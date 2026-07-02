/// JACET8000 レベル定義（RFP v1.1 第3章・第3.1章）。
///
/// LV1〜LV8 の「1行説明」（LV選択画面＝ホーム画面で表示）と、「詳細説明」
/// （対象・カバー率の目安・到達イメージ：LV詳細画面で表示）を定数として保持する。
/// ホーム画面（`home_screen.dart`）とLV詳細画面（`level_detail_screen.dart`）の
/// 双方から参照する単一の定義元であり、両画面で表示内容を一致させる。
///
/// RFP 第3章の注記のとおり、カバー率は一般的な語彙カバー率研究に基づく「目安（仮定）」で
/// あり確定値ではない。数値・文言は RFP 本文の記述に厳密に従う（創作しない）。
library;

/// 1つのレベル（LV1〜LV8）の定義（RFP 3・3.1）。
class LevelDefinition {
  /// レベル番号（1〜8）。
  final int level;

  /// レベル名（語番号レンジ付き）。例: `LV1（1〜1000語）`。LV詳細画面タイトル等で使用。
  final String name;

  /// 語番号レンジ表記。例: `1〜1000語`。
  final String wordRange;

  /// 1行説明（RFP 第3章の表）。ホーム画面のLVリスト各行に表示する。
  final String shortDescription;

  /// 詳細説明「対象」（RFP 3.1）。LV詳細画面で表示する。
  final String target;

  /// 詳細説明「カバー率（目安）」（RFP 3.1）。LV詳細画面で表示する。
  final String coverage;

  /// 詳細説明「到達イメージ」（RFP 3.1）。LV詳細画面で表示する。
  final String reachImage;

  const LevelDefinition({
    required this.level,
    required this.name,
    required this.wordRange,
    required this.shortDescription,
    required this.target,
    required this.coverage,
    required this.reachImage,
  });
}

/// LV1〜LV8 の定義一覧（固定順。ホーム画面のLVリストはこの順序で表示する）。
///
/// 文言は RFP v1.1 第3章の表（1行説明）および第3.1章（対象・カバー率・到達イメージ）に一致。
const List<LevelDefinition> kLevelDefinitions = [
  LevelDefinition(
    level: 1,
    name: 'LV1（1〜1000語）',
    wordRange: '1〜1000語',
    shortDescription: '中学教科書レベルの基本語',
    target: '中学教科書レベルの最基本語。be動詞・基本動詞・身近な名詞など、英語運用の土台となる高頻度語。',
    coverage: '一般英文の約 70〜75%。',
    reachImage: '中学卒業程度。ごく簡単な日常会話・掲示・短文の大意を把握できる。英検5級相当。',
  ),
  LevelDefinition(
    level: 2,
    name: 'LV2（1001〜2000語）',
    wordRange: '1001〜2000語',
    shortDescription: '高校初級・英字新聞の基礎語',
    target: '高校初級および英字新聞の基礎語。日常生活・学校生活で頻出する語彙。',
    coverage: 'LV1と合わせて一般英文の約 80%。',
    reachImage: '高校初級〜英検準2級相当。平易な文章の要旨を追える。',
  ),
  LevelDefinition(
    level: 3,
    name: 'LV3（2001〜3000語）',
    wordRange: '2001〜3000語',
    shortDescription: '高等学校・大学入試（センター試験）レベル',
    target: '高等学校・大学入試（旧センター試験）レベルの中核語。抽象度がやや上がる。',
    coverage: '累計で一般英文の約 85%。',
    reachImage: '高校卒業〜英検2級相当。一般的な話題の文章を辞書の補助で読める。',
  ),
  LevelDefinition(
    level: 4,
    name: 'LV4（3001〜4000語）',
    wordRange: '3001〜4000語',
    shortDescription: '大学一般教養初級',
    target: '大学一般教養（初級）レベル。学術・報道でも用いられる語が増える。',
    coverage: '累計で一般英文の約 88%。',
    reachImage: '英検2級上位／TOEIC 300〜400点相当。一般的なビジネス文書・記事の大意を把握できる。',
  ),
  LevelDefinition(
    level: 5,
    name: 'LV5（4001〜5000語）',
    wordRange: '4001〜5000語',
    shortDescription: '難関大学受験・大学一般教養',
    target: '難関大学受験・大学一般教養レベル。低頻度だが教養として重要な語。',
    coverage: '累計で一般英文の約 90%。',
    reachImage: '英検準1級下位／TOEIC 400〜500点相当。専門外の一般的文章を概ね理解できる。',
  ),
  LevelDefinition(
    level: 6,
    name: 'LV6（5001〜6000語）',
    wordRange: '5001〜6000語',
    shortDescription: '英語専門外の大学生・ビジネスマン目標',
    target: '英語専門外の大学生・ビジネスパーソンが目標とする実用上限レベル。',
    coverage: '累計で一般英文の約 92%。',
    reachImage: '英検準1級／TOEIC 600点相当。実務・報道で必要な語彙のほぼ全域をカバー。',
  ),
  LevelDefinition(
    level: 7,
    name: 'LV7（6001〜7000語）',
    wordRange: '6001〜7000語',
    shortDescription: '英語を仕事で使う人向け',
    target: '英語を仕事で使う人向けの上級語。専門的・格式的な語彙を含む。',
    coverage: '累計で一般英文の約 95%。',
    reachImage: '英検1級下位／TOEIC 700点以上相当。専門的文章・報道を辞書なしで読める。',
  ),
  LevelDefinition(
    level: 8,
    name: 'LV8（7001〜8000語）',
    wordRange: '7001〜8000語',
    shortDescription: '日本人英語学習者の最終目標',
    target: '日本人英語学習者の最終目標となる最上級語。低頻度・専門・文語的語彙。',
    coverage: '累計で一般英文の約 96〜98%（ネイティブ教養層に近い水準）。',
    reachImage: '英検1級／TOEIC 800点以上相当。広範な話題の英文を高精度で理解できる。',
  ),
];

/// レベル番号（1〜8）から定義を取得する。範囲外は [ArgumentError]。
LevelDefinition levelDefinitionOf(int level) {
  for (final def in kLevelDefinitions) {
    if (def.level == level) return def;
  }
  throw ArgumentError.value(level, 'level', 'LV1〜LV8 のいずれかを指定してください');
}
