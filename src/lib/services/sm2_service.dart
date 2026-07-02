import '../data/database_helper.dart';
import '../data/models/study_log.dart';
import '../data/models/user_progress.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/study_log_repository.dart';

/// SM-2 の4段階評価（◎〇△×）。
///
/// RFP v1.1 第5章に準拠する。DB（`user_progress.last_grade` / `study_log.grade`）
/// には記号文字列で保持するため、[symbol] で記号へ、[fromSymbol] で記号から相互変換する。
enum Grade {
  /// ◎（楽）: 簡単に思い出せた。ease_factor +0.10 / 初回interval 30日。
  easy(UserProgress.gradeEasy, 0.10),

  /// 〇（良）: 思い出せた。ease_factor ±0 / 初回interval 7日。
  good(UserProgress.gradeGood, 0.00),

  /// △（難）: 苦労して思い出せた。ease_factor −0.15 / 初回interval 3日。
  hard(UserProgress.gradeHard, -0.15),

  /// ×（忘）: 思い出せなかった。ease_factor −0.20 / interval 1日にリセット。
  fail(UserProgress.gradeFail, -0.20);

  const Grade(this.symbol, this.easeDelta);

  /// DB に保持する評価記号（◎〇△×）。
  final String symbol;

  /// ease_factor の増減値 Δ（RFP 5.2(2)）。
  final double easeDelta;

  /// 記号（◎〇△×）から [Grade] を得る。未知の記号は [ArgumentError]。
  static Grade fromSymbol(String symbol) {
    for (final g in Grade.values) {
      if (g.symbol == symbol) return g;
    }
    throw ArgumentError.value(symbol, 'symbol', '未知の評価記号です（◎〇△× のいずれか）');
  }

  /// 成功評価（◎〇△）なら true、× なら false（RFP 5.2(1)(3)(5)）。
  bool get isSuccess => this != Grade.fail;
}

/// SM-2 アルゴリズムと評価更新（gradeWord / applyGrade）を担うサービス。
///
/// RFP v1.1 第5.2〜5.3章の擬似コードに一字一句準拠して実装する。
/// データ層（[ProgressRepository] / [StudyLogRepository] / [UserProgress]）に依存し、
/// 「進捗レコードの取得／初期値新規作成 → SM-2 更新 → study_log へ1件追記」を
/// 同一トランザクション内で確定させる。
///
/// 進捗率（LV詳細画面）の算出は集計サービス（タスク3）の責務であり、本サービスは
/// 評価値マッピング（[gradeValue] / [progressValueOf]）を定数として提供するに留める。
class Sm2Service {
  Sm2Service({
    DatabaseHelper? helper,
    ProgressRepository? progressRepository,
    StudyLogRepository? studyLogRepository,
  })  : _helper = helper ?? DatabaseHelper.instance,
        _progressRepository =
            progressRepository ?? ProgressRepository(helper),
        _studyLogRepository =
            studyLogRepository ?? StudyLogRepository(helper);

  final DatabaseHelper _helper;
  final ProgressRepository _progressRepository;
  final StudyLogRepository _studyLogRepository;

  /// ease_factor の下限（RFP 5.1 / 5.2(2)）。上限は設けない。
  static const double kEaseFactorFloor = 1.3;

  /// ease_factor の初期値（未学習カード。RFP 5.1）。
  static const double kEaseFactorInitial = 2.5;

  /// △（難）の既存カードに適用する固定 interval 乗数（RFP 5.2(3)）。
  static const double kHardIntervalFactor = 1.2;

  /// 初回interval（今回の成功で repetitions が 1 になったとき）。RFP 5.2(3)。
  static const Map<Grade, int> kFirstInterval = {
    Grade.easy: 30,
    Grade.good: 7,
    Grade.hard: 3,
  };

  /// 進捗率算出用の評価値マッピング（RFP 5.4）。
  /// ◎=1.0 / 〇=0.5 / △=0.1 / ×・未学習=0。集計サービス（タスク3）が使用する。
  static const Map<Grade, double> gradeValue = {
    Grade.easy: 1.0,
    Grade.good: 0.5,
    Grade.hard: 0.1,
    Grade.fail: 0.0,
  };

  /// last_grade（記号 or 未学習=null）を進捗率の評価値へ変換する（RFP 5.4）。
  /// 未学習（null）・未知記号・× はすべて 0.0。
  static double progressValueOf(String? gradeSymbol) {
    if (gradeSymbol == null) return 0.0;
    for (final entry in gradeValue.entries) {
      if (entry.key.symbol == gradeSymbol) return entry.value;
    }
    return 0.0;
  }

  /// 評価押下時のメイン処理（RFP 5.3 gradeWord）。
  ///
  /// (0) [wordId] で `user_progress` を検索し、無ければ初期値レコードを新規作成する。
  /// 取得/作成したレコードへ [applyGrade] を適用して更新し、`study_log` へ1件だけ追記する。
  /// (0)作成〜更新〜ログ追記は同一トランザクション内で実行する。
  ///
  /// - [wordId]: 対象単語 ID。
  /// - [level]: 出題時のレベル（study_log へ冗長保持）。
  /// - [grade]: 押下した評価（◎〇△×）。
  /// - [sessionType]: `new` / `review`（[StudyLog.sessionNew] / [StudyLog.sessionReview]）。
  /// - [now]: 基準時刻。端末ローカル日付の当日（0:00 境界）を想定する。
  Future<void> gradeWord({
    required int wordId,
    required int level,
    required Grade grade,
    required String sessionType,
    required DateTime now,
  }) async {
    await _helper.transaction((txn) async {
      // (0) レコード取得 or 未学習単語なら初期値で新規作成（RFP 5.2(0)）。
      final existing =
          await _progressRepository.getByWordId(wordId, executor: txn);
      final progress = existing ??
          await _progressRepository.createInitial(wordId, executor: txn);

      // (1)〜(6) の SM-2 更新を適用し、確定値で永続化する。
      final updated = applyGrade(progress, grade, now);
      await _progressRepository.update(updated, executor: txn);

      // study_log へ1件だけ追記する（重複記録を避けるため記録は本メソッドが担う）。
      await _studyLogRepository.insert(
        StudyLog(
          wordId: wordId,
          level: level,
          sessionType: sessionType,
          grade: grade.symbol,
          studiedAt: _startOfDayIso(now),
        ),
        executor: txn,
      );
    });
  }

