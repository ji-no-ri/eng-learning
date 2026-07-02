import 'package:flutter/foundation.dart';

import '../data/models/word.dart';
import '../data/models/study_log.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/word_repository.dart';
import '../services/sm2_service.dart';
import '../services/tts_service.dart';

/// 学習セッションのモード（RFP 4.3）。
///
/// [newLearning]（新規学習）と [review]（復習）で出題対象の抽出条件が異なるが、
/// Step1→Step2→Step3 の状態遷移・UI は共通である。
enum SessionMode {
  /// 新規学習：選択LV内の未学習語（`user_progress` レコード無し）を最大20語。
  newLearning,

  /// 復習：`next_review_at ≦ 今日` の語を全レベル横断・古い順（件数上限なし）。
  review,
}

/// セッション画面内の3ステップ（RFP 4.3 状態遷移）。
enum SessionStep {
  /// Step1 単語表示：単語＋発音記号のみ。◎〇△×はグレーアウト（押下不可）。
  word,

  /// Step2 詳細表示：意味・品詞・活用形・例文・コロケーションを展開。◎〇△×が活性化。
  detail,
}

/// 学習セッション画面（RFP 4.3）の状態を保持する `ChangeNotifier`。
///
/// 新規学習・復習で共通のロジックを担い、モードで出題対象の抽出のみを分岐する。
/// - 新規学習：選択LV内の未学習語を最大20語（20語未満ならその分だけ）。
/// - 復習：`next_review_at ≦ 今日` の語を全レベル横断・`next_review_at` 古い順（上限なし）。
///
/// Step1→Step2→Step3 の遷移、評価押下時の SM-2 更新（[Sm2Service.gradeWord]）、
/// 単語表示時の音声自動再生（[TtsService.speak]。音声OFF時は内部で無音）、
/// 完了画面の円グラフ入力とする押下評価の配列保持（[grades]）を管理する。
///
/// 基準時刻はセッション開始時点の端末ローカル日時（[DateTime.now]）を当日 0:00 に丸めて用いる
/// （RFP 5.2「0:00 境界基準」。復習対象の抽出・SM-2 の日付算出で一貫させる）。
class SessionProvider extends ChangeNotifier {
  SessionProvider({
    required this.mode,
    this.level,
    WordRepository? wordRepository,
    ProgressRepository? progressRepository,
    Sm2Service? sm2Service,
    TtsService? ttsService,
    DateTime? now,
  })  : assert(
          mode != SessionMode.newLearning || level != null,
          '新規学習モードでは level（対象レベル）が必須です。',
        ),
        _wordRepository = wordRepository ?? WordRepository(),
        _progressRepository = progressRepository ?? ProgressRepository(),
        _sm2Service = sm2Service ?? Sm2Service(),
        _ttsService = ttsService ?? TtsService(),
        // 基準時刻はセッション開始時点で当日 0:00 に丸めて確定し、以降の
        // 復習抽出（_loadTargets）と SM-2 更新（grade）で同一値を用いる
        // （RFP 5.2「0:00 境界基準」。基準日を全処理で一貫させる）。
        _now = _startOfDay(now ?? DateTime.now());

  /// セッションモード（新規学習／復習）。
  final SessionMode mode;

  /// 対象レベル（新規学習モードのみ必須。復習モードでは null で、各単語自身のレベルを用いる）。
  final int? level;

  final WordRepository _wordRepository;
  final ProgressRepository _progressRepository;
  final Sm2Service _sm2Service;
  final TtsService _ttsService;

  /// セッション開始時点の基準時刻（構築時に当日 0:00 へ丸め済み）。
  /// 復習対象の抽出・SM-2 の日付算出でこの同一値を用いる（RFP 5.2「0:00 境界基準」）。
  final DateTime _now;

  /// 新規学習セッションの1回あたり出題上限（RFP 4.3「20語固定」）。
  static const int kNewSessionLimit = 20;

  bool _loading = true;

  /// 出題対象の読み込み中か。初回は true。
  bool get loading => _loading;

  Object? _error;

  /// 読み込み中に発生した例外（無ければ null）。
  Object? get error => _error;

  List<Word> _words = const [];

  /// 出題対象の単語列（新規学習は id 昇順、復習は `next_review_at` 古い順）。
  List<Word> get words => _words;

  int _index = 0;

  /// 現在の出題位置（0 起点の添字）。
  int get index => _index;

  SessionStep _step = SessionStep.word;

  /// 現在の Step（Step1 単語表示 / Step2 詳細表示）。
  SessionStep get step => _step;

  final List<Grade> _grades = [];

