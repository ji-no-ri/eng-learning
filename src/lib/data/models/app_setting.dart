/// アプリ設定（`app_settings` テーブル）の不変モデル。
///
/// キー・バリュー形式（RFP v1.1 第6章）。value はすべて文字列で保持し、
/// 未設定（Piper モデル未ダウンロード等）は null を取り得る。
class AppSetting {
  /// 設定キー（PRIMARY KEY）。
  final String key;

  /// 設定値（文字列。未設定は null）。
  final String? value;

  const AppSetting({required this.key, this.value});

  /// DB 行（Map）から生成する。
  factory AppSetting.fromMap(Map<String, dynamic> map) => AppSetting(
        key: map['key'] as String,
        value: map['value'] as String?,
      );

  /// DB 行（Map）へ変換する。
  Map<String, dynamic> toMap() => {
        'key': key,
        'value': value,
      };

  AppSetting copyWith({String? key, String? value}) => AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
      );

  @override
  String toString() => 'AppSetting(key: $key, value: $value)';
}
