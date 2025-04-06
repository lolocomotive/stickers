import 'package:flutter/material.dart';

import 'settings_service.dart';

/// A class that many Widgets can interact with to read user settings, update
/// user settings, or listen to user settings changes.
///
/// Controllers glue Data Services to Flutter Widgets. The SettingsController
/// uses the SettingsService to store and retrieve user settings.
class SettingsController with ChangeNotifier {
  SettingsController(this._settingsService);

  // Make SettingsService a private variable so it is not used directly.
  final SettingsService _settingsService;

  // Make ThemeMode a private variable so it is not updated directly without
  // also persisting the changes with the SettingsService.
  late ThemeMode _themeMode;

  late bool _quickMode;

  late String _defaultAuthor;
  late String _defaultTitle;

  String get defaultTitle => _defaultTitle;

  String get defaultAuthor => _defaultAuthor;

  // Allow Widgets to read the user's preferred ThemeMode.
  ThemeMode get themeMode => _themeMode;

  bool get quickMode => _quickMode;

  Future<void> updateQuickMode(bool quickMode) async {
    // Do not perform any work if new and old ThemeMode are identical
    if (quickMode == _quickMode) return;

    // Otherwise, store the new ThemeMode in memory
    _quickMode = quickMode;

    // Important! Inform listeners a change has occurred.
    notifyListeners();

    // Persist the changes to a local database or the internet using the
    // SettingService.
    await _settingsService.updateQuickMode(quickMode);
  }

  Future<void> updateDefaultAuthor(String defaultAuthor) async {
    // Do not perform any work if new and old ThemeMode are identical
    if (defaultAuthor == _defaultAuthor) return;

    // Otherwise, store the new ThemeMode in memory
    _defaultAuthor = defaultAuthor;

    notifyListeners();
    await _settingsService.updateDefaultAuthor(defaultAuthor);
  }

  Future<void> updateDefaultTitle(String defaultTitle) async {
    if (defaultTitle == _defaultTitle) return;
    _defaultTitle = defaultTitle;
    notifyListeners();
    await _settingsService.updateDefaultTitle(defaultTitle);
  }

  /// Load the user's settings from the SettingsService. It may load from a
  /// local database or the internet. The controller only knows it can load the
  /// settings from the service.
  Future<void> loadSettings() async {
    _themeMode = await _settingsService.themeMode();
    _quickMode = await _settingsService.quickMode();
    _defaultTitle = await _settingsService.defaultTitle();
    _defaultAuthor = await _settingsService.defaultAuthor();

    notifyListeners();
  }

  /// Update and persist the ThemeMode based on the user's selection.
  Future<void> updateThemeMode(ThemeMode? newThemeMode) async {
    if (newThemeMode == null) return;
    if (newThemeMode == _themeMode) return;

    _themeMode = newThemeMode;
    notifyListeners();
    await _settingsService.updateThemeMode(newThemeMode);
  }
}
