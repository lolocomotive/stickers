import 'package:shared_preferences/shared_preferences.dart';

/// Quality presets used when exporting a sticker.
///
/// [auto] keeps the historical behaviour (start at a balanced setting and lower it until the
/// result fits WhatsApp's size limit). The other presets pick the starting point; the export
/// still degrades step by step if the result doesn't fit.
enum QualityPreset { max, balanced, small, auto, custom }

class QualityProfile {
  /// WebP quality, 0-100.
  final double quality;

  /// Frames per second of animated stickers.
  final int fps;

  /// libwebp compression effort, 0 (fast) - 6 (slowest, smallest).
  final int method;

  const QualityProfile({required this.quality, required this.fps, required this.method});

  static const int minFps = 8;
  static const int maxFps = 30;

  static const _presets = {
    QualityPreset.max: QualityProfile(quality: 85, fps: 30, method: 6),
    QualityPreset.balanced: QualityProfile(quality: 60, fps: 24, method: 4),
    QualityPreset.small: QualityProfile(quality: 40, fps: 15, method: 6),
    // Same starting point as balanced.
    QualityPreset.auto: QualityProfile(quality: 60, fps: 24, method: 4),
  };

  /// Profile for [preset]; [custom] is the user's own values.
  static QualityProfile of(QualityPreset preset, {QualityProfile? custom}) =>
      preset == QualityPreset.custom ? (custom ?? _presets[QualityPreset.balanced]!) : _presets[preset]!;

  QualityProfile copyWith({double? quality, int? fps, int? method}) =>
      QualityProfile(quality: quality ?? this.quality, fps: fps ?? this.fps, method: method ?? this.method);
}

/// Persists the chosen preset and custom values.
class QualitySettings {
  static const _kPreset = "qualityPreset";
  static const _kQuality = "qualityCustomQuality";
  static const _kFps = "qualityCustomFps";
  static const _kMethod = "qualityCustomMethod";

  QualityPreset preset;
  QualityProfile custom;

  QualitySettings({this.preset = QualityPreset.auto, QualityProfile? custom})
      : custom = custom ?? QualityProfile.of(QualityPreset.balanced);

  QualityProfile get profile => QualityProfile.of(preset, custom: custom);

  /// In [auto] mode the export lowers quality automatically when the result is too big.
  /// In every other mode the user's choice is tried first, with the same fallback so the
  /// sticker is always accepted by WhatsApp.
  static Future<QualitySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kPreset);
    return QualitySettings(
      preset: QualityPreset.values.firstWhere((p) => p.name == name, orElse: () => QualityPreset.auto),
      custom: QualityProfile(
        quality: prefs.getDouble(_kQuality) ?? 60,
        fps: prefs.getInt(_kFps) ?? 24,
        method: prefs.getInt(_kMethod) ?? 4,
      ),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPreset, preset.name);
    await prefs.setDouble(_kQuality, custom.quality);
    await prefs.setInt(_kFps, custom.fps);
    await prefs.setInt(_kMethod, custom.method);
  }
}
