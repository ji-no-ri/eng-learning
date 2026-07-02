import '../data/database_helper.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/study_log_repository.dart';
import '../data/repositories/word_repository.dart';
import 'sm2_service.dart';

/// 苦手単語 TOP5（RFP 4.2）の1件を表す集計結果。
///
/// 当該レベル内で × を受けた累計回数（[failCount]）が多い単語を表現する。
/// 画面には [word] と [failCount]（×回数）を表示する。[lastReviewedAt] は
/// 同数時タイブレーク（最終復習日が古い順）の根拠として保持する。
class WeakWord {
  /// 対象単語 ID（`words.id`）。
  final int wordId;

  /// 英単語見出し（`words.word`）。画面表示用。
  final String word;

  /// × を押された累計回数（`user_progress.fail_count`）。画面表示用の「×回数」。
  final int failCount;

  /// 最終学習/復習日時（ISO8601 文字列 or null）。タイブレークの根拠。
  final String? lastReviewedAt;

  const WeakWord({
    required this.wordId,
    required this.word,
    required this.failCount,
    this.lastReviewedAt,
  });

  @override
  String toString() =>
      'WeakWord(wordId: $wordId, word: $word, failCount: $failCount)';
}

/// 完了画面（RFP 4.4）の理解度円グラフ用の評価分布。
///
/// 1セッション内で押下した評価（◎〇△×）の件数と割合を保持する。
/// RFP 4.4 の「円グラフ入力はセッション内で保持した評価配列から算出する方式」に対応し、
/// [AggregationService.gradeDistribution] は画面側が保持する評価リストから本型を組み立てる
/// （DB 集計ではなくセッション内配列を入力とする契約）。割合（[easyRatio] 等）は
/// [total] が 0 のとき 0.0 を返す。
class GradeDistribution {
  /// ◎（楽）の件数。
  final int easy;

  /// 〇（良）の件数。
  final int good;

  /// △（難）の件数。
  final int hard;

  /// ×（忘）の件数。
  final int fail;

  const GradeDistribution({
    this.easy = 0,
    this.good = 0,
    this.hard = 0,
    this.fail = 0,
  });

  /// 総件数（◎＋〇＋△＋×）。
  int get total => easy + good + hard + fail;

  /// ◎の割合（0.0〜1.0）。総件数 0 のときは 0.0。
  double get easyRatio => total == 0 ? 0.0 : easy / total;

  /// 〇の割合（0.0〜1.0）。総件数 0 のときは 0.0。
  double get goodRatio => total == 0 ? 0.0 : good / total;

  /// △の割合（0.0〜1.0）。総件数 0 のときは 0.0。
  double get hardRatio => total == 0 ? 0.0 : hard / total;

  /// ×の割合（0.0〜1.0）。総件数 0 のときは 0.0。
  double get failRatio => total == 0 ? 0.0 : fail / total;

  /// セッション内で押下した評価リストから分布を組み立てる（RFP 4.4）。
  factory GradeDistribution.fromGrades(Iterable<Grade> grades) {
    var easy = 0, good = 0, hard = 0, fail = 0;
    for (final g in grades) {
      switch (g) {
        case Grade.easy:
          easy++;
        case Grade.good:
          good++;
        case Grade.hard:
          hard++;
        case Grade.fail:
          fail++;
      }
    }
    return GradeDistribution(easy: easy, good: good, hard: hard, fail: fail);
  }

  @override
  String toString() =>
      'GradeDistribution(◎: $easy, 〇: $good, △: $hard, ×: $fail, total: $total)';
}

