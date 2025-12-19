import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:image_editor/image_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/widgets/image_layer.dart';

import 'editor_data.dart';

Future<void> savePacks(List<StickerPack> packs) async {
  File output = File("$packsDir/packs.json");
  await output.writeAsString(jsonEncode(packs.map((pack) => pack.toJson()).toList()));
}

Future<void> exportPack(StickerPack pack) async {
  Stopwatch sw = Stopwatch()..start();
  Directory exportDir = Directory(exportCacheDir);
  Directory packDir = Directory("${exportDir.path}/pack_${DateTime.timestamp().millisecondsSinceEpoch}/");
  await packDir.create(recursive: true);
  File jsonFile = File("${packDir.path}/pack.json");
  Map<String, dynamic> exportData = pack.toJson();
  //TODO Don't hardcode extensions
  for (var i = 0; i < pack.stickers.length; i++) {
    await File(pack.stickers[i].source).copy("${packDir.path}$i.webp");
    exportData["stickers"][i]["source"] = "$i.webp";
  }
  if (pack.trayIcon != null) {
    await File(pack.trayIcon!).copy("${packDir.path}tray.png");
    exportData["trayIcon"] = "tray.png";
  }
  debugPrint("Copy t=${sw.elapsedMilliseconds}ms");
  await jsonFile.writeAsString(jsonEncode(exportData));
  debugPrint("Json written  t=${sw.elapsedMilliseconds}ms");

  File zipFile = File("${exportDir.path}/${pack.title.replaceAll(RegExp("[^ \\-_!&a-zA-Z0-9]"), "_")}.zip");
  await ZipFile.createFromDirectory(sourceDir: packDir, zipFile: zipFile);

  debugPrint("Exported to: ${zipFile.path} t=${sw.elapsedMilliseconds}ms");
  SharePlus.instance.share(ShareParams(files: [XFile(zipFile.path)]));
}

