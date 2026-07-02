import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import '../data/repositories/settings_repository.dart';
import 'piper_download_service.dart';

/// Piper TTS のオンデバイス実行時合成を抽象化するインターフェース。
///
/// Piper のオンデバイス合成は利用可能な Flutter プラグイン／FFI 実装に依存し、
/// 環境によっては実装が困難なため、合成呼び出し箇所を本インターフェースで抽象化して
/// 差し替え可能にする（RFP「注」の設計方針）。
///
/// 実装が用意できない環境では既定の [UnavailablePiperSynthesizer] を用いる。この場合
/// [isAvailable] が false を返し、[TtsService.speak] は自動的に flutter_tts へ
/// フォールバックする（`tts_engine == 'piper'` の設定であっても再生自体は途切れない）。
/// 実際の合成エンジン（FFI/プラグイン）が用意でき次第、本インターフェースの実装を
/// [TtsService] に注入するだけで差し替えられる。
abstract class PiperSynthesizer {
  /// この環境で Piper のオンデバイス合成が利用可能か。
  bool get isAvailable;

  /// [modelPath]（`.onnx`）を用いて [text] を実行時に合成・再生する（都度生成）。
  ///
  /// 事前生成した音声ファイルの再生ではなく、テキストからのリアルタイム合成であること
  /// （RFP 4.5「音声再生ロジック」）。合成・再生に失敗した場合は例外を送出してよい。
  Future<void> synthesizeAndPlay(String text, String modelPath);

  /// 再生中の合成音声を停止する。
  Future<void> stop();
}

/// Piper 合成の実装が未提供の環境向けの既定実装（常に利用不可）。
///
/// [isAvailable] は false を返し、合成は行わない。これにより [TtsService] は
/// flutter_tts へ安全にフォールバックする。実装差し替え時はこのクラスの代わりに
/// 具体的な [PiperSynthesizer] 実装を [TtsService] へ注入する。
class UnavailablePiperSynthesizer implements PiperSynthesizer {
  const UnavailablePiperSynthesizer();

  @override
  bool get isAvailable => false;

  @override
  Future<void> synthesizeAndPlay(String text, String modelPath) async {
    throw UnsupportedError(
      'この環境では Piper TTS のオンデバイス合成が利用できません（PiperSynthesizer 未実装）。',
    );
  }

  @override
  Future<void> stop() async {}
}

/// 全画面共通の音声再生サービス（RFP 4.5 / 第7章）。
///
/// 単語表示のたびにテキストから実行時にリアルタイム合成して再生する方式で、
/// 音声ファイルの事前生成・同梱・キャッシュは行わない。エンジンは以下のロジックで選択する
/// （RFP 4.5「音声再生ロジック」）:
///
/// ```
/// if tts_engine == 'piper' かつ モデルファイルが存在（かつ合成実装が利用可能）:
///     Piper でオンデバイス合成・再生
/// else:
///     flutter_tts で OS 標準音声を実行時生成・再生（フォールバック）
/// ```
///
/// 依存はタスク1の [SettingsRepository]（`audio_enabled` / `tts_engine` /
/// `piper_model_path` の永続化）と [PiperDownloadService]（モデル取得・削除）。
/// flutter_tts と Piper 合成実装は差し替え可能なようコンストラクタで注入できる。
class TtsService {
  TtsService({
    SettingsRepository? settingsRepository,
    PiperDownloadService? downloadService,
    PiperSynthesizer piperSynthesizer = const UnavailablePiperSynthesizer(),
    FlutterTts? flutterTts,
  })  : _settings = settingsRepository ?? SettingsRepository(),
        _downloadService = downloadService ?? PiperDownloadService(),
        _piper = piperSynthesizer,
        _tts = flutterTts ?? FlutterTts();

  final SettingsRepository _settings;
  final PiperDownloadService _downloadService;
  final PiperSynthesizer _piper;
  final FlutterTts _tts;

  /// flutter_tts の読み上げ言語（英単語の学習アプリのため英語固定）。
  static const String _ttsLanguage = 'en-US';

  /// flutter_tts の初期化（言語設定・完了待ち）を一度だけ行うためのフラグ。
  bool _flutterTtsConfigured = false;

  // ─────────────────────────────────────────────────────────────────────
  // 音声 ON/OFF（RFP 4.5 / 受け入れ基準 §11）
  // ─────────────────────────────────────────────────────────────────────

  /// 読み上げ音声が有効か（`app_settings.audio_enabled`）。未設定時は既定 true。
  Future<bool> isAudioEnabled() => _settings.getAudioEnabled();

  /// 読み上げ音声の ON/OFF を切り替え、`app_settings.audio_enabled` へ即時永続化する。
  Future<void> setAudioEnabled(bool enabled) async {
    await _settings.setAudioEnabled(enabled);
    // OFF にした場合は再生中の音声を止める。
    if (!enabled) await stop();
  }