  /// セッション中に押下した評価（◎〇△×）の配列。完了画面の円グラフ入力に用いる（RFP 4.4）。
  List<Grade> get grades => List.unmodifiable(_grades);

  /// 出題総数（読み込んだ単語数）。進捗バーの分母。
  int get totalCount => _words.length;

  /// 現在何語目か（1 起点。進捗バー表示用）。全語消化後は [totalCount] を返す。
  int get position => _words.isEmpty ? 0 : (_index + 1).clamp(0, _words.length);

  /// 現在表示中の単語（全語消化後・空セッションでは null）。
  Word? get currentWord =>
      _index >= 0 && _index < _words.length ? _words[_index] : null;

  /// 全語を消化したか（読み込み完了後、出題位置が末尾を越えたら true）。
  /// 空セッション（対象0語）も読み込み完了時点で true。
  bool get finished => !_loading && _error == null && _index >= _words.length;

  /// ◎〇△×ボタンが活性化しているか（Step2 のみ活性。Step1 はグレーアウト）。
  bool get canGrade => _step == SessionStep.detail && currentWord != null;

  /// `study_log.session_type` 用の文字列（new / review）。
  String get sessionType => mode == SessionMode.newLearning
      ? StudyLog.sessionNew
      : StudyLog.sessionReview;

  /// 出題対象を読み込み、最初の単語で Step1 を開始する（音声設定ONなら自動再生）。
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _words = await _loadTargets();
      _index = 0;
      _step = SessionStep.word;
      _grades.clear();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
    // 読み込み完了後、最初の単語を自動再生する（音声OFF時は speak 内部で無音）。
    if (_error == null) _speakCurrent();
  }

  /// モード別に出題対象を抽出する。
  Future<List<Word>> _loadTargets() async {
    if (mode == SessionMode.newLearning) {
      // 新規学習：選択LV内の未学習語を最大20語（20語未満ならその分だけ）。
      return _wordRepository.getUnlearnedWordsByLevel(
        level!,
        limit: kNewSessionLimit,
      );
    }
    // 復習：next_review_at ≦ 今日 の語を全レベル横断・古い順（上限なし）。
    // _now は構築時に当日 0:00 へ丸め済み（SM-2 更新と基準日を一貫させる）。
    final startOfToday = _now.toIso8601String();
    final due = await _progressRepository.getDueForReview(startOfToday);
    final result = <Word>[];
    for (final progress in due) {
      final word = await _wordRepository.getWord(progress.wordId);
      // 学習ログの整合上ありえないが、参照先が欠落していれば安全にスキップする。
      if (word != null) result.add(word);
    }
    return result;
  }

  /// Step1 → Step2：画面TAPで詳細を展開し、◎〇△×を活性化する（RFP 4.3）。
  /// 既に Step2、または全語消化後は何もしない。
  void revealDetail() {
    if (_step != SessionStep.word || currentWord == null) return;
    _step = SessionStep.detail;
    notifyListeners();
  }

  /// Step3：評価押下。SM-2 更新後、自動で次の単語（Step1）へ進む（RFP 4.3）。
  ///
  /// Step2（[canGrade]）でのみ有効。押下値は [grades] へ蓄積し、完了画面の円グラフ入力とする。
  Future<void> grade(Grade grade) async {
    final word = currentWord;
    if (!canGrade || word == null) return;

    // SM-2 更新（進捗レコードの取得/新規作成 → 更新 → study_log 追記を同一トランザクションで）。
    // 基準時刻は _loadTargets の復習抽出と同じ _now（当日 0:00 に丸め済み）を渡し、
    // 復習抽出と SM-2 の日付算出で基準日を一貫させる（RFP 5.2「0:00 境界基準」）。
    await _sm2Service.gradeWord(
      wordId: word.id!,
      level: word.level,
      grade: grade,
      sessionType: sessionType,
      now: _now,
    );

    _grades.add(grade);

    // 次の単語（Step1）へ。全語消化なら finished が true になる。
    _index += 1;
    _step = SessionStep.word;
    notifyListeners();

    // 次の単語があれば自動再生する。
    if (!finished) _speakCurrent();
  }

  /// 現在の単語を音声で再生する（音声設定ONのときのみ。OFF時は speak 内部で無音）。
  void _speakCurrent() {
    final word = currentWord;
    if (word == null) return;
    // UI をブロックしないよう待たずに実行する（再生失敗はサービス側でフォールバック）。
    _ttsService.speak(word.word);
  }

  /// 端末ローカル日付の当日 0:00（RFP 5.2「0:00 境界基準」）。
  /// 構築時の初期化リストから呼べるよう static とする。
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    // 画面離脱時に再生中の音声を止める。
    _ttsService.stop();
    super.dispose();
  }
}
