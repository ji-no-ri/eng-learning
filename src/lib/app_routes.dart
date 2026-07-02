import 'package:flutter/material.dart';

import 'providers/session_provider.dart';
import 'screens/complete_screen.dart';
import 'screens/home_screen.dart';
import 'screens/level_detail_screen.dart';
import 'screens/session_screen.dart';
import 'screens/settings_screen.dart';
import 'services/aggregation_service.dart';
import 'services/sm2_service.dart';
import 'services/tts_service.dart';

/// アプリ全体で共有するサービス群のコンテナ。
///
/// DB 依存の各サービス（[AggregationService] 等）は既定で `DatabaseHelper.instance`
/// を共有するが、TTS サービスや集計サービスの実体を1インスタンスに固定して
/// 画面間で共有することで、設定変更（音声 ON/OFF・Piper 切替）が全画面に一貫して
/// 反映されるようにする。`main.dart` で1度だけ生成し、[AppRoutes.onGenerateRoute] へ渡す。
class AppServices {
  const AppServices({
    required this.ttsService,
    required this.aggregationService,
    required this.sm2Service,
  });

  /// 全画面共通の音声再生・エンジン切替サービス（RFP 4.5 / 第7章）。
  final TtsService ttsService;

  /// 進捗率・復習予定・苦手TOP5・学習量推移などの集計サービス（RFP 4.2 / 4.4）。
  final AggregationService aggregationService;

  /// SM-2 更新サービス（学習セッションの評価反映。RFP 第5章）。
  final Sm2Service sm2Service;
}

/// アプリの画面遷移を一元管理する（RFP 4.0 画面遷移全体図）。
///
/// 名前付きルートと [onGenerateRoute] で以下の遷移を集約する。
/// - Home ↔ Settings（設定アイコン／戻る）
/// - Home → NewSession → 完了（新規学習）→ Home
/// - Home → ReviewSession → 完了（復習）→ Home
///
/// なお RFP 4.0 の残りの遷移のうち、
/// - Home ↔ LVDetail（詳細ボタン／戻る）は [HomeScreen] が [LevelDetailScreen] を直接 push し、
/// - Session → 完了画面は [SessionScreen] が [CompleteScreen] を pushReplacement する
///   （押下時点の評価配列を引き渡すため）。
/// これらは各起点画面が所有する遷移であり、共有サービスは本ルータ経由で注入した
/// [HomeScreen] / [SessionScreen] から伝播するため、遷移先でも同一インスタンスが使われる。
class AppRoutes {
  AppRoutes._();

  /// ホーム画面（初期ルート。RFP 4.1）。
  static const String home = '/';

  /// 設定画面（RFP 4.5）。
  static const String settings = '/settings';

  /// 新規学習セッション（RFP 4.3。arguments に対象レベル `int` を渡す）。
  static const String newSession = '/session/new';

  /// 復習セッション（RFP 4.3。全レベル横断のため arguments 不要）。
  static const String reviewSession = '/session/review';

  /// 完了画面（RFP 4.4）。arguments に [CompleteArgs] を渡す。
  ///
  /// 通常は [SessionScreen] が内部で pushReplacement するため直接使用しないが、
  /// 遷移先の一元管理のためルートとして公開する。
  static const String complete = '/session/complete';

  /// [MaterialApp.onGenerateRoute] へ渡すルート生成関数を返す。
  ///
  /// 共有サービス（[services]）を各画面へ注入するため、クロージャで包んで返す。
  static RouteFactory routeFactory(AppServices services) {
    return (RouteSettings routeSettings) => onGenerateRoute(routeSettings, services);
  }

  /// ルート名から対応する画面を生成する。
  static Route<dynamic> onGenerateRoute(
    RouteSettings routeSettings,
    AppServices services,
  ) {
    switch (routeSettings.name) {
      case home:
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => HomeScreen(
            aggregationService: services.aggregationService,
            // 設定アイコン → 設定画面（戻ると再集計）。
            onOpenSettings: (context) =>
                Navigator.of(context).pushNamed(settings),
            // 「復習を始める」→ 復習セッション（戻ると再集計）。
            onStartReview: (context) =>
                Navigator.of(context).pushNamed(reviewSession),
            // LV行タップ → 新規学習セッション（対象レベルを渡す。戻ると再集計）。
            onStartNewSession: (context, level) =>
                Navigator.of(context).pushNamed(newSession, arguments: level),
          ),
        );

      case settings:
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => SettingsScreen(ttsService: services.ttsService),
        );

      case newSession:
        final level = routeSettings.arguments as int?;
        assert(level != null, '新規学習セッションには対象レベル（int）が必要です。');
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => SessionScreen(
            mode: SessionMode.newLearning,
            level: level,
            ttsService: services.ttsService,
            sm2Service: services.sm2Service,
            aggregationService: services.aggregationService,
          ),
        );

      case reviewSession:
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => SessionScreen(
            mode: SessionMode.review,
            ttsService: services.ttsService,
            sm2Service: services.sm2Service,
            aggregationService: services.aggregationService,
          ),
        );

      case complete:
        final args = routeSettings.arguments as CompleteArgs;
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => CompleteScreen(
            mode: args.mode,
            grades: args.grades,
            level: args.level,
            aggregationService: services.aggregationService,
          ),
        );

      default:
        return MaterialPageRoute<void>(
          settings: routeSettings,
          builder: (_) => _UnknownRouteScreen(name: routeSettings.name),
        );
    }
  }
}

/// 完了画面（[AppRoutes.complete]）へ渡す引数（モード・評価配列・レベル）。
class CompleteArgs {
  const CompleteArgs({
    required this.mode,
    required this.grades,
    this.level,
  });

  final SessionMode mode;
  final List<Grade> grades;
  final int? level;
}

/// 未定義ルートに遷移した場合のフォールバック画面。
class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('画面が見つかりません')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '指定された画面（${name ?? '不明'}）は存在しません。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
