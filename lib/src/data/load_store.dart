import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:image_editor/image_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

Future<void> savePacks(List<StickerPack> packs) async {
  try {
    File output = File("$packsDir/packs.json");
    await output.writeAsString(
        jsonEncode(packs.map((pack) => pack.toJson()).toList()),
        flush: true);
  } catch (e) {
    debugPrint("Error saving packs: $e");
  }
}

Future<void> exportPack(StickerPack pack) async {
  Stopwatch sw = Stopwatch()..start();
  Directory exportDir = Directory(exportCacheDir);
  Directory packDir = Directory(
      "${exportDir.path}/pack_${DateTime.timestamp().millisecondsSinceEpoch}");
  await packDir.create(recursive: true);
  File jsonFile = File("${packDir.path}/pack.json");
  Map<String, dynamic> exportData = pack.toJson();

  for (var i = 0; i < pack.stickers.length; i++) {
    final dest = "${packDir.path}/$i.webp";
    await File(pack.stickers[i].source).copy(dest);
    exportData["stickers"][i]["source"] = "$i.webp";
  }
  if (pack.trayIcon != null) {
    final dest = "${packDir.path}/tray.png";
    await File(pack.trayIcon!).copy(dest);
    exportData["trayIcon"] = "tray.png";
  }
  debugPrint("Copy t=${sw.elapsedMilliseconds}ms");
  await jsonFile.writeAsString(jsonEncode(exportData), flush: true);
  debugPrint("Json written  t=${sw.elapsedMilliseconds}ms");

  File zipFile = File(
      "${exportDir.path}/${pack.title.replaceAll(RegExp("[^ \\-_!&a-zA-Z0-9]"), "_")}.zip");
  await ZipFile.createFromDirectory(sourceDir: packDir, zipFile: zipFile);

  debugPrint("Exported to: ${zipFile.path} t=${sw.elapsedMilliseconds}ms");
  SharePlus.instance.share(ShareParams(files: [XFile(zipFile.path)]));
}

Future<void> importPack(File f) async {
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory(mediaCacheDir);
  Directory unzipDir = Directory(
      "${importDir.path}/pack_${DateTime.timestamp().millisecondsSinceEpoch}");
  await unzipDir.create(recursive: true);
  await ZipFile.extractToDirectory(zipFile: f, destinationDir: unzipDir);
  debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");

  List<StickerPack> packsToAdd = [];

  switch (f.path.split(".").last.toLowerCase()) {
    case "wastickers":
      final dirContents = unzipDir.listSync();
      final pack = StickerPack(
          (await File("${unzipDir.path}/title.txt").readAsString())
              .replaceAll("\n", ""),
          (await File("${unzipDir.path}/author.txt").readAsString())
              .replaceAll("\n", ""),
          "pack_${DateTime.timestamp().millisecondsSinceEpoch}",
          dirContents
              .map((entry) => entry.path)
              .where((path) => path.toLowerCase().endsWith(".webp"))
              .map((path) => Sticker(path, ["❤"]))
              .toList(),
          "1000",
          false,
          trayIcon: dirContents
              .where((entry) => entry.path.toLowerCase().endsWith(".png"))
              .firstOrNull
              ?.path);
      packsToAdd.add(pack);
      break;
    case "stickify":
      final dirs = unzipDir.listSync().whereType<Directory>();
      for (final dir in dirs) {
        final jsonFile = File("${dir.path}/contents.json");
        if (!await jsonFile.exists()) continue;
        final json = jsonDecode(await jsonFile.readAsString());
        for (final packJson in json["sticker_packs"]) {
          final pack = StickerPack(
            packJson["name"],
            packJson["publisher"],
            packJson["identifier"],
            (packJson["stickers"] as List)
                .map((sticker) => Sticker(
                      "${dir.path}/${sticker["image_file"]}",
                      (sticker["emojis"] as List).isEmpty
                          ? ["❤"]
                          : sticker["emojis"],
                    ))
                .toList(),
            packJson["image_data_version"],
            packJson["animated_sticker_pack"],
            publisherWebsite: packJson["publisher_website"],
            licenseAgreementWebsite: packJson["license_agreement_website"],
            privacyPolicyWebsite: packJson["privacy_policy_website"],
          );
          packsToAdd.add(pack);
        }
      }
      break;
    default:
      File jsonFile = File("${unzipDir.path}/pack.json");
      if (await jsonFile.exists()) {
        final pack =
            StickerPack.fromJson(jsonDecode(await jsonFile.readAsString()));
        for (var sticker in pack.stickers) {
          sticker.source = "${unzipDir.path}/${sticker.source}";
        }
        if (pack.trayIcon != null) {
          pack.trayIcon = "${unzipDir.path}/${pack.trayIcon}";
        }
        packsToAdd.add(pack);
      }
  }
  debugPrint("Parse t=${sw.elapsedMilliseconds}ms");

  for (final pack in packsToAdd) {
    while (packs.where((p) => p.id == pack.id).isNotEmpty) {
      pack.id = "${pack.id}_";
    }
    await Directory("$packsDir/${pack.id}").create(recursive: true);

    for (var i = 0; i < pack.stickers.length; i++) {
      final dest = "$packsDir/${pack.id}/imported_$i.webp";
      await File(pack.stickers[i].source).copy(dest);
      pack.stickers[i].source = dest;
    }
    if (pack.trayIcon != null) {
      final dest = "$packsDir/${pack.id}/imported_tray.webp";
      await File("${pack.trayIcon}").copy(dest);
      pack.trayIcon = dest;
    }
    debugPrint("[${pack.id}] Copy t=${sw.elapsedMilliseconds}ms");
    packs.add(pack);
  }

  try {
    await unzipDir.delete(recursive: true);
  } on Exception catch (e) {
    debugPrint("Failed to delete unzipDir: $e");
  }
  await _deleteIfInsideAppCache(f);

  await savePacks(packs);
}

