import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/word.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/word_repository.dart';
import '../providers/session_provider.dart';
import '../services/aggregation_service.dart';
import '../services/sm2_service.dart';
import '../services/tts_service.dart';
import '../widgets/grade_pie_chart.dart';
import 'complete_screen.dart';

/// 学習セッション画面（新規学習・復習の共通UI。RFP 4.3）。
///
/// [mode] で出題対象の抽出のみを分岐し、Step1→Step2→Step3 の状態遷移・UI は共通とする。
/// - Step1 単語表示：単語＋発音記号を表示し、音声設定ONなら表示と同時に自動再生。
///   ◎〇△×は表示するがグレーアウト（押下不可）。
/// - Step2 詳細表示：画面TAPで意味・品詞／活用形／例文／コロケーションを同一画面に展開
///   （データ無しの項目はセクションごと非表示）。◎〇△×を活性化。
/// - Step3 評価押下：SM-2 更新後、自動で次の単語（Step1）へ。全語消化で完了画面へ。
///
/// 共通要素として進捗バー（現在何語目か）と「終了する」ボタンを常時表示する。
/// 全語消化または「終了する」押下で完了画面（[CompleteScreen]）へ [pushReplacement] する。
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.mode,
    this.level,
    this.wordRepository,
    this.progressRepository,
    this.sm2Service,
    this.ttsService,
    this.aggregationService,
  })  : assert(
          mode != SessionMode.newLearning || level != null,
          '新規学習モードでは level（対象レベル）が必須です。',
        );

  /// セッションモード（新規学習／復習）。
  final SessionMode mode;

  /// 対象レベル（新規学習モードのみ必須。復習では null）。
  final int? level;

  // 以下はテスト時の差し替え用（省略時は各既定インスタンス）。
  final WordRepository? wordRepository;
  final ProgressRepository? progressRepository;
  final Sm2Service? sm2Service;
  final TtsService? ttsService;
  final AggregationService? aggregationService;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final SessionProvider _provider;

  /// 完了画面への遷移を一度だけ行うためのフラグ（多重 push を防ぐ）。
  bool _navigatedToComplete = false;

  @override
  void initState() {
    super.initState();
    _provider = SessionProvider(
      mode: widget.mode,
      level: widget.level,
      wordRepository: widget.wordRepository,
      progressRepository: widget.progressRepository,
      sm2Service: widget.sm2Service,
      ttsService: widget.ttsService,
    );
    _provider.load();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  /// 完了画面へ遷移する（全語消化 or「終了する」押下）。押下時点までの評価配列を引き渡す。
  void _goToComplete() {
    if (_navigatedToComplete) return;
    _navigatedToComplete = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CompleteScreen(
          mode: widget.mode,
          level: widget.level,
          grades: _provider.grades,
          aggregationService: widget.aggregationService,
        ),
      ),
    );
  }

  /// 「終了する」確認ダイアログ。押下時点までの結果で完了画面へ進む。
  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('セッションを終了しますか？'),
        content: const Text('ここまでの結果で完了画面へ進みます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('終了する'),
          ),
        ],
      ),
    );
    if (quit == true && mounted) _goToComplete();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.mode == SessionMode.newLearning ? '新規学習' : '復習';
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
        ),
        body: Consumer<SessionProvider>(
          builder: (context, provider, _) {
            if (provider.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null) {
              return _ErrorView(onRetry: provider.load);
            }
            // 全語消化（空セッション含む）なら完了画面へ自動遷移する。
            if (provider.finished) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _goToComplete();
              });
              return const Center(child: CircularProgressIndicator());
            }
            return _SessionBody(
              provider: provider,
              onQuit: _confirmQuit,
            );
          },
        ),
      ),
    );
  }
}

/// セッション本体（進捗バー・単語カード・評価ボタン・終了ボタン）。
class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.provider, required this.onQuit});

  final SessionProvider provider;
  final Future<void> Function() onQuit;

  @override
  Widget build(BuildContext context) {
    final word = provider.currentWord!;
    return Column(
      children: [
        _ProgressHeader(
          position: provider.position,
          total: provider.totalCount,
        ),
        Expanded(
          child: GestureDetector(
            // Step1 で画面TAPすると Step2（詳細）へ展開する（RFP 4.3）。
            behavior: HitTestBehavior.opaque,
            onTap: provider.revealDetail,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: _WordCard(
                word: word,
                showDetail: provider.step == SessionStep.detail,
              ),
            ),
          ),
        ),
        _GradeBar(
          enabled: provider.canGrade,
          onGrade: provider.grade,
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onQuit,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('終了する'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 進捗バー（現在何語目か）。常時表示（RFP 4.3 共通要素）。
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.position, required this.total});

  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : position / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$position / $total 語',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// 単語カード。Step1 は単語＋発音記号のみ、Step2 は詳細（意味・品詞・活用形・例文・
/// コロケーション）を展開する。データが無い項目はセクションごと非表示（RFP 4.3）。
class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.showDetail});

  final Word word;
  final bool showDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          word.word,
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (word.pronunciation != null && word.pronunciation!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '/${word.pronunciation}/',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 24),
        if (!showDetail)
          // Step1：詳細を見るためのタップ誘導（RFP 4.3 Step1→Step2）。
          Column(
            children: [
              Icon(Icons.touch_app_outlined,
                  color: theme.colorScheme.primary, size: 32),
              const SizedBox(height: 8),
              Text(
                'タップして意味を確認',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          )
        else
          _WordDetail(word: word),
      ],
    );
  }
}

