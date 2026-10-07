import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/data/storage.dart';
import 'package:stickers/src/globals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync("stickers_test").absolute;
    dataDir = root.path.replaceAll("\\", "/");
    packsDir = "$dataDir/packs";
    Directory(packsDir).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  File touch(String path) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync("x");

  group("paths", () {
    test("are stored relative to the root", () {
      expect(relativePath("$packsDir/p/0.webp", packsDir), "p/0.webp");
      expect(resolvePath("p/0.webp", packsDir), "$packsDir/p/0.webp");
    });

    test("from older versions are moved to the current root", () {
      expect(
        resolvePath("/data/user/0/app/app_flutter/packs/p/0.webp", packsDir),
        "$packsDir/p/0.webp",
      );
      expect(resolvePath("$packsDir/p/0.webp", packsDir), "$packsDir/p/0.webp");
    });

    test("outside the root are kept", () {
      expect(relativePath("/elsewhere/0.webp", packsDir), "/elsewhere/0.webp");
      expect(resolvePath("/elsewhere/0.webp", packsDir), "/elsewhere/0.webp");
    });

    test("round trip through pack json", () {
      final pack = StickerPack("t", "a", "p", [Sticker("$packsDir/p/0.webp", ["❤"], "$packsDir/p/0.json")], "1", false,
          trayIcon: "$packsDir/p/tray.webp");
      final json = jsonDecode(jsonEncode(pack.toJson()));
      expect(json["trayIcon"], "p/tray.webp");
      expect(json["stickers"][0]["source"], "p/0.webp");
      final loaded = StickerPack.fromJson(json);
      expect(loaded.stickers.single.source, "$packsDir/p/0.webp");
      expect(loaded.stickers.single.editorData, "$packsDir/p/0.json");
      expect(loaded.trayIcon, "$packsDir/p/tray.webp");
    });
  });

  group("cleanUpPacks", () {
    test("deletes only unused files and migrates absolute paths", () async {
      final dir = "$packsDir/p";
      touch("$dir/0_a.webp");
      touch("$dir/0_a/background.webp");
      File("$dir/0_a.json").writeAsStringSync(jsonEncode({
        "background": "/old/location/app_flutter/packs/p/0_a/background.webp",
        "layers": [],
      }));
      touch("$dir/batch_1/0.webp");
      touch("$dir/tray.webp");
      touch("$dir/whatsapp_tray.png");
      touch("$dir/tray.png");
      touch("$dir/1_b.webp");
      touch("$dir/1_b/background.mp4");
      touch("$dir/empty/nested/stale.webp");
      touch("$packsDir/.trash_x/0.webp");
      touch("$packsDir/orphan/0.webp");
      File("$packsDir/packs.json").writeAsStringSync(jsonEncode([
        {
          "id": "p",
          "title": "t",
          "author": "a",
          "imageDataVersion": "1",
          "animated": false,
          "trayIcon": "/old/location/app_flutter/packs/p/tray.webp",
          "stickers": [
            {"source": "/old/location/app_flutter/packs/p/0_a.webp", "emojis": [], "editorData": "p/0_a.json"},
            {"source": "p/batch_1/0.webp", "emojis": [], "editorData": null},
          ],
        }
      ]));

      packs = await getPacks();
      await cleanUpPacks();

      final remaining = Directory(packsDir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => relativePath(f.path.replaceAll("\\", "/"), packsDir))
          .toSet();
      expect(remaining, {
        "packs.json",
        "orphan/0.webp",
        "p/0_a.webp",
        "p/0_a.json",
        "p/0_a/background.webp",
        "p/batch_1/0.webp",
        "p/tray.webp",
        "p/whatsapp_tray.png",
      });
      expect(Directory("$dir/empty").existsSync(), isFalse);
      expect(Directory("$dir/1_b").existsSync(), isFalse);

      final saved = jsonDecode(File("$packsDir/packs.json").readAsStringSync());
      expect(saved[0]["trayIcon"], "p/tray.webp");
      expect(saved[0]["stickers"][0]["source"], "p/0_a.webp");
      final editorData = jsonDecode(File("$dir/0_a.json").readAsStringSync());
      expect(editorData["background"], "p/0_a/background.webp");
    });

    test("keeps everything when a sticker is missing", () async {
      touch("$packsDir/p/0.webp");
      touch("$packsDir/p/unknown.webp");
      packs = [
        StickerPack("t", "a", "p", [Sticker("$packsDir/p/0.webp", [], null), Sticker("$packsDir/p/gone.webp", [], null)],
            "1", false),
      ];
      await cleanUpPacks();
      expect(File("$packsDir/p/unknown.webp").existsSync(), isTrue);
    });
  });

  test("savePacks keeps the last save", () async {
    packs = [StickerPack("first", "a", "p", [], "1", false)];
    final first = savePacks(packs);
    packs = [StickerPack("second", "a", "p", [], "1", false)];
    await Future.wait([first, savePacks(packs)]);
    final saved = jsonDecode(File("$packsDir/packs.json").readAsStringSync());
    expect(saved[0]["title"], "second");
    expect(File("$packsDir/packs.json.tmp").existsSync(), isFalse);
  });
}
