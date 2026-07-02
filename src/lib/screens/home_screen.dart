import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/level_definitions.dart';
import '../providers/home_provider.dart';
import '../services/aggregation_service.dart';
import '../widgets/progress_bar_widget.dart';
import 'level_detail_screen.dart';

/// 画面遷移用コールバック（対象レベルを伴う）。
typedef LevelNavCallback = void Function(BuildContext context, int level);

/// 画面遷移用コールバック（レベル指定なし）。
typedef ScreenNavCallback = void Function(BuildContext context);

/// ホーム画面（LV選択統合画面。RFP 4.1・画面設計書 §5）。
///
/// 構成は次の3要素。
/// 1. アプリバー右上の設定アイコン（[onOpenSettings] で設定画面へ）。音声ON/OFFはここには置かない。
/// 2. 今日の復習ブロック（復習対象1語以上のときのみ表示。件数と「復習を始める」ボタンをカード状・
///    強調配色で表示。0語ならブロックごと非表示）。押下で復習セッションへ（[onStartReview]）。
/// 3. LVリスト（LV1〜LV8を固定順で表示）。各行に1行説明・進捗率・詳細ボタン。行タップで新規学習
///    セッションへ（[onStartNewSession]）、詳細ボタンでLV詳細画面へ遷移。
///
/// 設定画面・学習セッション画面は別タスクの成果物であるため、遷移はコールバックで受け取り、
/// 未配線の場合は案内スナックバーを表示する。LV詳細画面（[LevelDetailScreen]）は本タスクの
/// 成果物のため直接 push する。セッション・詳細から戻った際は進捗・復習件数を再集計する。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.aggregationService,
    this.onOpenSettings,
    this.onStartReview,
    this.onStartNewSession,
  });

  /// 集計サービス（省略時は既定インスタンス）。テスト時に差し替え可能。
  final AggregationService? aggregationService;

  /// 設定アイコン押下時の遷移（設定画面＝別タスク）。未指定なら案内表示。
  final ScreenNavCallback? onOpenSettings;

  /// 「復習を始める」押下時の遷移（復習セッション＝別タスク）。未指定なら案内表示。
  final ScreenNavCallback? onStartReview;

  /// LV行タップ時の遷移（新規学習セッション＝別タスク）。未指定なら案内表示。
  final LevelNavCallback? onStartNewSession;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = HomeProvider(aggregationService: widget.aggregationService);
    _provider.load();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  void _showPending(String screenName) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$screenNameは別タスクで実装されます。')),
      );
  }

  void _handleOpenSettings() {
    final cb = widget.onOpenSettings;
    if (cb != null) {
      cb(context);
    } else {
      _showPending('設定画面');
    }
  }

  void _handleStartReview() {
    final cb = widget.onStartReview;
    if (cb != null) {
      cb(context);
    } else {
      _showPending('復習セッション');
    }
  }

  void _handleStartNewSession(int level) {
    final cb = widget.onStartNewSession;
    if (cb != null) {
      cb(context, level);
    } else {
      _showPending('新規学習セッション');
    }
  }

  Future<void> _openDetail(int level) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LevelDetailScreen(
          level: level,
          aggregationService: widget.aggregationService,
        ),
      ),
    );
    // 詳細画面から戻った際、進捗・復習件数が変わっている可能性があるため再集計する。
    if (!mounted) return;
    await _provider.load();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('JACET Vocabulary Learner'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '設定',
              onPressed: _handleOpenSettings,
            ),
          ],
        ),
        body: Consumer<HomeProvider>(
          builder: (context, provider, _) {
            if (provider.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null) {
              return _ErrorView(onRetry: provider.load);
            }
            return RefreshIndicator(
              onRefresh: provider.load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (provider.hasReviewsToday)
                    _TodayReviewBlock(
                      count: provider.reviewCountToday,
                      onStart: _handleStartReview,
                    ),
                  if (provider.hasReviewsToday) const SizedBox(height: 24),
                  Text(
                    'レベルを選ぶ',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final def in kLevelDefinitions)
                    _LevelTile(
                      definition: def,
                      rate: provider.progressOf(def.level),
                      onTap: () => _handleStartNewSession(def.level),
                      onDetail: () => _openDetail(def.level),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 今日の復習ブロック（RFP 4.1・画面設計書 §5.5）。復習対象1語以上のときのみ生成される。
class _TodayReviewBlock extends StatelessWidget {
  const _TodayReviewBlock({required this.count, required this.onStart});

  final int count;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_repeat, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  '今日の復習',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '$count語',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('復習を始める'),
            ),
          ],
        ),
      ),
    );
  }
}

/// LVリストの1行（RFP 4.1・画面設計書 §5.4）。行タップで新規学習、詳細ボタンでLV詳細へ。
class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.definition,
    required this.rate,
    required this.onTap,
    required this.onDetail,
  });

  final LevelDefinition definition;
  final double rate;
  final VoidCallback onTap;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${definition.name.split('（').first}  ${definition.shortDescription}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ProgressBarWidget(rate: rate, compact: true),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onDetail,
                child: const Text('詳細'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 集計失敗時の簡易エラー表示（再試行付き）。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('データの読み込みに失敗しました。'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => onRetry(),
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }
}