/// Step2 の詳細情報。存在するセクションのみを表示する（RFP 4.3）。
class _WordDetail extends StatelessWidget {
  const _WordDetail({required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final inflections = word.inflections;
    final collocations = word.collocations;

    // 意味・品詞（意味 or 品詞のいずれかがあれば表示）。
    final hasMeaning = (word.definitionJa != null &&
            word.definitionJa!.isNotEmpty) ||
        (word.partOfSpeech != null && word.partOfSpeech!.isNotEmpty);
    // 例文（英文があれば表示。日本語訳は任意）。
    final hasExample = word.exampleEn != null && word.exampleEn!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasMeaning)
          _DetailSection(
            title: '意味・品詞',
            child: _MeaningBlock(
              partOfSpeech: word.partOfSpeech,
              definitionJa: word.definitionJa,
            ),
          ),
        if (inflections != null && inflections.isNotEmpty)
          _DetailSection(
            title: '活用形',
            child: _InflectionsBlock(inflections: inflections),
          ),
        if (hasExample)
          _DetailSection(
            title: '例文',
            child: _ExampleBlock(
              exampleEn: word.exampleEn!,
              exampleJa: word.exampleJa,
            ),
          ),
        if (collocations != null && collocations.isNotEmpty)
          _DetailSection(
            title: 'コロケーション',
            child: _CollocationsBlock(collocations: collocations),
          ),
      ],
    );
  }
}

/// 詳細情報の1セクション（見出し＋本文）。
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 意味・品詞ブロック。
class _MeaningBlock extends StatelessWidget {
  const _MeaningBlock({this.partOfSpeech, this.definitionJa});

  final String? partOfSpeech;
  final String? definitionJa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (partOfSpeech != null && partOfSpeech!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              partOfSpeech!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        if (definitionJa != null && definitionJa!.isNotEmpty)
          Text(definitionJa!, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

/// 活用形ブロック（キー：値 の一覧）。
class _InflectionsBlock extends StatelessWidget {
  const _InflectionsBlock({required this.inflections});

  final Map<String, dynamic> inflections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in inflections.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    entry.key,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${entry.value}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 例文ブロック（英文＋日本語訳）。
class _ExampleBlock extends StatelessWidget {
  const _ExampleBlock({required this.exampleEn, this.exampleJa});

  final String exampleEn;
  final String? exampleJa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          exampleEn,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
        if (exampleJa != null && exampleJa!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            exampleJa!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// コロケーションブロック（箇条書き）。
class _CollocationsBlock extends StatelessWidget {
  const _CollocationsBlock({required this.collocations});

  final List<String> collocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in collocations)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('・'),
                Expanded(child: Text(c, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

/// ◎〇△×の評価ボタン行。Step1 ではグレーアウト（[enabled]=false）、Step2 で活性化する。
class _GradeBar extends StatelessWidget {
  const _GradeBar({required this.enabled, required this.onGrade});

  final bool enabled;
  final Future<void> Function(Grade grade) onGrade;

  static const List<Grade> _order = [
    Grade.easy,
    Grade.good,
    Grade.hard,
    Grade.fail,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final grade in _order)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _GradeButton(
                  grade: grade,
                  enabled: enabled,
                  onPressed: () => onGrade(grade),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 個々の評価ボタン。無効時はグレーアウト表示にする（押下不可）。
class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.grade,
    required this.enabled,
    required this.onPressed,
  });

  final Grade grade;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = gradeColor(grade);
    final disabledColor = theme.colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: 64,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: baseColor,
          disabledBackgroundColor: disabledColor,
          disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
          padding: EdgeInsets.zero,
        ),
        child: Text(
          grade.symbol,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: enabled ? Colors.white : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// 出題対象の読み込み失敗時の簡易エラー表示（再試行付き）。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('単語の読み込みに失敗しました。'),
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
