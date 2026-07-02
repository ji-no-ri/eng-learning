import 'package:flutter/material.dart';

import '../data/repositories/settings_repository.dart';
import '../services/piper_download_service.dart';
import '../services/tts_service.dart';

/// 設定画面（RFP 4.5）。ホーム画面右上の設定アイコンから遷移し、以下を1画面に表示する。
///
/// 1. 音声設定
///    - 「読み上げ音声」ON/OFF スイッチ。切替で [TtsService.setAudioEnabled] を通じて
///      `app_settings.audio_enabled` に即時反映・永続化する（RFP 受け入れ基準 §11）。
/// 2. TTSエンジン
///    - 現在有効なエンジン（`OS標準（flutter_tts）` / `Piper TTS`）を表示する。
///    - Piper TTS ボタンの状態遷移（RFP 4.5 状態遷移表・Mermaid）:
///      - 状態A（未DL）: 「Piper TTSを使用する」。押下→[TtsService.enablePiper] で
///        モデルをダウンロード（進捗表示）→完了で `tts_engine='piper'` へ切替→状態Bへ。
///        失敗時はエラーメッセージを表示し状態Aのまま維持する。
///      - 状態B（DL済み・使用中）: 「Piper TTSを使用しない」。押下→[TtsService.disablePiper]
///        でモデル削除→`tts_engine='flutter_tts'`→状態Aへ戻す。
/// 3. データソース・クレジット表示（RFP 第2章の文言をそのまま表示）。
///
/// 状態A/Bの判定は `app_settings`（`tts_engine` / `piper_model_path`）の永続値に基づく。
/// 現在有効なエンジン表示も同様に永続値に従う（実行時の合成実装可否には依存しない）。
///
/// 戻る（AppBar の戻るボタン）でホーム画面へ戻る（設定画面はホームから push される）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.ttsService,
    this.settingsRepository,
  });

  /// 音声設定・Piper 有効化／無効化に用いる TTS サービス（省略時は既定インスタンス）。
  final TtsService? ttsService;

  /// Piper ボタンの状態判定（`tts_engine` / `piper_model_path` の参照）に用いる設定リポジトリ。
  /// 省略時は既定インスタンス（[TtsService] と同一の `DatabaseHelper` を共有する）。
  final SettingsRepository? settingsRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TtsService _tts;
  late final SettingsRepository _settings;

  /// 初期状態の読み込み中フラグ。
  bool _loading = true;

  /// 読み上げ音声の ON/OFF（`app_settings.audio_enabled`）。
  bool _audioEnabled = true;

  /// 現在有効な TTS エンジン（`app_settings.tts_engine`）。
  String _engine = SettingsRepository.ttsEngineFlutter;

  /// Piper モデルの保存パス（`app_settings.piper_model_path`。未DLなら null）。
  String? _piperModelPath;

  /// Piper のダウンロード中フラグ（状態A→B の処理中）。
  bool _downloading = false;

  /// ダウンロード進捗（0.0〜1.0）。Content-Length 不明時などは null（不確定表示）。
  double? _progress;

  /// Piper 無効化（状態B→A）の処理中フラグ。
  bool _disabling = false;

  /// 直近のダウンロード失敗メッセージ（成功・未実行時は null）。
  String? _error;

  /// Piper がダウンロード済み・使用中か（状態B）。未DL（状態A）なら false。
  ///
  /// RFP 4.5 状態遷移表の状態B（「ダウンロード済み・使用中」）に一致させるため、
  /// `tts_engine == 'piper'` かつモデルパスが非空の両方を満たす場合のみ true とする。
  /// モデルパスの有無だけで判定すると、`tts_engine != 'piper'` なのにパスが残っている
  /// 状態（例: 無効化途中の不整合や外部要因で片方だけ残った場合）でも状態B表示となり、
  /// 「現在: OS標準（flutter_tts）」というエンジン表示と矛盾するため、両条件で判定する。
  bool get _piperInUse =>
      _engine == SettingsRepository.ttsEnginePiper &&
      _piperModelPath != null &&
      _piperModelPath!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tts = widget.ttsService ?? TtsService();
    _settings = widget.settingsRepository ?? SettingsRepository();
    _loadState();
  }

  /// 永続化された設定値を読み込み、画面状態へ反映する。
  Future<void> _loadState() async {
    final audio = await _tts.isAudioEnabled();
    final engine = await _settings.getTtsEngine();
    final modelPath = await _settings.getPiperModelPath();
    if (!mounted) return;
    setState(() {
      _audioEnabled = audio;
      _engine = engine;
      _piperModelPath = modelPath;
      _loading = false;
    });
  }

  /// 読み上げ音声 ON/OFF の切替（即時永続化）。
  Future<void> _onToggleAudio(bool enabled) async {
    setState(() => _audioEnabled = enabled);
    await _tts.setAudioEnabled(enabled);
  }

  /// Piper TTS を有効化する（状態A→B）。進捗を表示し、失敗時は状態Aを維持する。
  Future<void> _enablePiper() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      await _tts.enablePiper(
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      // 成功時のみ設定が書き換わる。永続値を読み直して状態Bへ更新する。
      await _loadState();
    } on PiperDownloadException catch (e) {
      // 失敗時は tts_engine / piper_model_path は変更されない（状態Aを維持）。
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Piper TTS の有効化に失敗しました。時間をおいて再試行してください。');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Piper TTS を無効化する（状態B→A）。モデル削除後に flutter_tts へ戻す。
  Future<void> _disablePiper() async {
    setState(() {
      _disabling = true;
      _error = null;
    });
    try {
      await _tts.disablePiper();
      await _loadState();
    } finally {
      if (mounted) setState(() => _disabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _AudioSection(
                  enabled: _audioEnabled,
                  onChanged: _onToggleAudio,
                ),
                const SizedBox(height: 8),
                _TtsEngineSection(
                  engine: _engine,
                  piperInUse: _piperInUse,
                  downloading: _downloading,
                  disabling: _disabling,
                  progress: _progress,
                  error: _error,
                  onEnablePiper: _enablePiper,
                  onDisablePiper: _disablePiper,
                ),
                const SizedBox(height: 8),
                const _CreditsSection(),
              ],
            ),
    );
  }
}

