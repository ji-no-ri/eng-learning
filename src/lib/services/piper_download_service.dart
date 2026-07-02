import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/piper_model_source.dart';

/// Piper TTS モデルのダウンロード／削除に失敗したことを表す例外。
///
/// RFP 4.5「ダウンロード仕様」に基づき、通信エラー・容量不足・HTTP エラー等の
/// 失敗を単一の型で呼び出し元へ通知する。呼び出し元（[TtsService.enablePiper]）は
/// 本例外を捕捉した場合、`tts_engine` と `piper_model_path` を変更せず状態Aを維持する。
class PiperDownloadException implements Exception {
  PiperDownloadException(this.message, {this.cause});

  /// 人間可読なエラー内容（UI へそのまま表示可能な日本語メッセージ）。
  final String message;

  /// 原因となった下位例外（`SocketException` / `FileSystemException` 等）。任意。
  final Object? cause;

  @override
  String toString() =>
      'PiperDownloadException: $message${cause == null ? '' : '（原因: $cause）'}';
}

/// Piper TTS の英語音声モデル（`.onnx`）を公開インフラから直接ダウンロードし、
/// 端末ローカルストレージへ保存・削除するサービス（RFP 4.5 / 第7章 / 第9章）。
///
/// - 取得元は [PiperModelSource]（`--dart-define` 注入）に集約する。GitHub Releases /
///   Hugging Face 等の既存公開インフラから直接取得し、自前ホスティングは持たない。
/// - チェックサムによる改ざん検証は初期版では実装しない（RFP 第9章の明示方針）。
/// - Piper の実行時合成はモデル本体（`.onnx`）に加えて設定ファイル（`.onnx.json`）を
///   必要とするため、両ファイルを同一ディレクトリへ取得し、`piper_model_path` には
///   モデル本体（`.onnx`）のパスを記録する（設定ファイルは同名 + `.json`）。
///
/// HTTP ダウンロードは（アーキテクチャ設計書の第一候補 `dio` に対し）実プロジェクトの
/// 依存構成（`pubspec.yaml`）に合わせ `http` パッケージのストリーミング受信で進捗を算出する。
/// テスト容易性のため [http.Client] とモデル保存先ディレクトリの解決を注入可能にする。
class PiperDownloadService {
  PiperDownloadService({
    http.Client? client,
    Future<Directory> Function()? modelDirProvider,
  })  : _client = client ?? http.Client(),
        _modelDirProvider = modelDirProvider ?? _defaultModelDir;

  final http.Client _client;
  final Future<Directory> Function() _modelDirProvider;

  /// モデルの既定保存先（アプリ専用サポートディレクトリ）。
  ///
  /// ユーザーの書類領域ではなくアプリ管理下の領域へ保存し、無効化時に確実に削除できるようにする。
  static Future<Directory> _defaultModelDir() =>
      getApplicationSupportDirectory();

  /// モデル（`.onnx`）と設定（`.onnx.json`）をダウンロードして保存し、
  /// モデル本体の保存先絶対パスを返す（`piper_model_path` に記録する値）。
  ///
  /// - [onProgress]: 0.0〜1.0 の進捗を通知する（主にモデル本体のバイト受信割合）。
  ///   サーバーが Content-Length を返さない場合は端点（開始 0.0・完了 1.0）のみ通知する。
  /// - 取得先（[PiperModelSource]）が未注入の場合や失敗時（通信エラー・HTTP エラー・
  ///   容量不足等）は部分ファイルを削除し [PiperDownloadException] を送出する。この場合、
  ///   呼び出し元は状態Aを維持する。
  Future<String> download({void Function(double progress)? onProgress}) async {
    if (!PiperModelSource.isConfigured) {
      // 取得先が実装時に注入されていない（--dart-define 未設定）。状態Aを維持する。
      throw PiperDownloadException(
        'Piper TTS モデルの取得先が設定されていません。ビルド時にモデル配布先を指定してください。',
      );
    }

    final dir = await _modelDirProvider();
    final modelPath = p.join(dir.path, PiperModelSource.modelFileName);
    final configPath = p.join(dir.path, PiperModelSource.configFileName);

    onProgress?.call(0.0);
    try {
      // 設定ファイル（小容量）を先に取得する。進捗の重みはモデル本体に割り当てる。
      await _downloadTo(PiperModelSource.configUrl, configPath);
      // モデル本体（大容量）を取得し、受信割合を進捗として通知する。
      await _downloadTo(PiperModelSource.modelUrl, modelPath,
          onProgress: onProgress);
      onProgress?.call(1.0);
      return modelPath;
    } catch (e) {
      // 中途半端に残ったファイルを掃除し、状態Aを保てるようにする。
      await _deleteQuietly(modelPath);
      await _deleteQuietly(configPath);
      if (e is PiperDownloadException) rethrow;
      throw PiperDownloadException(
        'モデルのダウンロードに失敗しました。通信状態や空き容量を確認してください。',
        cause: e,
      );
    }
  }

  /// ダウンロード済みモデルとその設定ファイルを端末から削除する（状態B→A）。
  ///
  /// [modelPath] はモデル本体（`.onnx`）のパス。設定ファイル（`.onnx.json`）は
  /// 同名 + `.json` を削除する。ファイルが無い場合は無視する。
  Future<void> deleteModel(String modelPath) async {
    await _deleteQuietly(modelPath);
    await _deleteQuietly('$modelPath.json');
  }

  /// 指定 URL を [destPath] へストリーミング保存する。
  ///
  /// Content-Length が得られる場合は受信バイト割合を [onProgress] へ通知する。
  Future<void> _downloadTo(
    String url,
    String destPath, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw PiperDownloadException(
        'サーバーからエラー応答を受信しました（HTTP ${response.statusCode}）。',
      );
    }

    final file = File(destPath);
    await file.parent.create(recursive: true);
    final total = response.contentLength ?? -1;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          final ratio = received / total;
          onProgress(ratio > 1.0 ? 1.0 : ratio);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// 例外を無視してファイルを削除する（存在しなければ何もしない）。
  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // クリーンアップ失敗は致命的でないため握りつぶす。
    }
  }
}