Future<List<StickerPack>> getPacks() async {
  File input = File("$packsDir/packs.json");
  if (await input.exists()) {
    try {
      final content = await input.readAsString();
      final loaded = (jsonDecode(content) as List)
          .map((json) => StickerPack.fromJson(json))
          .toList();
      await pruneMissingStickerFiles(loaded);
      return loaded;
    } catch (e) {
      debugPrint("Failed to read packs.json: $e");
    }
  }
  return List.empty(growable: true);
}

Future<Uint8List> cropSticker(Rect cropRect, Uint8List rawImageData,
    StickerPack pack, int index, double rotation) async {
  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(RotateOption(rotation.toInt()));
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  if (oldSize.height > oldSize.width) {
    newSize = Size(oldSize.width * 512 / oldSize.height, 512);
  } else {
    newSize = Size(512, oldSize.height * 512 / oldSize.width);
  }
  crop.addOption(
    ScaleOption(
      newSize.width.toInt(),
      newSize.height.toInt(),
    ),
  );
  crop.outputFormat = const OutputFormat.png();
  final intermediate = (await ImageEditor.editImage(
      image: rawImageData, imageEditorOption: crop))!;

  final option = ImageMergeOption(
    canvasSize: const Size.square(512),
    format: const OutputFormat.webp_lossy(50),
  );

  option.addImage(
    MergeImageConfig(
      image: MemoryImageSource(intermediate),
      position: ImagePosition(
        Offset((512 - newSize.width) / 2, (512 - newSize.height) / 2),
        newSize,
      ),
    ),
  );
  return (await ImageMerger.mergeToMemory(option: option))!;
}

Future<void> addToPack(StickerPack pack, int index, Uint8List data) async {
  final dir = Directory("$packsDir/${pack.id}");
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  File output;
  if (index == 30) {
    output =
        File("${dir.path}/tray_${DateTime.now().millisecondsSinceEpoch}.webp");
    await output.writeAsBytes(data, flush: true);
    pack.trayIcon = output.path;
  } else {
    output = File(
        "${dir.path}/sticker_${index}_${DateTime.now().millisecondsSinceEpoch}.webp");
    await output.writeAsBytes(data, flush: true);

    if (!await output.exists() || await output.length() == 0) {
      throw FileSystemException("Sticker file was not written", output.path);
    }

    pack.stickers.add(Sticker(output.path, ["❤"]));
  }

  await pack.onEdit();

  _cleanupMediaCache();
}

Future<void> _cleanupMediaCache() async {
  try {
    final dir = Directory(mediaCacheDir);
    if (!await dir.exists()) return;

    final now = DateTime.now();
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final stat = await entity.stat();
        if (now.difference(stat.modified) > const Duration(minutes: 10)) {
          try {
            await entity.delete();
          } on Exception catch (e) {
            debugPrint("Failed to delete cache file: $e");
          }
        }
      }
    }
  } catch (e) {
    debugPrint("Cache cleanup error: $e");
  }
}

Future<void> _deleteIfInsideAppCache(File file) async {
  final appCacheRoot = Directory(cacheDir).parent.path;
  final appCachePrefix = appCacheRoot.endsWith(Platform.pathSeparator)
      ? appCacheRoot
      : "$appCacheRoot${Platform.pathSeparator}";
  if (!file.path.startsWith(appCachePrefix)) return;

  try {
    await file.delete();
  } on Exception catch (e) {
    debugPrint("Failed to delete app cache file: $e");
  }
}

Future<File> saveTemp(Uint8List data) async {
  File output =
      File("$mediaCacheDir/${DateTime.now().millisecondsSinceEpoch}.tmp.webp");
  await output.writeAsBytes(data, flush: true);
  return output;
}

Future<void> pruneMissingStickerFiles(List<StickerPack> packs) async {
  var changed = false;
  for (final pack in packs) {
    final existingStickers = <Sticker>[];
    for (final sticker in pack.stickers) {
      if (await File(sticker.source).exists()) {
        existingStickers.add(sticker);
      } else {
        changed = true;
        debugPrint(
            "Removing missing sticker file from pack ${pack.id}: ${sticker.source}");
      }
    }
    if (existingStickers.length != pack.stickers.length) {
      pack.stickers
        ..clear()
        ..addAll(existingStickers);
    }
    if (pack.trayIcon != null && !await File(pack.trayIcon!).exists()) {
      debugPrint(
          "Removing missing tray icon from pack ${pack.id}: ${pack.trayIcon}");
      pack.trayIcon = null;
      changed = true;
    }
  }
  if (changed) {
    await savePacks(packs);
  }
}