  /// SM-2 パラメータ更新（RFP 5.3 applyGrade）。純関数：更新後の [UserProgress] を返す。
  ///
  /// [progress] は取得済みレコード、または (0) で作成した初期値レコード。
  /// (1)〜(6) を RFP の順序どおり適用する。(3) の interval 算出には (1) 更新後の
  /// repetitions と (2) 更新後の ease_factor を用いる点に注意。
  UserProgress applyGrade(UserProgress progress, Grade grade, DateTime now) {
    // (1) repetitions: ◎〇△なら +1、×なら 0 にリセット。
    final repetitions = grade.isSuccess ? progress.repetitions + 1 : 0;

    // (2) ease_factor: Δ を加算し、下限 1.3 でクランプ（上限なし）。
    final easeFactor =
        _clampFloor(progress.easeFactor + grade.easeDelta, kEaseFactorFloor);

    // (3) interval_days: ※ (2)更新後の ease_factor を使用。
    final int intervalDays;
    if (grade == Grade.fail) {
      // × → 1日にリセット（repetitions は (1) で既に 0）。
      intervalDays = 1;
    } else if (repetitions == 1) {
      // 今回の成功で初めて repetitions が 1 ＝ 初回学習 → 初回interval。
      intervalDays = kFirstInterval[grade]!;
    } else {
      // repetitions >= 2 の既存カード → 乗算式。
      // ◎〇: ×ease_factor（更新後）／△: ×1.2 固定。
      final factor =
          (grade == Grade.hard) ? kHardIntervalFactor : easeFactor;
      intervalDays = (progress.intervalDays * factor).round();
    }

    // (4) 日時: last_reviewed_at=now（0:00 境界）、next_review_at=+interval_days 日。
    final base = _startOfDay(now);
    final nextReview = DateTime(base.year, base.month, base.day + intervalDays);

    // (5) 苦手カウント: × のときのみ累計 +1。
    final failCount =
        grade == Grade.fail ? progress.failCount + 1 : progress.failCount;

    // (6) last_grade: 押下値で上書き。
    return progress.copyWith(
      easeFactor: easeFactor,
      intervalDays: intervalDays,
      repetitions: repetitions,
      lastGrade: grade.symbol,
      failCount: failCount,
      lastReviewedAt: base.toIso8601String(),
      nextReviewAt: nextReview.toIso8601String(),
    );
  }

  /// 値を下限 [floor] でクランプする（`max(floor, value)`）。上限は設けない。
  double _clampFloor(double value, double floor) =>
      value < floor ? floor : value;

  /// 端末ローカル日付の当日 0:00（RFP 5.2「0:00 境界基準」）を返す。
  DateTime _startOfDay(DateTime now) => DateTime(now.year, now.month, now.day);

  /// 当日 0:00 の ISO8601 文字列。
  String _startOfDayIso(DateTime now) => _startOfDay(now).toIso8601String();
}

// ─────────────────────────────────────────────────────────────────────────
// テスト観点（RFP 5.2〜5.3・受け入れ基準 §11「SM-2・データ更新」）:
//
// 1. 未学習語の初回◎ → interval_days=30:
//    レコード無し（repetitions=0, ease_factor=2.5, interval=0）に ◎ を適用すると、
//    (1)で repetitions=1、(2)で ease_factor=2.60、(3)は repetitions==1 分岐で初回30日、
//    next_review_at = now(0:00) + 30日。〇→7日、△→3日 も同様。
//
// 2. ×リセット:
//    任意の状態に × を適用すると repetitions=0・interval_days=1 に強制リセットされ、
//    fail_count が +1（累計。復習で再度×でも加算）、ease_factor は −0.20（下限1.3で停止）。
//    next_review_at = now(0:00) + 1日。
//
// 3. ease_factor 下限 1.3:
//    ease_factor=1.4 に △（−0.15）を適用すると 1.25 ではなく下限 1.3 で停止する。
//    × の連続でも 1.3 を下回らない。上限は設けない（◎連続で 2.5 を超えて上昇する）。
//
// 4. 既存カードの乗算式（repetitions≧1 の成功）:
//    例）repetitions=2, interval_days=30, ease_factor=2.5 に ◎ を適用すると、
//    (2)で ease_factor=2.60、(3)は else 分岐で round(30 × 2.60)=78 日。
//    △ の場合は固定 factor 1.2 で round(30 × 1.2)=36 日（延長幅を抑制）。
//    ※乗算には (2)更新後の ease_factor を用いる。
//
// 5. 記録の単一性:
//    gradeWord は study_log へちょうど1件だけ追記する（applyGrade は追記しない）。
//    (0)新規作成〜更新〜ログ追記は同一トランザクションで確定する。
// ─────────────────────────────────────────────────────────────────────────
