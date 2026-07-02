import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite データベースの初期化・オープン・マイグレーションを担うヘルパー。
///
/// RFP v1.1 第6章「データベース設計（SQLite）」のスキーマ（テーブル・インデックス・
/// 既定設定）を厳密に再現する。稼働用 DB は端末の書き込み可能領域に配置し、
/// アプリ全体で単一インスタンス（[instance]）を共有する。
///
/// 単語（words）の実データ投入は本ヘルパーの責務ではなく、[SeedLoader] が担う。
/// 本ヘルパーは「スキーマ生成」と「app_settings 既定値の投入」のみを行う。
class DatabaseHelper {
  DatabaseHelper._internal();

  /// アプリ全体で共有する単一インスタンス。
  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// 稼働用データベースファイル名。
  static const String dbFileName = 'jacet_vocab.db';

  /// スキーマバージョン。初期版は 1（RFP 第6章確定スキーマ）。
  static const int dbVersion = 1;

  // --- テーブル名（リポジトリ層から参照する公開定数） ---
  static const String tableWords = 'words';
  static const String tableUserProgress = 'user_progress';
  static const String tableStudyLog = 'study_log';
  static const String tableAppSettings = 'app_settings';

  Database? _db;

  /// 稼働用データベースを取得する（未オープンなら初期化してオープンする）。
  ///
  /// 初回オープン時に [onCreate] でスキーマ生成・既定設定投入が行われる。
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, dbFileName);
    return openDatabase(
      path,
      version: dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 接続ごとの構成。外部キー制約を有効化する
  /// （sqflite は既定で無効のため、接続確立時に毎回設定する）。
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  /// 初回作成時のスキーマ生成・インデックス作成・既定設定投入。
  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // --- words（静的データ、事前投入）RFP 6章 ---
    // audio_file_path は将来の Piper TTS 事前生成音声用の予約カラム。初期版は常に NULL。
    batch.execute('''
      CREATE TABLE $tableWords (
        id INTEGER PRIMARY KEY,
        word TEXT UNIQUE NOT NULL,
        level INTEGER NOT NULL,
        part_of_speech TEXT,
        pronunciation TEXT,
        definition_ja TEXT,
        example_en TEXT,
        example_ja TEXT,
        inflections_json TEXT,
        collocations_json TEXT,
        audio_file_path TEXT
      );
    ''');

    // --- user_progress（学習進捗・SM-2 パラメータ）RFP 6章 ---
    // word_id は UNIQUE により「1語につき進捗 0/1 件」を保証する。
    batch.execute('''
      CREATE TABLE $tableUserProgress (
        id INTEGER PRIMARY KEY,
        word_id INTEGER NOT NULL UNIQUE,
        ease_factor REAL DEFAULT 2.5,
        interval_days INTEGER DEFAULT 0,
        repetitions INTEGER DEFAULT 0,
        last_grade TEXT,
        fail_count INTEGER DEFAULT 0,
        last_reviewed_at TIMESTAMP,
        next_review_at TIMESTAMP,
        FOREIGN KEY(word_id) REFERENCES $tableWords(id)
      );
    ''');

    // --- study_log（学習量推移グラフ・ストリーク計算用、追記専用）RFP 6章 ---
    batch.execute('''
      CREATE TABLE $tableStudyLog (
        id INTEGER PRIMARY KEY,
        word_id INTEGER NOT NULL,
        level INTEGER NOT NULL,
        session_type TEXT,
        grade TEXT,
        studied_at TIMESTAMP,
        FOREIGN KEY(word_id) REFERENCES $tableWords(id)
      );
    ''');

    // --- app_settings（キー・バリュー設定）RFP 6章 ---
    batch.execute('''
      CREATE TABLE $tableAppSettings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');

    // --- インデックス（RFP 6章の定義どおり） ---
    batch.execute(
        'CREATE INDEX idx_words_level ON $tableWords(level);');
    batch.execute(
        'CREATE INDEX idx_progress_next_review ON $tableUserProgress(next_review_at);');
    batch.execute(
        'CREATE INDEX idx_progress_fail_count ON $tableUserProgress(fail_count);');
    batch.execute(
        'CREATE INDEX idx_study_log_studied_at ON $tableStudyLog(studied_at);');
    batch.execute(
        'CREATE INDEX idx_study_log_level ON $tableStudyLog(level);');

    // --- app_settings 既定値の投入（RFP 4.5 / データ設計書 7章） ---
    // piper_model_path は未ダウンロードを表す NULL を明示的に投入する。
    batch.insert(tableAppSettings, {'key': 'audio_enabled', 'value': 'true'});
    batch.insert(
        tableAppSettings, {'key': 'tts_engine', 'value': 'flutter_tts'});
    batch.insert(tableAppSettings, {'key': 'piper_model_path', 'value': null});

    await batch.commit(noResult: true);
  }

  /// スキーマ移行。初期版は version=1 のみで移行なし。
  /// 将来 audio_file_path を用いた事前生成方式へ切り替える等の変更時にここで対応する。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 現時点では移行処理なし。
  }

  /// 書き込みを1トランザクションにまとめて実行する。
  ///
  /// 評価押下時の「user_progress 更新 ＋ study_log 追記」を同一トランザクションで
  /// 確定させる用途（RFP 5.3）に用いる。各リポジトリの書き込みメソッドは
  /// `executor` 引数に渡された [Transaction] を利用できる。
  Future<T> transaction<T>(
      Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction<T>(action);
  }

  /// データベースをクローズする（主にテスト・終了処理用）。
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
