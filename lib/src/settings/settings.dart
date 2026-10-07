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

/// All user settings, backed by SharedPreferences.
///
/// To add a setting, declare one more field below.
class Settings {
  Settings._(this._prefs);

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  late final themeMode = _enum("themeMode", ThemeMode.values, ThemeMode.system);
  late final locale = _string("locale", _systemLocale());
  late final quickMode = _bool("quickMode", false);
  late final defaultTitle = _string("defaultTitle", "New sticker pack");
  late final defaultAuthor = _string("defaultAuthor", "auto-generated");

  /// Whether the user has agreed or not to use the google fonts service
  late final googleFonts = _bool("googleFonts", false);
  late final exportIncludeEditData = _bool("exportIncludeEditData", true);
  late final exportStickerFormat = _enum("exportStickerFormat", StickerFormat.values, StickerFormat.png);

  static const supportedLocales = ["en", "fr", "de", "ru", "pt"];

  static String _systemLocale() =>
      supportedLocales.firstWhere((l) => Platform.localeName.startsWith(l), orElse: () => "en");

  Setting<bool> _bool(String key, bool fallback) =>
      Setting(_prefs.getBool(key) ?? fallback, (v) => _prefs.setBool(key, v));

  Setting<String> _string(String key, String fallback) =>
      Setting(_prefs.getString(key) ?? fallback, (v) => _prefs.setString(key, v));

  Setting<E> _enum<E extends Enum>(String key, List<E> values, E fallback) =>
      Setting(values.asNameMap()[_prefs.getString(key)] ?? fallback, (v) => _prefs.setString(key, v.name));
}
