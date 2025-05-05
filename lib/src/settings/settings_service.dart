import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service that stores and retrieves user settings.
///
/// By default, this class does not persist user settings. If you'd like to
/// persist the user settings locally, use the shared_preferences package. If
/// you'd like to store settings on a web server, use the http package.
class SettingsService {
  late SharedPreferences _prefs;
  late Future<SharedPreferences> _pFuture;

  SettingsService() {
    _pFuture = SharedPreferences.getInstance().then((value) => _prefs = value);
  }

  Future waitForInit() async {
    await _pFuture;
  }

  /// Loads the User's preferred ThemeMode from local or remote storage.
  Future<ThemeMode> themeMode() async {
    String mode = _prefs.getString("themeMode") ?? "";
    return ThemeMode.values.firstWhere(
      (element) => element.name == mode,
      orElse: () => ThemeMode.system,
    );
  }

  Future<bool> quickMode() async => _prefs.getBool("quickMode") ?? false;

  Future<String> defaultTitle() async => _prefs.getString("defaultPackName") ?? "New sticker pack";

  Future<String> defaultAuthor() async => _prefs.getString("defaultAuthor") ?? "auto-generated";
  Future<String> locale() async => _prefs.getString("locale") ?? _getLocale();

  /// Gets the locale from the system settings if unset in config
  String _getLocale(){
      if(Platform.localeName.startsWith("de")) return "de";
      if(Platform.localeName.startsWith("fr")) return "fr";
      return "en";
  }

  /// Persists the user's preferred ThemeMode to local or remote storage.
  Future<void> updateThemeMode(ThemeMode theme) async {
    _prefs.setString("themeMode", theme.name);
  }

  Future<void> updateQuickMode(bool quickMode) async {
    _prefs.setBool("quickMode", quickMode);
  }

  Future<void> updateDefaultTitle(String defaultTitle) async {
    _prefs.setString("defaultTitle", defaultTitle);
  }

  Future<void> updateDefaultAuthor(String defaultAuthor) async {
    _prefs.setString("defaultAuthor", defaultAuthor);
  }

  Future<void> updateLocale(String locale) async {
    _prefs.setString("locale", locale);
  }
}
