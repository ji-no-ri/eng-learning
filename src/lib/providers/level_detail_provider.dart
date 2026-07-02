import 'package:flutter/foundation.dart';

import '../services/aggregation_service.dart';

/// LV詳細画面（RFP 4.2）の表示状態を保持する `ChangeNotifier`。
///
/// 1つのレベルについて、進捗率・ストリーク・過去7日カレンダー・復習予定（全レベル共通）・
/// 苦手単語TOP5（当該LV内）・学習量推移（過去7日・当該LV内）を [AggregationService] から
/// 取得して保持する。復習予定（明日／今週）は RFP 4.2 の注記どおり、当該LVに限定せず
/// 全レベル横断の数字である点に注意する。
///
/// 基準日は [load] 実行時点の端末ローカル日時（[DateTime.now]）。カレンダー・推移グラフの
/// 曜日ラベル算出のため、基準日を [referenceDate] として公開する（当日 0:00 に丸め済み）。
class LevelDetailProvider extends ChangeNotifier {
  LevelDetailProvider({
    required this.level,
    AggregationService? aggregationService,
  }) : _aggregation = aggregationService ?? AggregationService();

  /// 対象レベル（1〜8）。
  final int level;

  final AggregationService _aggregation;

  bool _loading = true;

  /// 集計の読み込み中か。初回は true。
  bool get loading => _loading;

  Object? _error;

  /// 集計中に発生した例外（無ければ null）。
  Object? get error => _error;

  DateTime _referenceDate = DateTime(2000, 1, 1);

  /// 集計の基準日（当日 0:00）。カレンダー・推移グラフの曜日ラベル算出に用いる。
  DateTime get referenceDate => _referenceDate;

  double _progressRate = 0.0;

  /// 進捗率（0.0〜1.0）。RFP 5.4。
  double get progressRate => _progressRate;

  int _streakDays = 0;

  /// 連続学習日数（ストリーク）。RFP 4.2。
  int get streakDays => _streakDays;

  List<bool> _last7DaysCalendar = const [];

  /// 過去7日の実施有無（添字0=6日前, 添字6=当日）。RFP 4.2 の過去7日カレンダー。
  List<bool> get last7DaysCalendar => _last7DaysCalendar;

  int _reviewCountTomorrow = 0;

  /// 明日の復習予定数（全レベル横断）。RFP 4.2 項目3。
  int get reviewCountTomorrow => _reviewCountTomorrow;

  int _reviewCountThisWeek = 0;

  /// 今週（今日から7日以内）の復習予定数（全レベル横断）。RFP 4.2 項目3。
  int get reviewCountThisWeek => _reviewCountThisWeek;

  List<WeakWord> _weakWords = const [];

  /// 苦手単語TOP5（当該LV内）。`fail_count` 降順・同数は最終復習日古い順・最大5件。RFP 4.2 項目4。
  List<WeakWord> get weakWords => _weakWords;

  List<int> _studyVolume7Days = const [];

  /// 過去7日の学習量（新規＋復習の合算。添字0=6日前, 添字6=当日）。RFP 4.2 項目5。
  List<int> get studyVolume7Days => _studyVolume7Days;

  /// 当該レベルの全集計を取得して状態を更新する。
  ///
  /// 例外が発生した場合は [error] に保持し、[loading] を false に戻したうえで通知する。
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      _referenceDate = DateTime(now.year, now.month, now.day);
      _progressRate = await _aggregation.progressRate(level);
      _streakDays = await _aggregation.streakDays(now);
      _last7DaysCalendar = await _aggregation.last7DaysCalendar(now);
      _reviewCountTomorrow = await _aggregation.reviewCountTomorrow(now);
      _reviewCountThisWeek = await _aggregation.reviewCountThisWeek(now);
      _weakWords = await _aggregation.weakWordsTop5(level);
      _studyVolume7Days = await _aggregation.studyVolume7Days(level, now);
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
