import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/study_log.dart';

/// 学習量推移グラフの日別集計結果（1日1件）。
class DailyStudyCount {
  /// 日付（`YYYY-MM-DD`、端末ローカル）。
  final String date;

  /// その日の学習件数（新規＋復習の合算）。
  final int count;

  const DailyStudyCount({required this.date, required this.count});

  @override
  String toString() => 'DailyStudyCount(date: $date, count: $count)';
}

/// 学習ログ（`study_log`）へのデータアクセスを集約するリポジトリ。
///
/// 評価押下ごとの1件追記（追記専用）と、ストリーク・学習量推移用の期間集計を提供する。
/// 日付は ISO8601 文字列の先頭10文字（`YYYY-MM-DD`）で日単位に丸めて集計する。
class StudyLogRepository {
  StudyLogRepository([DatabaseHelper? helper])
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  Future<DatabaseExecutor> _resolve(DatabaseExecutor? executor) async =>
      executor ?? await _helper.database;

  /// 学習ログを1件追記する（RFP 5.3）。採番された id を返す。
  Future<int> insert(StudyLog log, {DatabaseExecutor? executor}) async {
    final db = await _resolve(executor);
    final values = log.toMap()..remove('id');
    return db.insert(DatabaseHelper.tableStudyLog, values);
  }

  /// 指定レベルの日別学習量（[fromIso], [toIso]) を日付昇順で集計する。
  ///
  /// RFP 4.2「学習量推移グラフ（このLV内）」。範囲は
  /// [`fromIso`（含む）, `toIso`（含まない）) の半開区間。
  Future<List<DailyStudyCount>> getDailyCountsByLevel(
    int level,
    String fromIso,
    String toIso, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _resolve(executor);
    final rows = await db.rawQuery(
      '''
      SELECT substr(studied_at, 1, 10) AS study_date, COUNT(*) AS study_count
      FROM ${DatabaseHelper.tableStudyLog}
      WHERE level = ?
        AND studied_at >= ?
        AND studied_at < ?
      GROUP BY substr(studied_at, 1, 10)
      ORDER BY study_date ASC
      ''',
      [level, fromIso, toIso],
    );
    return rows
        .map((r) => DailyStudyCount(
              date: r['study_date'] as String,
              count: (r['study_count'] as num).toInt(),
            ))
        .toList();
  }

  /// 学習を実施した日付（`YYYY-MM-DD`）の集合を、指定範囲について新しい順で返す。
  ///
  /// RFP 4.2 のストリーク（連続学習日数）・過去7日カレンダー算出用。全レベル横断。
  /// 連続日数のカウントは呼び出し側（Domain 層）が当日から遡って行う。
  /// [toIso] を渡すと [`fromIso`（含む）, `toIso`（含まない）) に限定する。
  Future<List<String>> getStudyDates(
    String fromIso, {
    String? toIso,
    DatabaseExecutor? executor,
  }) async {
    final db = await _resolve(executor);
    final hasTo = toIso != null;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT substr(studied_at, 1, 10) AS study_date
      FROM ${DatabaseHelper.tableStudyLog}
      WHERE studied_at >= ?
        ${hasTo ? 'AND studied_at < ?' : ''}
      ORDER BY study_date DESC
      ''',
      hasTo ? [fromIso, toIso] : [fromIso],
    );
    return rows.map((r) => r['study_date'] as String).toList();
  }
}
