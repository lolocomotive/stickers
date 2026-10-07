import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:restart_app/restart_app.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/dialogs/edit_quickmode_defaults_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings.dart';

/// Displays the various settings that can be customized by the user.
///
/// When a user changes a setting, the corresponding [Setting] is updated and
/// this page is rebuilt.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const routeName = "/settings";

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        settings.themeMode,
        settings.locale,
        settings.quickMode,
        settings.defaultTitle,
        settings.defaultAuthor,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
      ),
      body: Column(
        children: [
          _DropdownTile(
            icon: Icons.invert_colors,
            title: AppLocalizations.of(context)!.theme,
            setting: settings.themeMode,
            items: {
              ThemeMode.system: AppLocalizations.of(context)!.system,
              ThemeMode.light: AppLocalizations.of(context)!.light,
              ThemeMode.dark: AppLocalizations.of(context)!.dark,
            },
          ),
          _DropdownTile(
            icon: Icons.language,
            title: AppLocalizations.of(context)!.language,
            setting: settings.locale,
            items: const {
              "en": "English",
              "fr": "Français",
              "de": "Deutsch",
              "ru": "Русский",
              "pt": "Português",
            },
          ),
          ListTile(
            onTap: () => settings.quickMode.value = !settings.quickMode.value,
            title: Text(AppLocalizations.of(context)!.quickMode),
            leading: const Icon(Icons.bolt),
            subtitle: Opacity(
              opacity: .7,
              child: Text(AppLocalizations.of(context)!.settings_quickmode_description),
            ),
            trailing: Switch(value: settings.quickMode.value, onChanged: (v) => settings.quickMode.value = v),
          ),
          if (settings.quickMode.value)
            ListTile(
              onTap: () => _showQuickModeDefaultsDialog(context),
              leading: Icon(Icons.account_circle),
              subtitle: Opacity(
                  opacity: .7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("${AppLocalizations.of(context)!.title}: ${settings.defaultTitle.value}"),
                      Text("${AppLocalizations.of(context)!.author}: ${settings.defaultAuthor.value}")
                    ],
                  )),
              title: Text(AppLocalizations.of(context)!.quickModeDefaults),
              trailing: ElevatedButton(
                  onPressed: () => _showQuickModeDefaultsDialog(context),
                  child: Text(AppLocalizations.of(context)!.edit)),
            ),
          ListTile(
            onTap: () {
              Navigator.of(context).pushNamed("/settings/fonts");
            },
            leading: Icon(Icons.text_fields),
            title: Text(AppLocalizations.of(context)!.fontsManager),
            subtitle: Opacity(
              opacity: .7,
              child: Text(AppLocalizations.of(context)!.fontsManagerDetails),
            ),
          ),
          ListTile(
            title: Text(AppLocalizations.of(context)!.clearCache),
            subtitle: Opacity(
              opacity: .7,
              child: Text(AppLocalizations.of(context)!.thisWillRestart),
            ),
            onTap: () async {
              await Directory(cacheDir).delete(recursive: true);
              await (await getTemporaryDirectory()).delete(recursive: true);
              Restart.restartApp();
            },
            leading: Icon(Icons.storage),
            trailing: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!,
              child: CacheUseIndicator(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppLocalizations.of(context)!.about),
            subtitle: info == null
                ? null
                : Opacity(
                    opacity: .7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${info!.appName} v${info!.version}+${info!.buildNumber}"),
                      ],
                    ),
                  ),
            trailing: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LicensePage()),
                    ),
                child: Text(AppLocalizations.of(context)!.licences)),
          ),
          ListTile(
            onTap: () {
              String url = "https://github.com/lolocomotive/stickers";
              launchUrl(Uri.parse(url));
            },
            leading: Icon(Icons.code),
            title: Text("GitHub"),
            subtitle: Opacity(
              opacity: .7,
              child: Text(AppLocalizations.of(context)!.sourceOnGithub),
            ),
            trailing: Icon(Icons.open_in_new),
          )
        ],
      ),
    );
  }

  void _showQuickModeDefaultsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EditQuickmodeDefaultsDialog(),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({required this.icon, required this.title, required this.setting, required this.items});

  final IconData icon;
  final String title;
  final Setting<T> setting;
  final Map<T, String> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Flexible(
            child: Container(
              padding: const EdgeInsets.only(left: 16, right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: ElevationOverlay.applySurfaceTint(colors.surface, colors.primary, 2),
              ),
              child: DropdownButton<T>(
                borderRadius: BorderRadius.circular(16),
                dropdownColor: ElevationOverlay.applySurfaceTint(colors.surface, colors.primary, 4),
                underline: Container(),
                value: setting.value,
                items: [
                  for (final item in items.entries)
                    DropdownMenuItem(
                      value: item.key,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(item.value),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setting.value = value;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CacheUseIndicator extends StatelessWidget {
  const CacheUseIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _getCacheSize(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            int size = snapshot.data!;
            if (size >= 1000000000) {
              return Text("${size.toStringAsPrecision(2)} GB");
            } else if (size >= 1000000) {
              return Text("${(size / 1000000).toStringAsPrecision(3)} MB");
            } else if (size >= 1000) {
              return Text("${(size / 1000).toStringAsPrecision(3)} KB");
            } else {
              return Text("$size B");
            }
          } else {
            return CircularProgressIndicator();
          }
        });
  }

  Future<int> _getCacheSize() async {
    int totalSize = 0;
    await Directory(cacheDir).list(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (entity is File) {
        totalSize += entity.lengthSync();
      }
    });
    await (await getTemporaryDirectory()).list(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (entity is File) {
        totalSize += entity.lengthSync();
      }
    });

    return totalSize;
  }
}
