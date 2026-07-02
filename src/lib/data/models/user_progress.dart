/// 学習進捗・SM-2 パラメータ（`user_progress` テーブル）の不変モデル。
///
/// RFP v1.1 第5章（SM-2）・第6章のカラム定義に一致する。1語につき 0/1 件
/// （`word_id` は UNIQUE）。未学習単語は行が存在せず、初回評価時に [initial] の
/// 初期値でレコードを新規作成してから SM-2 更新を適用する（RFP 5.2(0)）。
///
/// 日時（`last_reviewed_at` / `next_review_at`）は ISO8601 文字列（端末ローカル、
/// 当日 0:00 境界基準）で保持する。パース済みの [DateTime] は
/// [lastReviewedAtDate] / [nextReviewAtDate] で得る。
class UserProgress {
  /// SM-2 の評価値として許容される記号（`last_grade`）。
  static const String gradeEasy = '◎'; // 楽に想起
  static const String gradeGood = '〇'; // 想起できた
  static const String gradeHard = '△'; // 苦労して想起
  static const String gradeFail = '×'; // 想起できず

  /// 進捗の一意識別子。DB 未保存は null。
  final int? id;

  /// 対象単語 ID（NOT NULL, UNIQUE, FK → words.id）。
  final int wordId;

  /// 易しさ係数（初期値 2.5、下限 1.3）。
  final double easeFactor;

  /// 次回復習までの日数。未学習は 0。
  final int intervalDays;

  /// 連続成功回数。× で 0 にリセット。
  final int repetitions;

  /// 最新の評価値（`◎` `〇` `△` `×`）。未学習は null。進捗率算出に用いる唯一の評価。
  final String? lastGrade;

  /// × を押された累計回数（苦手単語 TOP5 用）。
  final int failCount;

  /// 最終学習/復習日時（ISO8601 文字列）。未学習は null。
  final String? lastReviewedAt;

  /// 次回復習予定日時（ISO8601 文字列）。未学習は null。
  final String? nextReviewAt;

  const UserProgress({
    this.id,
    required this.wordId,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.lastGrade,
    this.failCount = 0,
    this.lastReviewedAt,
    this.nextReviewAt,
  });

  /// RFP 5.2(0) の初期値レコードを生成する（未学習単語の初回評価用）。
  /// ease_factor=2.5 / interval_days=0 / repetitions=0 / fail_count=0 /
  /// last_grade=null / last_reviewed_at=null / next_review_at=null。
  factory UserProgress.initial(int wordId) => UserProgress(wordId: wordId);

  /// `last_reviewed_at` をパースした [DateTime]（不正/未設定は null）。
  DateTime? get lastReviewedAtDate {
    final raw = lastReviewedAt;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// `next_review_at` をパースした [DateTime]（不正/未設定は null）。
  DateTime? get nextReviewAtDate {
    final raw = nextReviewAt;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// DB 行（Map）から生成する。
  factory UserProgress.fromMap(Map<String, dynamic> map) => UserProgress(
        id: map['id'] as int?,
        wordId: map['word_id'] as int,
        easeFactor: (map['ease_factor'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (map['interval_days'] as num?)?.toInt() ?? 0,
        repetitions: (map['repetitions'] as num?)?.toInt() ?? 0,
        lastGrade: map['last_grade'] as String?,
        failCount: (map['fail_count'] as num?)?.toInt() ?? 0,
        lastReviewedAt: map['last_reviewed_at'] as String?,
        nextReviewAt: map['next_review_at'] as String?,
      );

  /// DB 行（Map）へ変換する。id が null の場合はキーを含めない。
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'word_id': wordId,
        'ease_factor': easeFactor,
        'interval_days': intervalDays,
        'repetitions': repetitions,
        'last_grade': lastGrade,
        'fail_count': failCount,
        'last_reviewed_at': lastReviewedAt,
        'next_review_at': nextReviewAt,
      };

  UserProgress copyWith({
    int? id,
    int? wordId,
    double? easeFactor,
    int? intervalDays,
    int? repetitions,
    String? lastGrade,
    int? failCount,
    String? lastReviewedAt,
    String? nextReviewAt,
  }) =>
      UserProgress(
        id: id ?? this.id,
        wordId: wordId ?? this.wordId,
        easeFactor: easeFactor ?? this.easeFactor,
        intervalDays: intervalDays ?? this.intervalDays,
        repetitions: repetitions ?? this.repetitions,
        lastGrade: lastGrade ?? this.lastGrade,
        failCount: failCount ?? this.failCount,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      );

  @override
  String toString() =>
      'UserProgress(wordId: $wordId, ef: $easeFactor, interval: $intervalDays, '
      'reps: $repetitions, lastGrade: $lastGrade, failCount: $failCount)';
}
