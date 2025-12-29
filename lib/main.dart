import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';

import 'src/app.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';

void main() async {
  Stopwatch sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  PackageInfo.fromPlatform().then((result) => info = result);

  List<Future> tasks = [];

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(
      ['Google fonts'],
      'SIL Open Font License\n\n$license',
    );
  });

  final service = SettingsService();
  tasks.add(
    service.waitForInit().then((value) {
      settingsController = SettingsController(service);
      tasks.add(settingsController.loadSettings());
    }),
  );

  tasks.add(
    getApplicationDocumentsDirectory().then((value) {
      packsDir = "${value.path}/packs";
      tasks.add(Directory(packsDir).create(recursive: true));
      tasks.add(getPacks().then((value) {
        packs = value;
        debugPrint("Added packs");
      }));
    }),
  );
  tasks.add(createDirs());

  // It's okay to not wait for this to be finished before we start the app
  // We assume the user will not create text in stickers in the first 500ms when the app is started
  FontsRegistry.init();

  // Calling this twice because the list is modified in between.
  // Not an elegant solution
  await Future.wait(tasks);
  await Future.wait(tasks);

  debugPrint("Startup: ${sw.elapsedMilliseconds}ms");

  // Run the app and pass in the SettingsController. The app listens to the
  // SettingsController for changes, then passes it further down to the
  // SettingsView.
  runApp(StickersApp(settingsController: settingsController));
}

/// Creates the directory structure for the app to function
///
/// ```
/// app_flutter
/// ├── bundled_fonts
/// │   ├── DM Serif Text.ttf
/// │   ...
/// ├── cache                               // Used for temporary stuff. Not using flutter-provided temp dir because
/// │                                       // Android may delete it while the app is running, which breaks the app
/// │   ├── exported_packs                  // Packs that have been exported for the user to share
/// │   ├── fonts                           // Font previews downloaded by the fonts manager
/// │   └── media                           // Where media gets stored before getting cropped and processed into a sticker
/// ├── flutter_assets
/// │   ...
/// ├── fonts.json                          // Json file for the fonts registry
/// ├── packs                               // Folder where all sticker packs are stored
/// │   ├── pack_1767046146925              // Original pack name if imported, UID if created from the app
/// │   │   ├── 0_7a5870ea8035b6d2
/// │   │   ├── 0_7a5870ea8035b6d2.json     // Editor data, needed to edit stickers after they are made
/// │   │   ├── 0_7a5870ea8035b6d2.webp     // Sticker file (edited image)
/// │   │   │   └── background.webp         // Background image/video
/// │   │   ├── 1_3de0a47000e17e7b
/// │   │   ├── 1_3de0a47000e17e7b.json
/// │   │   └── 1_3de0a47000e17e7b.webp
/// │   │       └── background.webp
/// │   ├── pack_1767046194568
/// │   │   ├── 0_b10ec36cbb4a8154
/// │   │   ├── 0_b10ec36cbb4a8154.json
/// │   │   └── 0_b10ec36cbb4a8154.webp
/// │   │       └── background.webp
/// │   └── packs.json
/// └── sticker_packs.json                  // Main json file with all sticker packs
/// ```

Future<void> createDirs() async {
  await getApplicationDocumentsDirectory().then((value) async {
    final List<Future> tasks = [];
    cacheDir = "${value.path}/cache";
    exportCacheDir = "${value.path}/cache/exported_packs";
    mediaCacheDir = "${value.path}/cache/media";
    fontsCacheDir = "${value.path}/cache/fonts";
    tasks.addAll([
      Directory(mediaCacheDir).create(recursive: true),
      Directory(exportCacheDir).create(recursive: true),
      Directory(fontsCacheDir).create(recursive: true),
    ]);
    await Future.wait(tasks);
  });
}
