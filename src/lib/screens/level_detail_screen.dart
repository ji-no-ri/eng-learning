import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/level_definitions.dart';
import '../providers/level_detail_provider.dart';
import '../services/aggregation_service.dart';
import '../widgets/progress_bar_widget.dart';

/// LV詳細画面（RFP 4.2・画面設計書 §6）。
///
/// タイトルはLV名。本文冒頭に第3.1章の詳細説明（対象・カバー率・到達イメージ）を表示し、
/// 続けて次の項目を表示する。
/// 1. 進捗率（%＋横棒プログレスバー）。
/// 2. 連続学習日数（ストリーク数値）＋過去7日カレンダー（曜日ごとの実施有無）。
/// 3. 復習予定（明日／今週）。RFP 4.2 注記どおり、当該LV内でも全レベル共通の数字。
/// 4. 苦手な単語TOP5（当該LV内。`fail_count` 降順・同数は最終復習日古い順）。0件ならセクション非表示。
/// 5. 学習量推移グラフ（過去7日・当該LV内・新規＋復習合算の棒グラフ）。
///
/// グラフは追加ライブラリを用いず、軽量なカスタムウィジェット（[_StreakCalendar] /
/// [_StudyBarChart]）で描画する（pubspec 変更なし）。
class LevelDetailScreen extends StatefulWidget {
  const LevelDetailScreen({
    super.key,
    required this.level,
    this.aggregationService,
  });

  /// 対象レベル（1〜8）。
  final int level;

  /// 集計サービス（省略時は既定インスタンス）。テスト時に差し替え可能。
  final AggregationService? aggregationService;

  @override
  State<LevelDetailScreen> createState() => _LevelDetailScreenState();
}

class _LevelDetailScreenState extends State<LevelDetailScreen> {
  late final LevelDetailProvider _provider;
  late final LevelDefinition _definition;

  @override
  void initState() {
    super.initState();
    _definition = levelDefinitionOf(widget.level);
    _provider = LevelDetailProvider(
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(title: Text(_definition.name)),
        body: Consumer<LevelDetailProvider>(
          builder: (context, provider, _) {
            if (provider.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('データの読み込みに失敗しました。'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => provider.load(),
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: provider.load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _DescriptionCard(definition: _definition),
                  const SizedBox(height: 16),
                  _Section(
                    title: '進捗率',
                    child: ProgressBarWidget(rate: provider.progressRate),
                  ),
                  _Section(
                    title: '連続学習日数',
                    child: _StreakSection(
                      streakDays: provider.streakDays,
                      calendar: provider.last7DaysCalendar,
                      referenceDate: provider.referenceDate,
                    ),
                  ),
                  _Section(
                    title: '復習予定（全レベル共通）',
                    child: _ReviewScheduleRow(
                      tomorrow: provider.reviewCountTomorrow,
                      thisWeek: provider.reviewCountThisWeek,
                    ),
                  ),
                  // 苦手TOP5は当該LVで fail_count>0 の単語が存在するときのみ表示（RFP 4.2・§6.5）。
                  if (provider.weakWords.isNotEmpty)
                    _Section(
                      title: '苦手な単語 TOP5',
                      child: _WeakWordsList(words: provider.weakWords),
                    ),
                  _Section(
                    title: '学習量推移（過去7日）',
                    child: _StudyBarChart(
                      counts: provider.studyVolume7Days,
                      referenceDate: provider.referenceDate,
                    ),
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

/// 詳細説明カード（RFP 3.1：対象・カバー率・到達イメージ）。
class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.definition});

  final LevelDefinition definition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labeled(theme, '対象', definition.target),
            const SizedBox(height: 8),
            _labeled(theme, 'カバー率（目安）', definition.coverage),
            const SizedBox(height: 8),
            _labeled(theme, '到達イメージ', definition.reachImage),
          ],
        ),
      ),
    );
  }