/// 画面表示用の集計を担うサービス（RFP 4.1／4.2／4.4／5.4）。
///
/// LV詳細画面（進捗率・ストリーク・復習予定・苦手TOP5・学習量推移）、
/// ホーム画面の復習ブロック判定、完了画面の理解度・単語数を提供する。
/// 集計は原則 SQL 側で行い（RFP 第6章のインデックスを活用）、
/// 日付境界を跨ぐ連続判定など一部のみ Dart 側で処理する。
///
/// 基準時刻は「端末ローカル日付の当日（0:00 境界）」で扱う（RFP 5.2）。
/// DB に保持する日時は SM-2 サービスと同じく `DateTime(y, m, d).toIso8601String()`
/// 形式（当日 0:00 のローカル ISO8601 文字列）で統一されているため、
/// 範囲比較は同形式の文字列で行い、日付キーは先頭10文字（`YYYY-MM-DD`）で丸める。
///
/// 最大 8000 語（1000語×8レベル）規模で実用的な応答性能となるよう、
/// 復習予定は `idx_progress_next_review`、苦手 TOP5 は `idx_progress_fail_count`、
/// ストリーク・学習量推移は `idx_study_log_studied_at` / `idx_study_log_level`、
/// LV 絞り込みは `idx_words_level` を利用する（RFP 第6章・第9章）。
class AggregationService {
  AggregationService({
    DatabaseHelper? helper,
    WordRepository? wordRepository,
    ProgressRepository? progressRepository,
    StudyLogRepository? studyLogRepository,
  })  : _helper = helper ?? DatabaseHelper.instance,
        _wordRepository = wordRepository ?? WordRepository(helper),
        _progressRepository = progressRepository ?? ProgressRepository(helper),
        _studyLogRepository =
            studyLogRepository ?? StudyLogRepository(helper);

  final DatabaseHelper _helper;
  final WordRepository _wordRepository;
  final ProgressRepository _progressRepository;
  final StudyLogRepository _studyLogRepository;

  // ─────────────────────────────────────────────────────────────────────
  // 1. 進捗率（RFP 4.2 / 5.4）
  // ─────────────────────────────────────────────────────────────────────

