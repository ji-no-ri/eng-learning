import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/user_progress.dart';

/// 学習進捗（`user_progress`）へのデータアクセスを集約するリポジトリ。
///
/// word_id による取得／初期値新規作成／更新（upsert）と、`next_review_at` 条件に
/// よる復習対象抽出・件数集計を提供する。SM-2 の計算そのものは呼び出し側（Domain 層）
/// が行い、本リポジトリは確定後の値を永続化・参照する。
///
/// 評価押下時に「進捗更新 ＋ study_log 追記」を同一トランザクションで確定させる場合は、
/// [DatabaseHelper.transaction] で得た [Transaction] を各メソッドの `executor` に渡す。
class ProgressRepository {
  ProgressRepository([DatabaseHelper? helper])
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  Future<DatabaseExecutor> _resolve(DatabaseExecutor? executor) async =>
      executor ?? await _helper.database;

  /// word_id で進捗を取得する（未学習＝レコード無しなら null）。
  Future<UserProgress?> getByWordId(int wordId,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final rows = await db.query(
      DatabaseHelper.tableUserProgress,
      where: 'word_id = ?',
      whereArgs: [wordId],
      limit: 1,
    );
    return rows.isEmpty ? null : UserProgress.fromMap(rows.first);
  }

  /// RFP 5.2(0) の初期値でレコードを新規作成し、id を付与した進捗を返す。
  Future<UserProgress> createInitial(int wordId,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final initial = UserProgress.initial(wordId);
    final id = await db.insert(
      DatabaseHelper.tableUserProgress,
      initial.toMap(),
    );
    return initial.copyWith(id: id);
  }

  /// 進捗を更新する（word_id で特定）。更新行数を返す。
  Future<int> update(UserProgress progress,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final values = progress.toMap()..remove('id');
    return db.update(
      DatabaseHelper.tableUserProgress,
      values,
      where: 'word_id = ?',
      whereArgs: [progress.wordId],
    );
  }

  /// 進捗を挿入または更新する。
  ///
  /// word_id の行が存在すれば更新、無ければ挿入する（1語1進捗を維持）。
  /// 確定後の [UserProgress]（挿入時は採番済み id を含む）を返す。
  Future<UserProgress> upsert(UserProgress progress,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final existing = await getByWordId(progress.wordId, executor: db);
    if (existing == null) {
      final values = progress.toMap()..remove('id');
      final id =
          await db.insert(DatabaseHelper.tableUserProgress, values);
      return progress.copyWith(id: id);
    }
    await update(progress, executor: db);
    return progress.copyWith(id: existing.id);
  }

  /// 復習対象（`next_review_at ≦ now`、全レベル横断、古い順）を取得する。
  ///
  /// RFP 4.3 復習セッション固有仕様。件数上限なし。[nowIso] は端末ローカル当日
  /// 0:00 の ISO8601 文字列。
  Future<List<UserProgress>> getDueForReview(String nowIso,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final rows = await db.query(
      DatabaseHelper.tableUserProgress,
      where: 'next_review_at IS NOT NULL AND next_review_at <= ?',
      whereArgs: [nowIso],
      orderBy: 'next_review_at ASC',
    );
    return rows.map(UserProgress.fromMap).toList();
  }

  /// 復習対象の件数（`next_review_at ≦ now`、全レベル横断）を返す。
  /// ホーム画面「今日の復習ブロック」の件数に対応する（RFP 4.1）。
  Future<int> countDue(String nowIso, {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseHelper.tableUserProgress} '
      'WHERE next_review_at IS NOT NULL AND next_review_at <= ?',
      [nowIso],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 指定範囲 [`startInclusive`, `endExclusive`) に `next_review_at` が入る件数を返す。
  ///
  /// RFP 4.2 の復習予定（全レベル共通）に用いる。境界（当日 0:00 起点の翌日／7日後等）は
  /// 呼び出し側で算出して ISO8601 文字列で渡す。
  Future<int> countDueInRange(String startInclusive, String endExclusive,
      {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseHelper.tableUserProgress} '
      'WHERE next_review_at IS NOT NULL '
      'AND next_review_at >= ? AND next_review_at < ?',
      [startInclusive, endExclusive],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
