import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'models/word.dart';
import 'repositories/word_repository.dart';

/// 初回起動時に `words` テーブルへ静的な単語データを投入する仕組み。
///
/// 本クラスは「投入の仕組み」のみを提供する。同梱している
/// `assets/seed/words_seed.json` は各レベル数語のダミー（構造確認用）であり、
/// 実データ（JACET8000 + Wiktionary 補完、最大8000語）は事前収集済みのものへ
/// 差し替える前提である（単語データの収集・変換は本アプリのスコープ外／RFP 第9章）。
///
/// シードエントリの JSON 形状:
/// ```json
/// {
///   "words": [
///     {
///       "word": "apple",
///       "level": 1,
///       "part_of_speech": "noun",
///       "pronunciation": "/ˈæp.əl/",
///       "definition_ja": "りんご",
///       "example_en": "I ate an apple.",
///       "example_ja": "私はりんごを食べた。",
///       "inflections": {"plural": "apples"},
///       "collocations": ["an apple a day"]
///     }
///   ]
/// }
/// ```
/// `inflections`（オブジェクト）・`collocations`（配列）は JSON 文字列へ直列化して
/// それぞれ `inflections_json` / `collocations_json` に格納する。`audio_file_path` は
/// 予約カラムのため常に null を投入する。
class SeedLoader {
  /// 既定のシードアセットパス（`pubspec.yaml` の assets に登録済み）。
  static const String defaultAssetPath = 'assets/seed/words_seed.json';

  final WordRepository _wordRepository;

  SeedLoader([WordRepository? wordRepository])
      : _wordRepository = wordRepository ?? WordRepository();

  /// `words` テーブルが空の場合のみシードを投入する。投入した件数を返す
  /// （既に投入済みなら 0）。初回起動フローから呼び出す。
  Future<int> seedIfEmpty(
    Database db, {
    String assetPath = defaultAssetPath,
  }) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DatabaseHelper.tableWords}'),
        ) ??
        0;
    if (count > 0) return 0; // 既に投入済み（実データ差し替え後も再投入しない）

    final words = await loadWordsFromAsset(assetPath);
    return _wordRepository.insertWords(words, executor: db);
  }

  /// シードアセット（JSON）を読み込み、[Word] のリストへ変換する。
  Future<List<Word>> loadWordsFromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (decoded['words'] as List).cast<Map<String, dynamic>>();
    return entries.map(_wordFromSeedEntry).toList();
  }

  Word _wordFromSeedEntry(Map<String, dynamic> e) {
    final inflections = e['inflections'];
    final collocations = e['collocations'];
    return Word(
      word: e['word'] as String,
      level: (e['level'] as num).toInt(),
      partOfSpeech: e['part_of_speech'] as String?,
      pronunciation: e['pronunciation'] as String?,
      definitionJa: e['definition_ja'] as String?,
      exampleEn: e['example_en'] as String?,
      exampleJa: e['example_ja'] as String?,
      inflectionsJson: inflections == null ? null : jsonEncode(inflections),
      collocationsJson: collocations == null ? null : jsonEncode(collocations),
      audioFilePath: null, // 予約カラム。初期版は常に NULL。
    );
  }
}