  // ─────────────────────────────────────────────────────────────────────
  // エンジン状態（RFP 4.5）
  // ─────────────────────────────────────────────────────────────────────

  /// 現在“実際に使用される”TTS エンジン（'flutter_tts' or 'piper'）を返す。
  ///
  /// `tts_engine == 'piper'` かつモデルファイルが存在し、合成実装が利用可能な場合のみ
  /// `'piper'` を返す。それ以外は `'flutter_tts'`（フォールバック）を返す。
  Future<String> currentEngine() async {
    return await _shouldUsePiper()
        ? SettingsRepository.ttsEnginePiper
        : SettingsRepository.ttsEngineFlutter;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 再生（RFP 4.5「音声再生ロジック」/ 第7章 オフライン動作）
  // ─────────────────────────────────────────────────────────────────────

  /// [text] を実行時合成して再生する。
  ///
  /// - `audio_enabled == false` のときは無音（何もしない）。
  /// - `audio_enabled == true` のときは Piper（条件を満たす場合）または
  ///   flutter_tts でリアルタイム合成・再生する。
  /// - Piper 合成が実行時に失敗した場合は flutter_tts へフォールバックする。
  Future<void> speak(String text) async {
    if (!await isAudioEnabled()) return;
    if (text.trim().isEmpty) return;

    if (await _shouldUsePiper()) {
      final modelPath = await _settings.getPiperModelPath();
      try {
        await _piper.synthesizeAndPlay(text, modelPath!);
        return;
      } catch (_) {
        // 実行時合成に失敗した場合でも再生を途切れさせず flutter_tts へフォールバックする。
      }
    }
    await _speakWithFlutterTts(text);
  }

  /// 再生中の音声（Piper / flutter_tts の両方）を停止する。
  Future<void> stop() async {
    await _piper.stop();
    await _tts.stop();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Piper 有効化／無効化（RFP 4.5 状態遷移 A⇄B）
  // ─────────────────────────────────────────────────────────────────────

  /// Piper TTS を有効化する（状態A→B）。
  ///
  /// 公開インフラから英語音声モデル（`.onnx`）を HTTP でダウンロードし
  /// （進捗を [onProgress] で 0.0〜1.0 通知）、端末へ保存後に
  /// `piper_model_path` を記録し `tts_engine` を `'piper'` へ切り替える。
  ///
  /// ダウンロード失敗時は [PiperDownloadException] を送出し、`tts_engine` と
  /// `piper_model_path` は変更しない（状態Aを維持。RFP 4.5 状態遷移表）。
  Future<void> enablePiper({void Function(double progress)? onProgress}) async {
    // ダウンロードが成功して初めて設定を書き換える。失敗時は例外が伝播し状態Aのまま。
    final modelPath = await _downloadService.download(onProgress: onProgress);
    await _settings.setPiperModelPath(modelPath);
    await _settings.setTtsEngine(SettingsRepository.ttsEnginePiper);
  }

  /// Piper TTS を無効化する（状態B→A）。
  ///
  /// ダウンロード済みモデルファイル（と設定ファイル）を端末から削除し、
  /// `piper_model_path` を NULL、`tts_engine` を `'flutter_tts'` へ戻す。
  Future<void> disablePiper() async {
    // 再生中に削除すると不整合になり得るため、先に停止する。
    await stop();
    final modelPath = await _settings.getPiperModelPath();
    if (modelPath != null) {
      await _downloadService.deleteModel(modelPath);
    }
    await _settings.setPiperModelPath(null);
    await _settings.setTtsEngine(SettingsRepository.ttsEngineFlutter);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 内部ヘルパー
  // ─────────────────────────────────────────────────────────────────────

  /// Piper を使用すべきか（`tts_engine=='piper'` かつモデル実在かつ合成実装が利用可能）。
  Future<bool> _shouldUsePiper() async {
    if (!_piper.isAvailable) return false;
    final engine = await _settings.getTtsEngine();
    if (engine != SettingsRepository.ttsEnginePiper) return false;
    final modelPath = await _settings.getPiperModelPath();
    if (modelPath == null || modelPath.isEmpty) return false;
    return File(modelPath).exists();
  }

  /// flutter_tts でリアルタイム合成・再生する（フォールバック経路）。
  Future<void> _speakWithFlutterTts(String text) async {
    await _ensureFlutterTtsConfigured();
    // 直前の再生が残っている場合に備えて停止してから発話する。
    await _tts.stop();
    await _tts.speak(text);
  }

  /// flutter_tts の言語・完了待ち設定を初回のみ適用する。
  Future<void> _ensureFlutterTtsConfigured() async {
    if (_flutterTtsConfigured) return;
    await _tts.setLanguage(_ttsLanguage);
    // speak() が発話完了まで待つようにする（自動で次単語へ進む UI 制御を容易にする）。
    await _tts.awaitSpeakCompletion(true);
    _flutterTtsConfigured = true;
  }
}
