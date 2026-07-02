import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/aggregation_service.dart';
import '../services/sm2_service.dart';

/// 評価（◎〇△×）に対応する表示色（完了画面の理解度円グラフ・凡例で共通利用）。
///
/// ◎=緑（楽）／〇=青（良）／△=橙（難）／×=赤（忘）で、直感的に習得度が読めるよう配色する。
Color gradeColor(Grade grade) {
  switch (grade) {
    case Grade.easy:
      return const Color(0xFF2E7D32); // green 800
    case Grade.good:
      return const Color(0xFF1565C0); // blue 800
    case Grade.hard:
      return const Color(0xFFEF6C00); // orange 800
    case Grade.fail:
      return const Color(0xFFC62828); // red 800
  }
}

/// 評価の日本語ラベル（記号＋補足）。凡例表示に用いる。
String gradeLabel(Grade grade) {
  switch (grade) {
    case Grade.easy:
      return '◎ 楽';
    case Grade.good:
      return '〇 良';
    case Grade.hard:
      return '△ 難';
    case Grade.fail:
      return '× 忘';
  }
}

/// 理解度の円グラフ（◎〇△×の割合）＋凡例（RFP 4.4 完了画面）。
///
/// 追加ライブラリを用いず [CustomPainter]（[_PiePainter]）で描画する。入力は
/// セッション中に保持した押下評価から組み立てた [GradeDistribution]。総件数が 0 のときは
/// 「評価データがありません」と表示する（空セッションで終了した場合の保険）。
class GradePieChart extends StatelessWidget {
  const GradePieChart({super.key, required this.distribution});

  /// ◎〇△×の件数・割合を保持する評価分布。
  final GradeDistribution distribution;

  /// グラフに描画する評価の順序（◎→〇→△→×）。
  static const List<Grade> _order = [
    Grade.easy,
    Grade.good,
    Grade.hard,
    Grade.fail,
  ];

  int _countOf(Grade grade) {
    switch (grade) {
      case Grade.easy:
        return distribution.easy;
      case Grade.good:
        return distribution.good;
      case Grade.hard:
        return distribution.hard;
      case Grade.fail:
        return distribution.fail;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = distribution.total;

    if (total == 0) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            '評価データがありません',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: CustomPaint(
            painter: _PiePainter(
              counts: {for (final g in _order) g: _countOf(g)},
              order: _order,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final g in _order)
                _LegendRow(
                  color: gradeColor(g),
                  label: gradeLabel(g),
                  count: _countOf(g),
                  total: total,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 凡例の1行（色チップ＋ラベル＋件数・割合）。
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.count,
    required this.total,
  });

  final Color color;
  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = total == 0 ? 0.0 : count / total * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            '$count語（${percent.toStringAsFixed(0)}%）',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// 円グラフ本体の描画（各評価の件数比に応じた扇形を描く）。件数0の評価は扇形を描かない。
class _PiePainter extends CustomPainter {
  _PiePainter({required this.counts, required this.order});

  final Map<Grade, int> counts;
  final List<Grade> order;

  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 12時方向（-90°）から時計回りに描く。
    var startAngle = -math.pi / 2;
    for (final grade in order) {
      final count = counts[grade] ?? 0;
      if (count == 0) continue;
      final sweep = count / total * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = gradeColor(grade);
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.counts != counts;
}