/// セクション見出し＋カード本文（設定画面共通の枠）。
class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.title, required this.child});

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

/// 音声設定セクション（RFP 4.5「読み上げ音声 ON/OFF」）。
class _AudioSection extends StatelessWidget {
  const _AudioSection({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingCard(
      title: '音声設定',
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('読み上げ音声'),
        subtitle: const Text('単語表示時に発音を自動再生します。'),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

/// TTSエンジンセクション（RFP 4.5 現在エンジン表示・Piper 状態遷移）。
class _TtsEngineSection extends StatelessWidget {
  const _TtsEngineSection({
    required this.engine,
    required this.piperInUse,
    required this.downloading,
    required this.disabling,
    required this.progress,
    required this.error,
    required this.onEnablePiper,
    required this.onDisablePiper,
  });

  final String engine;
  final bool piperInUse;
  final bool downloading;
  final bool disabling;
  final double? progress;
  final String? error;
  final VoidCallback onEnablePiper;
  final VoidCallback onDisablePiper;

  /// 現在有効なエンジンの表示名。
  String get _engineLabel => engine == SettingsRepository.ttsEnginePiper
      ? 'Piper TTS'
      : 'OS標準（flutter_tts）';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = downloading || disabling;
    return _SettingCard(
      title: 'TTSエンジン',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 現在有効なエンジン表示（RFP 4.5「現在: …」）。
          Row(
            children: [
              Icon(Icons.record_voice_over, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '現在: '),
                      TextSpan(
                        text: _engineLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            'Piper TTS（高品質音声）',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            piperInUse ? 'ダウンロード済み（使用中）' : '未ダウンロード',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // ダウンロード進捗（状態A→B の処理中のみ表示）。
          if (downloading) ...[
            _DownloadProgress(progress: progress),
            const SizedBox(height: 12),
          ],
          // 状態A/B に応じたボタン（RFP 4.5 状態遷移表）。
          if (piperInUse)
            OutlinedButton.icon(
              onPressed: busy ? null : onDisablePiper,
              icon: disabling
                  ? const _ButtonSpinner()
                  : const Icon(Icons.delete_outline),
              label: const Text('Piper TTSを使用しない'),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : onEnablePiper,
              icon: downloading
                  ? const _ButtonSpinner()
                  : const Icon(Icons.download),
              label: Text(downloading ? 'ダウンロード中…' : 'Piper TTSを使用する'),
            ),
          // 失敗時のエラーメッセージ（状態Aのまま維持。RFP 4.5）。
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ダウンロード進捗表示（% 判明時はバー＋数値、不明時は不確定インジケータ）。
class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = progress == null ? null : (progress! * 100).clamp(0, 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          percent == null ? 'モデルをダウンロードしています…' : 'ダウンロード中… $percent%',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// ボタン内に置く小さめのスピナー（処理中表示）。
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// データソース・クレジット表示セクション（RFP 第2章の文言をそのまま表示）。
class _CreditsSection extends StatelessWidget {
  const _CreditsSection();

  /// RFP 第2章「アプリ内クレジット表示（設定画面）」の3行をそのまま表示する。
  static const List<String> _credits = [
    'JACET8000 (Japan Association of College English Teachers)',
    'Wiktionary - CC BY-SA 4.0 (https://en.wiktionary.org/)',
    'Algorithm SM-2, (C) Copyright SuperMemo World, 1991',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SettingCard(
      title: 'データソース・クレジット表示',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in _credits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('・'),
                  Expanded(
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
