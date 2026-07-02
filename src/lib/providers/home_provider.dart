import 'package:flutter/foundation.dart';

import '../data/level_definitions.dart';
import '../services/aggregation_service.dart';

/// ホーム画面（RFP 4.1）の表示状態を保持する `ChangeNotifier`。
///
/// 「今日の復習ブロック」の判定に用いる復習対象件数（全レベル横断）と、LVリスト各行の
/// 進捗率（LV1〜LV8）を [AggregationService] から取得して保持する。画面初回表示時と
/// セッション・詳細画面から戻った際に [load] を呼んで再集計する（RFP 5.5「復帰時に再計算」）。
///
/// 基準日は取得時点の端末ローカル日時（[DateTime.now]）。集計サービス側で当日 0:00 境界に
/// 丸めて扱う（RFP 5.2）。
class HomeProvider extends ChangeNotifier {
  HomeProvider({AggregationService? aggregationService})
      : _aggregation = aggregationService ?? AggregationService();

  final AggregationService _aggregation;

  bool _loading = true;

  /// 集計の読み込み中か。初回は true。
  bool get loading => _loading;

  Object? _error;

  /// 集計中に発生した例外（無ければ null）。
  Object? get error => _error;

  int _reviewCountToday = 0;

  /// 復習対象件数（全レベル横断で `next_review_at ≦ 今日`）。RFP 4.1 の復習ブロック件数。
  int get reviewCountToday => _reviewCountToday;

  /// 復習ブロックを表示すべきか（1語以上のときのみ表示。0語ならブロックごと非表示）。
  bool get hasReviewsToday => _reviewCountToday > 0;

  final Map<int, double> _progressByLevel = {};

  /// 指定レベルの進捗率（0.0〜1.0）。未取得は 0.0。
  double progressOf(int level) => _progressByLevel[level] ?? 0.0;

  /// 復習対象件数と全レベルの進捗率を集計して状態を更新する。
  ///
  /// 例外が発生した場合は [error] に保持し、[loading] を false に戻したうえで通知する。
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      _reviewCountToday = await _aggregation.reviewCountToday(now);
      for (final def in kLevelDefinitions) {
        _progressByLevel[def.level] = await _aggregation.progressRate(def.level);
      }
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
