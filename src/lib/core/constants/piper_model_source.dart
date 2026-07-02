/// Piper TTS モデルの取得先を集約する単一の決定点（TTS設計書 §5.5）。
///
/// RFP 第9章のとおり、取得先（GitHub Releases / Hugging Face 等の公開インフラ上の
/// 配布物）は実装時に選定して確定する。未確定の実値をソース上の固定リテラルとして
/// 埋め込まないため、取得先はコンパイル時環境変数（`--dart-define` →
/// `String.fromEnvironment`）としてビルド時に注入する。これにより選定結果の反映が
/// この1クラスで完結し、変更漏れを防ぐ。
///
/// ビルド例:
/// ```bash
/// flutter run \
///   --dart-define=PIPER_MODEL_BASE_URL=<公開インフラ上の配布ベースURL> \
///   --dart-define=PIPER_MODEL_FILE_NAME=<選定モデルのファイル名（.onnx）>
/// ```
///
/// Piper は実行時合成にモデル本体（`.onnx`）と設定ファイル（`.onnx.json`）を要するため、
/// 設定ファイルはモデルファイル名に `.json` を付した Piper の慣習名から導出する
/// （TTS設計書 §5.1「付随する設定ファイルが必要な場合はそれも含む」）。
class PiperModelSource {
  const PiperModelSource._();

  /// 公開インフラ上のモデル配布ベースURL（ビルド時に注入。未注入時は空文字）。
  static const String baseUrl = String.fromEnvironment('PIPER_MODEL_BASE_URL');

  /// 取得対象のモデル本体ファイル名（`.onnx`。ビルド時に注入。未注入時は空文字）。
  static const String modelFileName =
      String.fromEnvironment('PIPER_MODEL_FILE_NAME');

  /// 取得対象の設定ファイル名（`<model>.onnx.json`）。
  static String get configFileName => '$modelFileName.json';

  /// モデル本体の取得URL。
  static String get modelUrl => '$baseUrl/$modelFileName';

  /// 設定ファイルの取得URL。
  static String get configUrl => '$baseUrl/$configFileName';

  /// 取得先が注入済みか（未注入ではダウンロードを開始できない）。
  static bool get isConfigured =>
      baseUrl.isNotEmpty && modelFileName.isNotEmpty;
}
