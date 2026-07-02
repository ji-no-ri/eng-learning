import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/app_setting.dart';

/// アプリ設定（`app_settings`）へのデータアクセスを集約するリポジトリ。
///
/// 汎用の key/value 読み書きに加え、RFP 4.5 / データ設計書 7章で定義された
/// 想定キー（音声 ON/OFF・TTS エンジン・Piper モデルパス）向けの型付きアクセサを提供する。
class SettingsRepository {
  SettingsRepository([DatabaseHelper? helper])
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  // --- 想定キー（RFP 4.5 / データ設計書 7章） ---
  static const String keyAudioEnabled = 'audio_enabled';
  static const String keyTtsEngine = 'tts_engine';
  static const String keyPiperModelPath = 'piper_model_path';

  // --- tts_engine の取り得る値 ---
  static const String ttsEngineFlutter = 'flutter_tts';
  static const String ttsEnginePiper = 'piper';

  Future<DatabaseExecutor> _resolve(DatabaseExecutor? executor) async =>
      executor ?? await _helper.database;

  /// 指定キーの値を取得する（未設定は null）。
  Future<String?> getSetting(String key, {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final rows = await db.query(
      DatabaseHelper.tableAppSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// 指定キーへ値を書き込む（存在すれば更新、無ければ挿入）。
  Future<void> setSetting(String key, String? value,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    await db.insert(
      DatabaseHelper.tableAppSettings,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// すべての設定を取得する。
  Future<List<AppSetting>> getAllSettings({DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final rows = await db.query(DatabaseHelper.tableAppSettings);
    return rows.map(AppSetting.fromMap).toList();
  }

  // --- 型付き便宜アクセサ ---

  /// 読み上げ音声の ON/OFF。未設定時は既定 true（音声ON）でフォールバックする。
  Future<bool> getAudioEnabled({DatabaseExecutor? executor}) async {
    final raw = await getSetting(keyAudioEnabled, executor: executor);
    return raw == null ? true : raw == 'true';
  }

  Future<void> setAudioEnabled(bool enabled,
      {DatabaseExecutor? executor}) async {
    await setSetting(keyAudioEnabled, enabled ? 'true' : 'false',
        executor: executor);
  }

  /// 現在有効な TTS エンジン。未設定時は既定 `flutter_tts` でフォールバックする。
  Future<String> getTtsEngine({DatabaseExecutor? executor}) async {
    final raw = await getSetting(keyTtsEngine, executor: executor);
    return raw ?? ttsEngineFlutter;
  }

  Future<void> setTtsEngine(String engine,
      {DatabaseExecutor? executor}) async {
    await setSetting(keyTtsEngine, engine, executor: executor);
  }

  /// Piper TTS モデルの保存パス。未ダウンロード時は null。
  Future<String?> getPiperModelPath({DatabaseExecutor? executor}) async {
    return getSetting(keyPiperModelPath, executor: executor);
  }

  Future<void> setPiperModelPath(String? path,
      {DatabaseExecutor? executor}) async {
    await setSetting(keyPiperModelPath, path, executor: executor);
  }
}
