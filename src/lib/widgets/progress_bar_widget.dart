import 'package:flutter/material.dart';

/// 進捗率（%＋横棒プログレスバー）の共通表示ウィジェット（画面設計書 §3・§4.1）。
///
/// ホーム画面のLVリスト（コンパクト表示）とLV詳細画面（大きめ表示）で共有する。
/// [rate] は 0.0〜1.0。範囲外は内部で 0.0〜1.0 にクランプする。
class ProgressBarWidget extends StatelessWidget {
  const ProgressBarWidget({
    super.key,
    required this.rate,
    this.compact = false,
  });

  /// 進捗率（0.0〜1.0）。RFP 5.4 の算出値。
  final double rate;

  /// コンパクト表示（ホームのLVリスト向け。数値とバーを1行に近い密度で表示）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final clamped = rate.clamp(0.0, 1.0).toDouble();
    final percentText = '${(clamped * 100).toStringAsFixed(1)}%';
    final theme = Theme.of(context);

    if (compact) {
      return Row(
        children: [
          Text('進捗 $percentText', style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: clamped,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          percentText,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 12,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
