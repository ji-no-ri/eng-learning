import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/word.dart';

/// 単語マスタ（`words`）へのデータアクセスを集約するリポジトリ。
///
/// レベル別取得・件数取得・新規学習セッション用の未学習語抽出、およびシード投入用の
/// 一括挿入を提供する。DB への直接アクセスは本リポジトリ内に閉じる。
class WordRepository {
  WordRepository([DatabaseHelper? helper])
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  Future<DatabaseExecutor> _resolve(DatabaseExecutor? executor) async =>
      executor ?? await _helper.database;

  /// 単一の単語を ID で取得する（存在しなければ null）。
  Future<Word?> getWord(int id, {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final rows = await db.query(
      DatabaseHelper.tableWords,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Word.fromMap(rows.first);
  }

  /// 指定レベルの全単語を id 昇順で取得する。
  Future<List<Word>> getWordsByLevel(int level,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final rows = await db.query(
      DatabaseHelper.tableWords,
      where: 'level = ?',
      whereArgs: [level],
      orderBy: 'id ASC',
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 指定レベルの総単語数を返す（進捗率の分母などに使用）。
  Future<int> countWordsByLevel(int level,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseHelper.tableWords} WHERE level = ?',
      [level],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 指定レベルの未学習語（`user_progress` にレコードが無い語）を
  /// id 昇順で最大 [limit] 件取得する（RFP 4.3 新規学習セッション）。
  Future<List<Word>> getUnlearnedWordsByLevel(
    int level, {
    int limit = 20,
    DatabaseExecutor? executor,
  }) async {
    final db = await _resolve(executor);
    final rows = await db.rawQuery(
      '''
      SELECT w.*
      FROM ${DatabaseHelper.tableWords} w
      LEFT JOIN ${DatabaseHelper.tableUserProgress} p ON p.word_id = w.id
      WHERE w.level = ?
        AND p.word_id IS NULL
      ORDER BY w.id ASC
      LIMIT ?
      ''',
      [level, limit],
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 単語を一括挿入する（シード投入用）。挿入件数を返す。
  ///
  /// 主に [SeedLoader] から呼び出される。id は自動採番に委ねる。
  Future<int> insertWords(List<Word> words,
      {DatabaseExecutor? executor}) async {
    if (words.isEmpty) return 0;
    final db = await _resolve(executor);
    final batch = db.batch();
    for (final w in words) {
      final map = w.toMap()..remove('id');
      batch.insert(DatabaseHelper.tableWords, map);
    }
    await batch.commit(noResult: true);
    return words.length;
  }
}
