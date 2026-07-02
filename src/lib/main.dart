import 'package:flutter/material.dart';

import 'data/database_helper.dart';
import 'data/seed_loader.dart';

/// アプリのエントリポイント（最小の起動雛形）。
///
/// タスク1（データ層）の範囲として、DB 初期化とシード投入までを配線する。
/// 画面遷移・状態管理（provider）・各画面の本格的な配線はタスク7で行う。
Future<void> main() async {
  // rootBundle 経由のアセット読み込み・sqflite 利用のため、事前にバインディングを初期化する。
  WidgetsFlutterBinding.ensureInitialized();

  // 稼働用 DB をオープン（初回はスキーマ生成・app_settings 既定値投入）。
  final db = await DatabaseHelper.instance.database;

  // words が空なら初回のみシードを投入する。
  await SeedLoader().seedIfEmpty(db);

  runApp(const JacetVocabularyLearnerApp());
}

/// ルートウィジェット（雛形）。本格的なテーマ・ルーティングはタスク7で構築する。
class JacetVocabularyLearnerApp extends StatelessWidget {
  const JacetVocabularyLearnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JACET Vocabulary Learner',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const _BootstrapPlaceholder(),
    );
  }
}

/// 起動確認用のプレースホルダ画面。UI 実装は後続タスクで置き換える。
class _BootstrapPlaceholder extends StatelessWidget {
  const _BootstrapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JACET Vocabulary Learner')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'データ層の初期化が完了しました。\n画面の実装は後続タスクで追加されます。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
