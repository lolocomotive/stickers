import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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

exportPack(StickerPack pack) async {
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

importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory("${(await getTemporaryDirectory()).path}/import/");
  Directory packDir = Directory("${importDir.path}pack_${DateTime.timestamp().millisecondsSinceEpoch}/");
  await packDir.create(recursive: true);
  await ZipFile.extractToDirectory(zipFile: f, destinationDir: packDir);
  debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");

  File jsonFile = File("${packDir.path}pack.json");
  StickerPack pack = StickerPack.fromJson(jsonDecode(await jsonFile.readAsString()));

  for (var i = 0; packs.where((p) => p.id == pack.id).isNotEmpty; i++) {
    pack.id = "${pack.id}_$i";
  }

  debugPrint("Parse t=${sw.elapsedMilliseconds}ms");
  await Directory("$packsDir/${pack.id}").create(recursive: true);

  for (var i = 0; i < pack.stickers.length; i++) {
    await File("${packDir.path}${pack.stickers[i].source}").copy("$packsDir/${pack.id}/imported_$i.webp");
    pack.stickers[i].source = File("$packsDir/${pack.id}/imported_$i.webp").path;
  }
  if (pack.trayIcon != null) {
    await File("${packDir.path}${pack.trayIcon}").copy("$packsDir/${pack.id}/imported_tray.webp");
    pack.trayIcon = File("$packsDir/${pack.id}/imported_tray.webp").path;
  }
  debugPrint("Copy t=${sw.elapsedMilliseconds}ms");

  packs.add(pack);
  savePacks(packs);
}

Future<List<StickerPack>> getPacks() async {
  File input = File("$packsDir/packs.json");
  if (await input.exists()) {
    return (jsonDecode(await input.readAsString()) as List).map((json) => StickerPack.fromJson(json)).toList();
  }
  return List.empty(growable: true);
}

Future<Uint8List> cropSticker(Rect cropRect, Uint8List rawImageData, StickerPack pack, int index) async {
  // Apply crop then scale then put on 512x512 transparent image in center

  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  //Make the longest border exactly 512 pixels wide, preseving aspect ratio
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
