import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/globals.dart';

import 'src/app.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';

void main() async {
  Stopwatch sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  PackageInfo.fromPlatform().then((result) => info = result);

  List<Future> tasks = [];

  final service = SettingsService();
  late SettingsController settingsController;
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
  tasks.add(getApplicationCacheDirectory().then((value) => imageCacheDir = "${value.path}/images"));

  // Calling this twice because the list is modified inbetween.
  // Not an elegant solution
  await Future.wait(tasks);
  await Future.wait(tasks);

  debugPrint(packsDir);
  debugPrint("Startup: ${sw.elapsedMilliseconds}ms");

  // Run the app and pass in the SettingsController. The app listens to the
  // SettingsController for changes, then passes it further down to the
  // SettingsView.
  runApp(MyApp(settingsController: settingsController));
}
