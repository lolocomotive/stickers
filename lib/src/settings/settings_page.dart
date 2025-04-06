import 'package:flutter/material.dart';
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
        title: const Text('Settings'),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.invert_colors),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Theme'),
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
                      items: const [
                        DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('System'),
                            )),
                        DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('Light'),
                            )),
                        DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('Dark'),
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
            title: const Text("Quick mode"),
            leading: const Icon(Icons.bolt),
            subtitle: const Opacity(
              opacity: .7,
              child: Text(
                  "Adds shared images as stickers automatically without any interaction"),
            ),
            trailing: Switch(
                value: controller.quickMode,
                onChanged: controller.updateQuickMode),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text("About"),
            subtitle: info == null
                ? null
                : Opacity(
                    opacity: .7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            "${info!.appName} v${info!.version}+${info!.buildNumber}"),
                      ],
                    ),
                  ),
            trailing: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LicensePage()),
                    ),
                child: const Text("Licences")),
          ),
        ],
      ),
    );
  }
}
