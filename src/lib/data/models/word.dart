import 'dart:convert';

/// 単語マスタ（`words` テーブル）の不変モデル。
///
/// RFP v1.1 第6章のカラム定義に一致する。`inflections_json` / `collocations_json`
/// は生の JSON 文字列と、パース済みアクセサ（[inflections] / [collocations]）の
/// 両方を提供する。`audio_file_path` は将来の Piper TTS 事前生成音声用の予約カラムで、
/// 初期版は常に null。
class Word {
  /// 主キー。DB 未保存（シード投入前）は null。
  final int? id;

  /// 英単語見出し（UNIQUE, NOT NULL）。
  final String word;

  /// JACET8000 のレベル（1〜8）。
  final int level;

  /// 品詞。データが無ければ null（UI ではセクション非表示）。
  final String? partOfSpeech;

  /// 発音記号（IPA）。
  final String? pronunciation;

  /// 日本語の意味。
  final String? definitionJa;

  /// 例文（英文、1つ）。
  final String? exampleEn;

  /// 例文の日本語訳。
  final String? exampleJa;

  /// 活用形を格納した JSON オブジェクト文字列（例: `{"plural":"apples"}`）。
  final String? inflectionsJson;

  /// コロケーションを格納した JSON 配列文字列（例: `["an apple a day"]`）。
  final String? collocationsJson;

  /// 【予約カラム】将来の Piper TTS 事前生成音声ファイルのパス。初期版は常に null。
  final String? audioFilePath;

  const Word({
    this.id,
    required this.word,
    required this.level,
    this.partOfSpeech,
    this.pronunciation,
    this.definitionJa,
    this.exampleEn,
    this.exampleJa,
    this.inflectionsJson,
    this.collocationsJson,
    this.audioFilePath,
  });

  /// 活用形（パース済み）。`inflections_json` が無い/空/不正なら null。
  Map<String, dynamic>? get inflections {
    final raw = inflectionsJson;
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// コロケーション（パース済み）。`collocations_json` が無い/空/不正なら null。
  List<String>? get collocations {
    final raw = collocationsJson;
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.map((e) => e.toString()).toList() : null;
  }

  /// DB 行（Map）から生成する。
  factory Word.fromMap(Map<String, dynamic> map) => Word(
        id: map['id'] as int?,
        word: map['word'] as String,
        level: map['level'] as int,
        partOfSpeech: map['part_of_speech'] as String?,
        pronunciation: map['pronunciation'] as String?,
        definitionJa: map['definition_ja'] as String?,
        exampleEn: map['example_en'] as String?,
        exampleJa: map['example_ja'] as String?,
        inflectionsJson: map['inflections_json'] as String?,
        collocationsJson: map['collocations_json'] as String?,
        audioFilePath: map['audio_file_path'] as String?,
      );

  /// DB 行（Map）へ変換する。id が null の場合はキーを含めない（自動採番に委ねる）。
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'word': word,
        'level': level,
        'part_of_speech': partOfSpeech,
        'pronunciation': pronunciation,
        'definition_ja': definitionJa,
        'example_en': exampleEn,
        'example_ja': exampleJa,
        'inflections_json': inflectionsJson,
        'collocations_json': collocationsJson,
        'audio_file_path': audioFilePath,
      };

  Word copyWith({
    int? id,
    String? word,
    int? level,
    String? partOfSpeech,
    String? pronunciation,
    String? definitionJa,
    String? exampleEn,
    String? exampleJa,
    String? inflectionsJson,
    String? collocationsJson,
    String? audioFilePath,
  }) =>
      Word(
        id: id ?? this.id,
        word: word ?? this.word,
        level: level ?? this.level,
        partOfSpeech: partOfSpeech ?? this.partOfSpeech,
        pronunciation: pronunciation ?? this.pronunciation,
        definitionJa: definitionJa ?? this.definitionJa,
        exampleEn: exampleEn ?? this.exampleEn,
        exampleJa: exampleJa ?? this.exampleJa,
        inflectionsJson: inflectionsJson ?? this.inflectionsJson,
        collocationsJson: collocationsJson ?? this.collocationsJson,
        audioFilePath: audioFilePath ?? this.audioFilePath,
      );

  @override
  String toString() => 'Word(id: $id, word: $word, level: $level)';
}
