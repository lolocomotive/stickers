import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

void savePacks(List<StickerPack> packs) async {
  File output = File("$packsDir/packs.json");
  output.writeAsString(jsonEncode(packs.map((pack) => pack.toJson()).toList()));
}

Future<void> exportPack(StickerPack pack) async {
  Stopwatch sw = Stopwatch()..start();
  Directory exportDir = Directory("${(await getTemporaryDirectory()).path}/export/");
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

  File zipFile = File("${exportDir.path}${pack.title.replaceAll(RegExp("[^ \\-_!&a-zA-Z0-9]"), "_")}.zip");
  await ZipFile.createFromDirectory(sourceDir: packDir, zipFile: zipFile);

  debugPrint("Exported to: ${zipFile.path} t=${sw.elapsedMilliseconds}ms");
  SharePlus.instance.share(ShareParams(files: [XFile(zipFile.path)]));
}

Future<void> importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory("${(await getTemporaryDirectory()).path}/import/");
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
              .map((path) => Sticker(path, ["❤"]))
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

Future<Uint8List> cropSticker(Rect cropRect, Uint8List rawImageData, StickerPack pack, int index, double rotation) async {
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
void addToPack(StickerPack pack, int index, Uint8List data) {
  Directory("$packsDir/${pack.id}").createSync(recursive: true);
  File output;
  if (index == 30) {
    output = File("$packsDir/${pack.id}/tray_${DateTime.now().millisecondsSinceEpoch}.webp");
    output.writeAsBytesSync(data);
    pack.trayIcon = output.path;
  } else {
    output = File("$packsDir/${pack.id}/sticker_${index}_${DateTime.now().millisecondsSinceEpoch}.webp");
    output.writeAsBytesSync(data);
    pack.stickers.add(Sticker(output.path, ["❤"]));
  }
  pack.onEdit();
  savePacks(packs);
}

Future<File> saveTemp(Uint8List data) async {
  String path = "${(await getTemporaryDirectory()).path}/sticker_tmp";
  await Directory(path).create(recursive: true);
  File output = File("$path/${DateTime.now().millisecondsSinceEpoch}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
