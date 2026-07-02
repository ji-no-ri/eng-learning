import 'package:flutter/foundation.dart';

import '../services/aggregation_service.dart';
import '../services/sm2_service.dart';
import 'session_provider.dart';

/// 完了画面（RFP 4.4）の表示状態を保持する `ChangeNotifier`。
///
/// 新規学習・復習の共通項目（理解度の評価分布＝円グラフ入力）に加え、モード別の
/// 単語数集計を [AggregationService] から取得して保持する。
/// - 新規学習：このレベルの総単語数／今回学習した語数／累計学習済み単語数（このLV内）。
/// - 復習：今回消化した単語数／残りの復習対象数（全レベル横断で `next_review_at ≦ 今日`）。
///
/// 評価分布はセッション中に保持した押下評価の配列（[grades]）から算出する（DB集計ではない）。
class CompleteProvider extends ChangeNotifier {
  CompleteProvider({
    required this.mode,
    required List<Grade> grades,
    this.level,
    AggregationService? aggregationService,
    DateTime? now,
  })  : assert(
          mode != SessionMode.newLearning || level != null,
          '新規学習の完了画面では level（対象レベル）が必須です。',
        ),
        _grades = List.unmodifiable(grades),
        _aggregation = aggregationService ?? AggregationService(),
        _now = now ?? DateTime.now();

  /// セッションモード（新規学習／復習）。表示内容の分岐に用いる。
  final SessionMode mode;

  /// 対象レベル（新規学習のみ必須）。
  final int? level;

  final List<Grade> _grades;
  final AggregationService _aggregation;
  final DateTime _now;

  /// セッション中に押下した評価（◎〇△×）の配列。円グラフ入力。
  List<Grade> get grades => _grades;

  /// 今回消化した単語数（＝押下評価の件数）。新規は「今回学習した語数」、復習は「今回消化した語数」。
  int get studiedCount => _grades.length;

  bool _loading = true;

  /// 集計の読み込み中か。初回は true。
  bool get loading => _loading;

  Object? _error;

  /// 読み込み中に発生した例外（無ければ null）。
  Object? get error => _error;

  GradeDistribution _distribution = const GradeDistribution();

  /// 理解度の評価分布（◎〇△×の件数・割合）。円グラフ入力（RFP 4.4）。
  GradeDistribution get distribution => _distribution;

  int _totalWordsInLevel = 0;

  /// このレベルの総単語数（新規学習完了時のみ有効。RFP 上は 1000）。
  int get totalWordsInLevel => _totalWordsInLevel;

  int _learnedCountInLevel = 0;

  /// 累計学習済み単語数（このLV内。新規学習完了時のみ有効）。
  int get learnedCountInLevel => _learnedCountInLevel;

  int _remainingReviewCount = 0;

  /// 残りの復習対象数（全レベル横断で `next_review_at ≦ 今日`。復習完了時のみ有効）。
  int get remainingReviewCount => _remainingReviewCount;

  /// 評価分布とモード別集計を取得して状態を更新する。
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _distribution = await _aggregation.gradeDistribution(_grades);
      if (mode == SessionMode.newLearning) {
        _totalWordsInLevel = await _aggregation.totalWordsInLevel(level!);
        _learnedCountInLevel = await _aggregation.learnedCountInLevel(level!);
      } else {
        _remainingReviewCount = await _aggregation.remainingReviewCount(_now);
      }
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
