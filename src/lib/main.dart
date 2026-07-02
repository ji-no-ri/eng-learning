import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'data/database_helper.dart';
import 'data/seed_loader.dart';
import 'services/aggregation_service.dart';
import 'services/sm2_service.dart';
import 'services/tts_service.dart';

/// アプリのエントリポイント（RFP 第4章・第2章・第4.0章）。
///
/// 起動時に次を行う。
/// 1. DB 初期化（初回はスキーマ生成・`app_settings` 既定値投入。`DatabaseHelper._onCreate`）。
/// 2. シード投入（`words` が空の初回のみ、同梱の単語データを投入。[SeedLoader]）。
/// 3. 共有サービス（[TtsService] / [AggregationService] / [Sm2Service]）を1インスタンス生成し、
///    ルーティング（[AppRoutes]）へ注入して全画面で共有する。
///
/// 全機能はオフラインで動作する（単語データは同梱、音声も実行時オンデバイス合成。
/// RFP 第7章・第11章）。
Future<void> main() async {
  // rootBundle 経由のアセット読み込み・sqflite 利用のため、事前にバインディングを初期化する。
  WidgetsFlutterBinding.ensureInitialized();

  // 稼働用 DB をオープン（初回はスキーマ生成・app_settings 既定値投入）。
  final db = await DatabaseHelper.instance.database;

  // words が空なら初回のみシードを投入する（オフライン動作のため全データを同梱）。
  await SeedLoader().seedIfEmpty(db);

  // 画面間で共有するサービス群を生成する（DB は DatabaseHelper.instance を共有）。
  final services = AppServices(
    ttsService: TtsService(),
    aggregationService: AggregationService(),
    sm2Service: Sm2Service(),
  );

  runApp(JacetVocabularyLearnerApp(services: services));
}

/// ルートウィジェット。日本語UI・テーマ・ルーティング（RFP 4.0）を構成する。
class JacetVocabularyLearnerApp extends StatelessWidget {
  const JacetVocabularyLearnerApp({super.key, required this.services});

  /// 全画面で共有するサービス群（ルーティング経由で各画面へ注入する）。
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JACET英単語学習',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      // 画面遷移は AppRoutes に一元化する（RFP 4.0 画面遷移全体図）。
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRoutes.routeFactory(services),
    );
  }
}
