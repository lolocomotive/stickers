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

Future<void> createDirs() async {
  await getApplicationCacheDirectory().then((value) async {
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