  Widget _labeled(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// セクション見出し＋本文の共通レイアウト。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// ストリーク数値＋過去7日カレンダー（RFP 4.2 項目2・画面設計書 §4.4）。
class _StreakSection extends StatelessWidget {
  const _StreakSection({
    required this.streakDays,
    required this.calendar,
    required this.referenceDate,
  });

  final int streakDays;

  /// 添字0=6日前, 添字6=当日 の実施有無。
  final List<bool> calendar;

  /// 基準日（当日 0:00）。曜日ラベル算出に用いる。
  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$streakDays',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Text('日'),
          ],
        ),
        const SizedBox(height: 12),
        _StreakCalendar(calendar: calendar, referenceDate: referenceDate),
      ],
    );
  }
}

/// 過去7日カレンダー。曜日ラベルと実施有無マーク（塗り／薄色）を7日分並べる。
class _StreakCalendar extends StatelessWidget {
  const _StreakCalendar({required this.calendar, required this.referenceDate});

  final List<bool> calendar;
  final DateTime referenceDate;

  static const List<String> _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 添字 i（0=6日前 … 6=当日）に対応する日付・曜日を算出する。
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          _dayCell(
            context,
            scheme,
            // DateTime.weekday は月=1〜日=7。ラベル配列は月始まりなので -1 で参照。
            _weekdayLabels[
                DateTime(referenceDate.year, referenceDate.month,
                            referenceDate.day - (6 - i))
                        .weekday -
                    1],
            i < calendar.length && calendar[i],
          ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    ColorScheme scheme,
    String label,
    bool studied,
  ) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: studied
                ? scheme.primary
                : scheme.surfaceContainerHighest,
          ),
          child: studied
              ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
              : null,
        ),
      ],
    );
  }
}

/// 復習予定（明日／今週）。全レベル共通の数字を2値並べて表示する（RFP 4.2 項目3・§4.6）。
class _ReviewScheduleRow extends StatelessWidget {
  const _ReviewScheduleRow({required this.tomorrow, required this.thisWeek});

  final int tomorrow;
  final int thisWeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _card(context, '明日', tomorrow)),
        const SizedBox(width: 12),
        Expanded(child: _card(context, '今週（7日以内）', thisWeek)),
      ],
    );
  }

  Widget _card(BuildContext context, String label, int count) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '$count語',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

/// 苦手な単語TOP5リスト（RFP 4.2 項目4・§4.2）。単語と×回数を表示する。
class _WeakWordsList extends StatelessWidget {
  const _WeakWordsList({required this.words});

  final List<WeakWord> words;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < words.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text('${i + 1}.', style: theme.textTheme.bodyMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    words[i].word,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '×${words[i].failCount}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 学習量推移グラフ（過去7日・当該LV内。新規＋復習合算の棒グラフ。RFP 4.2 項目5・§4.3）。
///
/// 追加ライブラリを用いず `Container` ベースで7本の縦棒を描画する。7日すべて0件でも
/// 7本の空バーと軸を描画する（バー本数の欠落による誤読を避ける）。
class _StudyBarChart extends StatelessWidget {
  const _StudyBarChart({required this.counts, required this.referenceDate});

  /// 添字0=6日前, 添字6=当日 の学習数。
  final List<int> counts;
  final DateTime referenceDate;

  static const double _chartHeight = 120;
  static const List<String> _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxCount = counts.isEmpty
        ? 0
        : counts.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _chartHeight + 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _bar(theme, scheme, i < counts.length ? counts[i] : 0, maxCount),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 軸（横線）。
        Container(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: 28,
                child: Text(
                  _weekdayLabels[
                      DateTime(referenceDate.year, referenceDate.month,
                                  referenceDate.day - (6 - i))
                              .weekday -
                          1],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bar(ThemeData theme, ColorScheme scheme, int count, int maxCount) {
    // 高さは最大値に対する比率。全日0のときは高さ0（空バー）。
    final ratio = maxCount == 0 ? 0.0 : count / maxCount;
    final barHeight = (_chartHeight * ratio).clamp(0.0, _chartHeight);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$count',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Container(
          width: 24,
          height: barHeight,
          decoration: BoxDecoration(
            color: count == 0 ? scheme.surfaceContainerHighest : scheme.primary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ],
    );
  }
}
