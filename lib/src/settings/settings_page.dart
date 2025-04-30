import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/dialogs/edit_quickmode_defaults_dialog.dart';
import 'package:stickers/src/globals.dart';

import 'settings_controller.dart';

/// Displays the various settings that can be customized by the user.
///
/// When a user changes a setting, the SettingsController is updated and
/// Widgets that listen to the SettingsController are rebuilt.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  static const routeName = '/settings';

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.invert_colors),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(AppLocalizations.of(context)!.theme),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: ElevationOverlay.applySurfaceTint(
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.primary,
                        2,
                      ),
                    ),
                    child: DropdownButton<ThemeMode>(
                      borderRadius: BorderRadius.circular(16),
                      dropdownColor: ElevationOverlay.applySurfaceTint(
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.primary,
                        4,
                      ),
                      underline: Container(),
                      value: controller.themeMode,
                      items: [
                        DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(AppLocalizations.of(context)!.system),
                            )),
                        DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(AppLocalizations.of(context)!.light),
                            )),
                        DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(AppLocalizations.of(context)!.dark),
                            )),
                      ],
                      onChanged: controller.updateThemeMode,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            onTap: () {
              controller.updateQuickMode(!controller.quickMode);
            },
            title: Text(AppLocalizations.of(context)!.quickMode),
            leading: const Icon(Icons.bolt),
            subtitle: Opacity(
              opacity: .7,
              child: Text(AppLocalizations.of(context)!.settings_quickmode_description),
            ),
            trailing: Switch(value: controller.quickMode, onChanged: controller.updateQuickMode),
          ),
          if (controller.quickMode)
            ListTile(
              onTap: () => _showQuickModeDefaultsDialog(context),
              leading: Icon(Icons.account_circle),
              subtitle: Opacity(
                  opacity: .7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("${AppLocalizations.of(context)!.title}: ${controller.defaultTitle}"),
                      Text("${AppLocalizations.of(context)!.author}: ${controller.defaultAuthor}")
                    ],
                  )),
              title: Text(AppLocalizations.of(context)!.quickModeDefaults),
              trailing: ElevatedButton(
                  onPressed: () => _showQuickModeDefaultsDialog(context),
                  child: Text(AppLocalizations.of(context)!.edit)),
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
        ],
      ),
    );
  }

  _showQuickModeDefaultsDialog(context) {
    showDialog(
      context: context,
      builder: (context) => EditQuickmodeDefaultsDialog(
        settingsController: controller,
      ),
    );
  }
}