  /// 進捗率 = Σ(各単語の last_grade に対応する評価値) / 該当レベル総単語数（1000語）。
  ///
  /// 評価値：◎=1.0／〇=0.5／△=0.1／×・未学習=0（RFP 5.4）。
  /// 集計に用いるのは最新評価（`last_grade`）のみで、`study_log` は含めない。
  /// 分子は `words` を基点に `user_progress` を LEFT JOIN して SQL 側で集計するため、
  /// 進捗レコードが無い未学習語も分子 0 として自然に扱える。
  /// 戻り値は 0.0〜1.0（総単語数 0 のときは 0.0）。
  Future<double> progressRate(int level) async {
    final db = await _helper.database;
    // 分子（SUM(CASE ...)）を SQL 集計する。RFP 5.4 の評価値マッピングに一致。
    final rows = await db.rawQuery(
      '''
      SELECT SUM(CASE p.last_grade
                   WHEN '◎' THEN 1.0
                   WHEN '〇' THEN 0.5
                   WHEN '△' THEN 0.1
                   ELSE 0            -- '×' および last_grade IS NULL（未学習）は 0
                 END) AS numerator
      FROM   ${DatabaseHelper.tableWords} w
      LEFT   JOIN ${DatabaseHelper.tableUserProgress} p ON p.word_id = w.id
      WHERE  w.level = ?
      ''',
      [level],
    );
    final numerator = (rows.first['numerator'] as num?)?.toDouble() ?? 0.0;

    // 分母は該当レベルの総単語数（RFP 上 1000 語）。idx_words_level を利用。
    final total = await _wordRepository.countWordsByLevel(level);
    if (total <= 0) return 0.0;

    final rate = numerator / total;
    // 数値誤差・想定外データに対する保険として 0.0〜1.0 にクランプする。
    // num.clamp は num を返すため toDouble() で double に揃える。
    return rate.clamp(0.0, 1.0).toDouble();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 2. ストリーク・過去7日カレンダー（RFP 4.2）
  // ─────────────────────────────────────────────────────────────────────

  /// 連続学習日数（ストリーク）。
  ///
  /// 新規学習または復習を1回以上行った日を1日とし、当日から遡った直近の連続日数を返す。
  /// `study_log` の実施日集合（DISTINCT 日付）を取得し、日付境界の連続判定は Dart 側で行う
  /// （RFP 4.2・データ設計 6.5）。
  ///
  /// 当日（[today]）にまだ学習実施が無い場合は、進行中の当日を猶予として前日から遡って数える
  /// （朝の未学習時にストリークが 0 に見えないようにするための扱い）。
  Future<int> streakDays(DateTime today) async {
    // 実施日を全期間・新しい順（YYYY-MM-DD, DISTINCT）で取得する。
    final dates = await _studyLogRepository.getStudyDates(_farPastIso());
    final studiedDays = dates.toSet();

    // 起点は当日。当日が未実施なら前日を起点にする（進行中の当日を猶予）。
    var cursor = _startOfDay(today);
    if (!studiedDays.contains(_dateKey(cursor))) {
      cursor = _prevDay(cursor);
    }

    var streak = 0;
    while (studiedDays.contains(_dateKey(cursor))) {
      streak++;
      cursor = _prevDay(cursor);
    }
    return streak;
  }

  /// 過去7日間の各日の実施有無（曜日順・古→新）。
  ///
  /// 添字 0 が「6日前」、添字 6 が「当日」に対応する 7 要素の [bool] リストを返す
  /// （RFP 4.2 の過去7日カレンダー）。実施があった日を true とする。
  Future<List<bool>> last7DaysCalendar(DateTime today) async {
    final base = _startOfDay(today);
    final from = _addDays(base, -6); // 6日前 0:00（含む）
    final to = _addDays(base, 1); // 翌日 0:00（含まない）

    final dates = await _studyLogRepository.getStudyDates(
      _iso(from),
      toIso: _iso(to),
    );
    final studiedDays = dates.toSet();

    // 古→新（6日前 → 当日）の順で実施有無を並べる。
    final result = <bool>[];
    for (var i = 6; i >= 0; i--) {
      result.add(studiedDays.contains(_dateKey(_addDays(base, -i))));
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 3. 復習予定数（全レベル横断。LV詳細でも全レベル共通の数字）（RFP 4.1 / 4.2）
  // ─────────────────────────────────────────────────────────────────────

  /// `next_review_at ≦ 今日` の単語数（全レベル横断）。
  ///
  /// ホーム画面「今日の復習ブロック」の表示判定（1語以上で表示）や、
  /// 完了画面（復習）の「残りの復習対象数」に用いる（RFP 4.1・4.4）。
  Future<int> reviewCountToday(DateTime today) {
    // next_review_at は当日 0:00 で保持されるため、当日 0:00 以下で当日ぶんまで含む。
    return _progressRepository.countDue(_iso(_startOfDay(today)));
  }

  /// `next_review_at = 明日` の単語数（全レベル横断）。
  ///
  /// 翌日 0:00（含む）〜翌々日 0:00（含まない）の1日分（RFP 4.2・データ設計 6.2）。
  Future<int> reviewCountTomorrow(DateTime today) {
    final base = _startOfDay(today);
    final tomorrow = _addDays(base, 1); // 翌日 0:00
    final dayAfter = _addDays(base, 2); // 翌々日 0:00
    return _progressRepository.countDueInRange(_iso(tomorrow), _iso(dayAfter));
  }

  /// `next_review_at` が今日から7日以内の単語数（全レベル横断）。
  ///
  /// 当日 0:00（含む）〜7日後 0:00（含まない）（RFP 4.2・データ設計 6.2）。
  Future<int> reviewCountThisWeek(DateTime today) {
    final base = _startOfDay(today);
    final weekEnd = _addDays(base, 7); // 7日後 0:00
    return _progressRepository.countDueInRange(_iso(base), _iso(weekEnd));
  }

  // ─────────────────────────────────────────────────────────────────────
  // 4. 苦手単語 TOP5（このLV内）（RFP 4.2）
  // ─────────────────────────────────────────────────────────────────────

  /// 苦手単語 TOP5（当該レベル内）。
  ///
  /// `fail_count` 降順、同数時は `last_reviewed_at` が古い順、最大5件（RFP 4.2）。
  /// × を一度も受けていない語（`fail_count = 0`）は苦手として表示しない。
  /// `idx_progress_fail_count` が主ソートを支える（データ設計 6.4）。
  Future<List<WeakWord>> weakWordsTop5(int level) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
      SELECT w.id               AS word_id,
             w.word             AS word,
             p.fail_count       AS fail_count,
             p.last_reviewed_at AS last_reviewed_at
      FROM   ${DatabaseHelper.tableUserProgress} p
      JOIN   ${DatabaseHelper.tableWords} w ON w.id = p.word_id
      WHERE  w.level = ?
        AND  p.fail_count > 0
      ORDER  BY p.fail_count DESC,        -- ×回数が多い順
                p.last_reviewed_at ASC    -- 同数なら最終復習日が古い順
      LIMIT  5
      ''',
      [level],
    );
    return rows
        .map((r) => WeakWord(
              wordId: (r['word_id'] as num).toInt(),
              word: r['word'] as String,
              failCount: (r['fail_count'] as num).toInt(),
              lastReviewedAt: r['last_reviewed_at'] as String?,
            ))
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 5. 学習量推移（過去7日・このLV内）（RFP 4.2）
  // ─────────────────────────────────────────────────────────────────────

  /// 当該レベル内の日別学習数（新規＋復習の合算）を過去7日ぶん、古→新で返す。
  ///
  /// 添字 0 が「6日前」、添字 6 が「当日」に対応する 7 要素の [int] リスト。
  /// 実施の無い日は 0（RFP 4.2 の学習量推移グラフ）。`study_log` を集計元とし、
  /// `idx_study_log_studied_at` / `idx_study_log_level` を利用する（データ設計 6.5）。
  Future<List<int>> studyVolume7Days(int level, DateTime today) async {
    final base = _startOfDay(today);
    final from = _addDays(base, -6); // 6日前 0:00（含む）
    final to = _addDays(base, 1); // 翌日 0:00（含まない）

    final counts = await _studyLogRepository.getDailyCountsByLevel(
      level,
      _iso(from),
      _iso(to),
    );
    // 日付（YYYY-MM-DD）→件数の対応表を作る。
    final byDate = {for (final c in counts) c.date: c.count};

    // 古→新（6日前 → 当日）の順で日別件数を並べ、欠測日は 0 とする。
    final result = <int>[];
    for (var i = 6; i >= 0; i--) {
      result.add(byDate[_dateKey(_addDays(base, -i))] ?? 0);
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 6. 完了画面（RFP 4.4）
  // ─────────────────────────────────────────────────────────────────────

  /// 理解度の評価分布（◎〇△×の件数・割合）。
  ///
  /// RFP 4.4 の理解度円グラフ用。入力はセッション内で保持した評価リスト
  /// （画面側が押下順に蓄積した [Grade] 配列）であり、DB 集計ではない
  /// （画面側との契約：完了画面はセッション内配列を渡す）。
  Future<GradeDistribution> gradeDistribution(Iterable<Grade> sessionGrades) {
    return Future.value(GradeDistribution.fromGrades(sessionGrades));
  }

  /// 当該レベルの総単語数（RFP 上は常に 1000）。
  ///
  /// 完了画面（新規学習）の「このレベルの総単語数」表示に用いる。
  /// 実データを SQL で数える（`idx_words_level` を利用）。RFP のレベル定義では 1000。
  Future<int> totalWordsInLevel(int level) {
    return _wordRepository.countWordsByLevel(level);
  }

  /// 当該レベル内の学習済み単語数（`user_progress` にレコードがある単語数）。
  ///
  /// 完了画面（新規学習）の「累計学習済み単語数（このレベル内）」表示に用いる（RFP 4.4）。
  Future<int> learnedCountInLevel(int level) async {
    final db = await _helper.database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM   ${DatabaseHelper.tableUserProgress} p
      JOIN   ${DatabaseHelper.tableWords} w ON w.id = p.word_id
      WHERE  w.level = ?
      ''',
      [level],
    );
    return (result.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 復習残数（＝今日時点の復習対象数）。完了画面（復習）の「残りの復習対象数」に用いる。
  ///
  /// 全レベル横断で `next_review_at ≦ 今日` の単語数を返す（[reviewCountToday] と同義）。
  Future<int> remainingReviewCount(DateTime today) => reviewCountToday(today);

  // ─────────────────────────────────────────────────────────────────────
  // 日付ユーティリティ（端末ローカル・当日 0:00 境界）
  // ─────────────────────────────────────────────────────────────────────

  /// 端末ローカル日付の当日 0:00 を返す（RFP 5.2「0:00 境界基準」）。
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [d]（0:00 想定）から暦日で [days] 日ずらした 0:00 を返す。
  /// 月末・年跨ぎは DateTime のコンストラクタ正規化に委ねる。
  DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// 前日 0:00。
  DateTime _prevDay(DateTime d) => _addDays(d, -1);

  /// 範囲比較用の ISO8601 文字列（当日 0:00 のローカル形式）。
  /// SM-2 サービス／各リポジトリが保持する日時形式と一致させる。
  String _iso(DateTime d) => _startOfDay(d).toIso8601String();

  /// 日付キー（`YYYY-MM-DD`）。ISO8601 文字列の先頭10文字に相当し、
  /// リポジトリの `substr(studied_at, 1, 10)` 集計結果と突き合わせられる。
  String _dateKey(DateTime d) => _iso(d).substring(0, 10);

  /// ストリークの全期間走査に用いる十分に過去の下限（ISO8601）。
  String _farPastIso() => DateTime(1, 1, 1).toIso8601String();
}
