import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/complete_provider.dart';
import '../providers/session_provider.dart';
import '../services/aggregation_service.dart';
import '../services/sm2_service.dart';
import '../widgets/grade_pie_chart.dart';

/// 完了画面（RFP 4.4。新規学習／復習で表示内容を分岐）。
///
/// 共通で理解度の円グラフ（◎〇△×の割合）を表示する。加えて、
/// - 新規学習完了：このレベルの総単語数／今回学習した語数／累計学習済み単語数（このLV内）。
/// - 復習完了：今回消化した単語数／残りの復習対象数（0のときは完了メッセージに切り替え）。
///
/// 「ホームへ」ボタンでホーム画面へ戻る（本画面はセッション画面から [pushReplacement] で
/// 到達するため、[Navigator.pop] でホームへ復帰する）。
class CompleteScreen extends StatefulWidget {
  const CompleteScreen({
    super.key,
    required this.mode,
    required this.grades,
    this.level,
    this.aggregationService,
  })  : assert(
          mode != SessionMode.newLearning || level != null,
          '新規学習の完了画面では level（対象レベル）が必須です。',
        );

  /// セッションモード（新規学習／復習）。
  final SessionMode mode;

  /// セッション中に押下した評価（◎〇△×）の配列。円グラフ入力。
  final List<Grade> grades;

  /// 対象レベル（新規学習のみ必須）。
  final int? level;

  /// 集計サービス（省略時は既定インスタンス）。テスト時に差し替え可能。
  final AggregationService? aggregationService;

  @override
  State<CompleteScreen> createState() => _CompleteScreenState();
}

class _CompleteScreenState extends State<CompleteScreen> {
  late final CompleteProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = CompleteProvider(
      mode: widget.mode,
      grades: widget.grades,
      level: widget.level,
      aggregationService: widget.aggregationService,
    );
    _provider.load();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  void _goHome() {
    // セッション画面から pushReplacement で到達しているため、pop でホームへ戻る。
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == SessionMode.newLearning
        ? '新規学習 完了'
        : '復習 完了';
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
        ),
        body: Consumer<CompleteProvider>(
          builder: (context, provider, _) {
            if (provider.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null) {
              return _ErrorView(onRetry: provider.load);
            }
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _Section(
                        title: '理解度',
                        child: GradePieChart(distribution: provider.distribution),
                      ),
                      const SizedBox(height: 8),
                      if (widget.mode == SessionMode.newLearning)
                        _NewLearningStats(provider: provider, level: widget.level!)
                      else
                        _ReviewStats(provider: provider),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _goHome,
                        icon: const Icon(Icons.home),
                        label: const Text('ホームへ'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 新規学習完了の統計（総単語数／今回学習した語数／累計学習済み単語数）。RFP 4.4。
class _NewLearningStats extends StatelessWidget {
  const _NewLearningStats({required this.provider, required this.level});

  final CompleteProvider provider;
  final int level;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'このレベル（LV$level）の状況',
      child: Column(
        children: [
          _StatRow(label: 'このレベルの総単語数', value: '${provider.totalWordsInLevel}語'),
          _StatRow(label: '今回の学習対象数', value: '${provider.studiedCount}語'),
          _StatRow(
            label: '累計学習済み単語数',
            value: '${provider.learnedCountInLevel}語',
          ),
        ],
      ),
    );
  }
}

/// 復習完了の統計（今回消化した語数／残りの復習対象数）。RFP 4.4。
/// 残りの復習対象が0のときは件数の代わりに完了メッセージを表示する。
class _ReviewStats extends StatelessWidget {
  const _ReviewStats({required this.provider});

  final CompleteProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = provider.remainingReviewCount;
    return _Section(
      title: '復習の状況',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(label: '今回消化した単語数', value: '${provider.studiedCount}語'),
          const SizedBox(height: 4),
          if (remaining > 0)
            _StatRow(label: '残りの復習対象数', value: '$remaining語')
          else
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本日の復習をすべて消化しました。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// セクション見出し＋本文（カード）。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// ラベル＋数値の1行。
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
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
          const Text('完了情報の読み込みに失敗しました。'),
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
