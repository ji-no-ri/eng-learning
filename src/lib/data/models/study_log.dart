/// 学習ログ（`study_log` テーブル）の不変モデル。
///
/// RFP v1.1 第6章のカラム定義に一致する。評価押下ごとに1件追記され（追記専用）、
/// ストリーク計算・学習量推移グラフの集計元となる。`studied_at` は ISO8601 文字列
/// （端末ローカル）で保持する。
class StudyLog {
  /// セッション種別（`session_type`）。
  static const String sessionNew = 'new'; // 新規学習
  static const String sessionReview = 'review'; // 復習

  /// ログの一意識別子。DB 未保存は null。
  final int? id;

  /// 学習対象の単語 ID（NOT NULL, FK → words.id）。
  final int wordId;

  /// 学習時のレベル（1〜8）。LV 別集計を JOIN なしで行うため冗長保持する。
  final int level;

  /// セッション種別（`new` / `review`）。
  final String? sessionType;

  /// 押下した評価値（`◎` `〇` `△` `×`）。
  final String? grade;

  /// 学習日時（ISO8601 文字列）。
  final String? studiedAt;

  const StudyLog({
    this.id,
    required this.wordId,
    required this.level,
    this.sessionType,
    this.grade,
    this.studiedAt,
  });

  /// `studied_at` をパースした [DateTime]（不正/未設定は null）。
  DateTime? get studiedAtDate {
    final raw = studiedAt;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// DB 行（Map）から生成する。
  factory StudyLog.fromMap(Map<String, dynamic> map) => StudyLog(
        id: map['id'] as int?,
        wordId: map['word_id'] as int,
        level: map['level'] as int,
        sessionType: map['session_type'] as String?,
        grade: map['grade'] as String?,
        studiedAt: map['studied_at'] as String?,
      );

  /// DB 行（Map）へ変換する。id が null の場合はキーを含めない。
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'word_id': wordId,
        'level': level,
        'session_type': sessionType,
        'grade': grade,
        'studied_at': studiedAt,
      };

  StudyLog copyWith({
    int? id,
    int? wordId,
    int? level,
    String? sessionType,
    String? grade,
    String? studiedAt,
  }) =>
      StudyLog(
        id: id ?? this.id,
        wordId: wordId ?? this.wordId,
        level: level ?? this.level,
        sessionType: sessionType ?? this.sessionType,
        grade: grade ?? this.grade,
        studiedAt: studiedAt ?? this.studiedAt,
      );

  @override
  String toString() =>
      'StudyLog(wordId: $wordId, level: $level, type: $sessionType, '
      'grade: $grade, studiedAt: $studiedAt)';
}