Future<void> importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory(mediaCacheDir);
  Directory unzipDir = Directory("${importDir.path}pack_${DateTime.timestamp().millisecondsSinceEpoch}/");
  await unzipDir.create(recursive: true);
  await ZipFile.extractToDirectory(zipFile: f, destinationDir: unzipDir);
  debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");

  List<StickerPack> packsToAdd = [];

  switch (f.path.split(".").last.toLowerCase()) {
    case "wastickers":
      final dirContents = unzipDir.listSync();
      final pack = StickerPack(
          (await File("${unzipDir.path}title.txt").readAsString()).replaceAll("\n", ""),
          (await File("${unzipDir.path}author.txt").readAsString()).replaceAll("\n", ""),
          "pack_${DateTime.timestamp().millisecondsSinceEpoch}",
          dirContents
              .map((entry) => entry.path)
              .where((path) => path.toLowerCase().endsWith(".webp"))
              .map((path) => Sticker(path, ["❤"], null))
              .toList(),
          "1000",
          false, // It's not possible to directly export animated packs from that app.
          trayIcon: dirContents.where((entry) => entry.path.toLowerCase().endsWith(".png")).firstOrNull?.path);
      packsToAdd.add(pack);
      break;
    case "stickify":
      final dirs = unzipDir.listSync().whereType<Directory>();
      for (final dir in dirs) {
        final json = jsonDecode(File("${dir.path}/contents.json").readAsStringSync());
        for (final packJson in json["sticker_packs"]) {
          final pack = StickerPack(
            packJson["name"],
            packJson["publisher"],
            packJson["identifier"],
            (packJson["stickers"] as List)
                .map((sticker) => Sticker(
                      "${dir.path}/${sticker["image_file"]}",
                      (sticker["emojis"] as List).isEmpty ? ["❤"] : sticker["emojis"],
                      null,
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
      //TODO support stickify's backup file format
      File jsonFile = File("${unzipDir.path}pack.json");
      final pack = StickerPack.fromJson(jsonDecode(await jsonFile.readAsString()));
      for (var sticker in pack.stickers) {
        sticker.source = unzipDir.path + sticker.source;
      }
      if (pack.trayIcon != null) {
        pack.trayIcon = unzipDir.path + pack.trayIcon!;
      }
      packsToAdd.add(pack);
  }
  debugPrint("Parse t=${sw.elapsedMilliseconds}ms");

  for (final pack in packsToAdd) {
    while (packs.where((p) => p.id == pack.id).isNotEmpty) {
      pack.id = "${pack.id}_";
    }
    await Directory("$packsDir/${pack.id}").create(recursive: true);

    for (var i = 0; i < pack.stickers.length; i++) {
      await File(pack.stickers[i].source).copy("$packsDir/${pack.id}/imported_$i.webp");
      pack.stickers[i].source = File("$packsDir/${pack.id}/imported_$i.webp").path;
    }
    if (pack.trayIcon != null) {
      await File("${pack.trayIcon}").copy("$packsDir/${pack.id}/imported_tray.webp");
      pack.trayIcon = File("$packsDir/${pack.id}/imported_tray.webp").path;
    }
    debugPrint("[${pack.id}] Copy t=${sw.elapsedMilliseconds}ms");
    packs.add(pack);
  }

  // Clean up - even if the same files are imported again, they are copied again so there's no point in caching them
  // There is no await here since we don't need to wait
  // until the deletion of the temporary folder is complete to move on
  unzipDir.delete(recursive: true);
  f.parent.delete(recursive: true);

  savePacks(packs);
}

Future<List<StickerPack>> getPacks() async {
  File input = File("$packsDir/packs.json");
  if (await input.exists()) {
    return (jsonDecode(await input.readAsString()) as List).map((json) => StickerPack.fromJson(json)).toList();
  }
  return List.empty(growable: true);
}

Future<Uint8List> cropSticker(
    Rect cropRect, Uint8List rawImageData, StickerPack pack, int index, double rotation) async {
  // Apply crop then scale then put on 512x512 transparent image in center

  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(RotateOption(rotation.toInt()));
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  // Make the longest border exactly 512 pixels wide, preserving aspect ratio
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
  crop.outputFormat = const OutputFormat.png(); // Ensure the format supports transparency
  final intermediate = (await ImageEditor.editImage(image: rawImageData, imageEditorOption: crop))!;

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

/// Adds a sticker to a sticker pack
/// Copies the file to the required place
///
/// If [index] is 30 it changes the tray icon.
Future<void> addToPack(StickerPack pack, int index, Uint8List data, [EditorData? editorData]) async {
  Directory("$packsDir/${pack.id}").createSync(recursive: true);
  File stickerFile;
  File? editorDataFile;

  if (editorData != null) {
    await Directory("$packsDir/${pack.id}/$index/").create(recursive: true);
    await File(editorData.background).rename("$packsDir/${pack.id}/$index/background.webp");
    editorData.background = "$packsDir/${pack.id}/$index/background.webp";

    for (int i = 0; i < editorData.layers.length; i++) {
      if (editorData.layers[i] is ImageLayer) {
        final ImageLayer layer = editorData.layers[i] as ImageLayer;
        await File(layer.source).rename("$packsDir/${pack.id}/$index/$i.webp");
        layer.source = "$packsDir/${pack.id}/$index/$i.webp";
      }
    }

    editorDataFile = File("$packsDir/${pack.id}/$index.json");
    await editorDataFile.writeAsString(jsonEncode(editorData.toJson()));
  }

  if (index == 30) {
    stickerFile = File("$packsDir/${pack.id}/tray.webp");
    await stickerFile.writeAsBytes(data);
    pack.trayIcon = stickerFile.path;
  } else {
    stickerFile = File("$packsDir/${pack.id}/$index.webp");
    await stickerFile.writeAsBytes(data);
    pack.stickers.add(Sticker(stickerFile.path, ["❤"], editorDataFile?.path));
  }

  pack.onEdit();
  await FileImage(stickerFile).evict();
  await savePacks(packs);
  // Clear media cache after adding a sticker
  print("Clearing media cache");
  Directory(mediaCacheDir).list().listen((entry) => entry.delete());
}

Future<File> saveTemp(Uint8List data) async {
  File output = File("$mediaCacheDir/${DateTime.now().millisecondsSinceEpoch}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
