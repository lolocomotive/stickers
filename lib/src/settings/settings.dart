import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickers/src/data/sticker_encoding.dart';

/// A single persisted user setting. Assigning [value] notifies listeners and
/// writes the new value to storage.
class Setting<T> extends ValueNotifier<T> {
  Setting(super.value, this._persist);

  final void Function(T value) _persist;

  @override
  set value(T newValue) {
    if (newValue == value) return;
    super.value = newValue;
    _persist(newValue);
  }
}

enum VideoInputMethod { ask, gallery, filePicker }

/// All user settings, backed by SharedPreferences.
///
/// To add a setting, declare one more field below.
class Settings {
  Settings._(this._prefs);

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  late final themeMode = _enum("themeMode", ThemeMode.values, ThemeMode.system);

  /// Color the theme is generated from. Null means the system's dynamic colors.
  late final accentColor = _nullableColor("accentColor");
  late final locale = _string("locale", _systemLocale());
  late final quickMode = _bool("quickMode", false);
  late final defaultTitle = _string("defaultTitle", "New sticker pack");
  late final defaultAuthor = _string("defaultAuthor", "auto-generated");

  /// Whether the user has agreed or not to use the google fonts service
  late final googleFonts = _bool("googleFonts", false);
  late final exportIncludeEditData = _bool("exportIncludeEditData", true);
  late final exportStickerFormat = _enum("exportStickerFormat", StickerFormat.values, StickerFormat.png);

  /// Initial state of the crop pages. A null aspect ratio means free cropping.
  late final defaultStretch = _bool("defaultStretch", false);
  late final defaultAspectRatio = _nullableDouble("defaultAspectRatio");

  /// Where videos for animated stickers are picked from.
  late final videoInputMethod = _enum("videoInputMethod", VideoInputMethod.values, VideoInputMethod.ask);

  static const supportedLocales = ["en", "fr", "de", "ru", "pt"];

  static String _systemLocale() =>
      supportedLocales.firstWhere((l) => Platform.localeName.startsWith(l), orElse: () => "en");

  Setting<bool> _bool(String key, bool fallback) =>
      Setting(_prefs.getBool(key) ?? fallback, (v) => _prefs.setBool(key, v));

  Setting<String> _string(String key, String fallback) =>
      Setting(_prefs.getString(key) ?? fallback, (v) => _prefs.setString(key, v));

  Setting<double?> _nullableDouble(String key) =>
      Setting(_prefs.getDouble(key), (v) => v == null ? _prefs.remove(key) : _prefs.setDouble(key, v));

  Setting<Color?> _nullableColor(String key) {
    final stored = _prefs.getInt(key);
    return Setting(
      stored == null ? null : Color(stored),
      (v) => v == null ? _prefs.remove(key) : _prefs.setInt(key, v.toARGB32()),
    );
  }

  Setting<E> _enum<E extends Enum>(String key, List<E> values, E fallback) =>
      Setting(values.asNameMap()[_prefs.getString(key)] ?? fallback, (v) => _prefs.setString(key, v.name));
}
