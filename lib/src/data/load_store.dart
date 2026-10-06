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
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/image_layer.dart';

import 'editor_data.dart';

Future<void> savePacks(List<StickerPack> packs) async {
  File output = File("$packsDir/packs.json");
  await output.writeAsString(jsonEncode(packs.map((pack) => pack.toJson()).toList()));
}

Future<File> createPackZip(StickerPack pack, Directory exportDir, {bool includeEditData = true}) async {
  Directory packDir = Directory("${exportDir.path}/${uid()}/");
  await packDir.create(recursive: true);
  File jsonFile = File("${packDir.path}/pack.json");
  Map<String, dynamic> exportData = pack.toJson();
  //TODO Don't hardcode extensions
  for (var i = 0; i < pack.stickers.length; i++) {
    final stickerFile = File(pack.stickers[i].source);
    if (await stickerFile.exists()) {
      await stickerFile.copy("${packDir.path}$i.webp");
    } else if (pack.stickers[i].editorData != null) {
      final fallback = File("${pack.stickers[i].editorData!.replaceAll(RegExp(r"\.json$"), "")}/background.webp");
      if (await fallback.exists()) {
        await fallback.copy("${packDir.path}$i.webp");
      }
    }
    exportData["stickers"][i]["source"] = "$i.webp";
    if (includeEditData && exportData["stickers"][i]["editorData"] != null) {
      final edFile = File(pack.stickers[i].editorData!);
      if (await edFile.exists()) {
        exportData["stickers"][i]["editorData"] = "$i.json";
        final data = jsonDecode(await edFile.readAsString());
        data["background"] = "$i/background.webp";
        await File("${packDir.path}$i.json").writeAsString(jsonEncode(data));
        final edDir = Directory(pack.stickers[i].editorData!.replaceAll(RegExp(r"\.json$"), ""));
        if (await edDir.exists()) {
          await edDir.copy("${packDir.path}$i");
        }
      } else {
        exportData["stickers"][i]["editorData"] = null;
      }
    } else {
      exportData["stickers"][i]["editorData"] = null;
    }
  }
  if (pack.trayIcon != null) {
    final trayFile = File(pack.trayIcon!);
    if (await trayFile.exists()) {
      await trayFile.copy("${packDir.path}tray.png");
      exportData["trayIcon"] = "tray.png";
    }
  }
  await jsonFile.writeAsString(jsonEncode(exportData));

  final sanitizedTitle = pack.title.replaceAll(RegExp(r"[^ \-_!&a-zA-Z0-9]"), "_");
  File zipFile = File("${exportDir.path}/$sanitizedTitle.zip");
  if (await zipFile.exists()) {
    zipFile = File("${exportDir.path}/${sanitizedTitle}_${uid().substring(0, 4)}.zip");
  }
  await ZipFile.createFromDirectory(sourceDir: packDir, zipFile: zipFile);
  await packDir.delete(recursive: true);
  return zipFile;
}

Future<bool> exportPack(StickerPack pack, {bool includeEditData = true}) async {
  return await exportPacks([pack], includeEditData: includeEditData);
}

Future<bool> exportPacks(List<StickerPack> packsToExport, {bool includeEditData = true}) async {
  if (packsToExport.isEmpty) return false;
  Stopwatch sw = Stopwatch()..start();
  Directory exportDir = Directory(exportCacheDir);
  await exportDir.create(recursive: true);

  List<XFile> files = [];
  for (final pack in packsToExport) {
    File zip = await createPackZip(pack, exportDir, includeEditData: includeEditData);
    files.add(XFile(zip.path));
  }

  debugPrint("Exported ${files.length} packs t=${sw.elapsedMilliseconds}ms");
  await SharePlus.instance.share(ShareParams(files: files));
  return true;
}

Future<void> deleteStickerFiles(Sticker sticker) async {
  try {
    final file = File(sticker.source);
    if (await file.exists()) {
      await file.delete();
    }
    if (sticker.editorData != null) {
      final editorFile = File(sticker.editorData!);
      if (await editorFile.exists()) {
        await editorFile.delete();
      }
      final editorDir = Directory(sticker.editorData!.replaceAll(RegExp(r"\.json$"), ""));
      if (await editorDir.exists()) {
        await editorDir.delete(recursive: true);
      }
    }
  } catch (e) {
    debugPrint("Failed to delete sticker files: $e");
  }
}

Future<void> deletePackDirectory(StickerPack pack) async {
  try {
    final dir = Directory("$packsDir/${pack.id}");
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (e) {
    debugPrint("Failed to delete pack directory: $e");
  }
}

Future<void> importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory importDir = Directory(mediaCacheDir);
  Directory unzipDir = Directory("${importDir.path}/${uid()}/");
  await unzipDir.create(recursive: true);
  await ZipFile.extractToDirectory(zipFile: f, destinationDir: unzipDir);
  debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");
  final unzipPath = unzipDir.path.endsWith("/") || unzipDir.path.endsWith(r"\")
      ? unzipDir.path
      : "${unzipDir.path}/";

  List<StickerPack> packsToAdd = [];

  switch (f.path.split(".").last.toLowerCase()) {
    case "wastickers":
      final dirContents = unzipDir.listSync();
      final pack = StickerPack(
        (await File("${unzipPath}title.txt").readAsString()).replaceAll("\n", ""),
        (await File("${unzipPath}author.txt").readAsString()).replaceAll("\n", ""),
        uid(),
        dirContents
            .map((entry) => entry.path)
            .where((path) => path.toLowerCase().endsWith(".webp"))
            .map((path) => Sticker(path, ["❤"], null))
            .toList(),
        "1000",
        false, // It's not possible to directly export animated packs from that app.
        trayIcon: dirContents.where((entry) => entry.path.toLowerCase().endsWith(".png")).firstOrNull?.path,
      );
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
                .map(
                  (sticker) => Sticker(
                    "${dir.path}/${sticker["image_file"]}",
                    (sticker["emojis"] as List).isEmpty
                        ? ["❤"]
                        : (sticker["emojis"] as List).map((e) => e.toString()).toList(),
                    null,
                  ),
                )
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
      File jsonFile = File("${unzipPath}pack.json");
      final pack = StickerPack.fromJson(jsonDecode(await jsonFile.readAsString()));
      for (var sticker in pack.stickers) {
        sticker.source = unzipPath + sticker.source;
        if (sticker.editorData != null) {
          sticker.editorData = unzipPath + sticker.editorData!;
        }
      }
      if (pack.trayIcon != null) {
        pack.trayIcon = unzipPath + pack.trayIcon!;
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
      await File(pack.stickers[i].source).copy("$packsDir/${pack.id}/$i.webp");
      pack.stickers[i].source = File("$packsDir/${pack.id}/$i.webp").path;
      if (pack.stickers[i].editorData != null) {
        final edFile = File(pack.stickers[i].editorData!);
        if (await edFile.exists()) {
          final targetJson = "$packsDir/${pack.id}/$i.json";
          try {
            final data = jsonDecode(await edFile.readAsString());
            if (data is Map<String, dynamic> && data["background"] is String) {
              final bgRel = data["background"] as String;
              data["background"] = "$packsDir/${pack.id}/$bgRel";
              if (data["layers"] is List) {
                for (var layer in data["layers"]) {
                  if (layer is Map && layer["source"] is String) {
                    final src = layer["source"] as String;
                    if (!src.startsWith("/") && !src.contains(r":\")) {
                      layer["source"] = "$packsDir/${pack.id}/$src";
                    }
                  }
                }
              }
              await File(targetJson).writeAsString(jsonEncode(data));
            } else {
              await edFile.copy(targetJson);
            }
          } catch (_) {
            await edFile.copy(targetJson);
          }
          pack.stickers[i].editorData = targetJson;
          final edDir = Directory(edFile.path.replaceAll(RegExp(r"\.json$"), ""));
          if (await edDir.exists()) {
            await edDir.copy("$packsDir/${pack.id}/$i");
          }
        } else {
          pack.stickers[i].editorData = null;
        }
      }
    }
    if (pack.trayIcon != null) {
      await File("${pack.trayIcon}").copy("$packsDir/${pack.id}/tray.webp");
      pack.trayIcon = File("$packsDir/${pack.id}/tray.webp").path;
    }
    debugPrint("[${pack.id}] Copy t=${sw.elapsedMilliseconds}ms");
    packs.add(pack);
  }

  // Clean up unzipped temporary folder
  try {
    await unzipDir.delete(recursive: true);
  } catch (e) {
    debugPrint("Failed to delete unzipDir: $e");
  }

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
  Rect cropRect,
  Uint8List rawImageData,
  StickerPack pack,
  int index,
  double rotation, [
  bool stretch = false,
]) async {
  // Apply crop then scale then put on 512x512 transparent image in center

  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(RotateOption(rotation.toInt()));
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  // Make the longest border exactly 512 pixels wide, preserving aspect ratio if we're not stretching
  if (!stretch) {
    if (oldSize.height > oldSize.width) {
      newSize = Size(oldSize.width * 512 / oldSize.height, 512);
    } else {
      newSize = Size(512, oldSize.height * 512 / oldSize.width);
    }
  } else {
    newSize = Size(512, 512);
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
Future<void> addToPack(
  StickerPack pack,
  int index,
  Uint8List data, [
  EditorData? editorData,
  bool replace = false,
]) async {
  Directory("$packsDir/${pack.id}").createSync(recursive: true);
  File stickerFile;
  File? editorDataFile;

  if (index == 30) {
    stickerFile = File("$packsDir/${pack.id}/tray.webp");
    await stickerFile.writeAsBytes(data);
    pack.trayIcon = stickerFile.path;
  } else {
    // This is enough to avoid filename collisions
    final String filename = "${index}_${uid()}";

    if (editorData != null) {
      await Directory("$packsDir/${pack.id}/$filename/").create(recursive: true);
      final backgroundPath = "$packsDir/${pack.id}/$filename/background.${editorData.background.split(".").last}";
      final bgFile = File(editorData.background);
      if (await bgFile.exists()) {
        await bgFile.copy(backgroundPath);
        if (editorData.background.contains(mediaCacheDir)) {
          try {
            await bgFile.delete();
          } catch (_) {}
        }
      }
      editorData.background = backgroundPath;

      for (int i = 0; i < editorData.layers.length; i++) {
        if (editorData.layers[i] is ImageLayer) {
          final ImageLayer layer = editorData.layers[i] as ImageLayer;
          final layerFile = File(layer.source);
          if (await layerFile.exists()) {
            await layerFile.copy("$packsDir/${pack.id}/$filename/$i.webp");
            if (layer.source.contains(mediaCacheDir)) {
              try {
                await layerFile.delete();
              } catch (_) {}
            }
          }
          layer.source = "$packsDir/${pack.id}/$filename/$i.webp";
        }
      }

      editorDataFile = File("$packsDir/${pack.id}/$filename.json");
      await editorDataFile.writeAsString(jsonEncode(editorData.toJson()));
    }
    stickerFile = File("$packsDir/${pack.id}/$filename.webp");
    await stickerFile.writeAsBytes(data);
    if (replace) {
      await deleteStickerFiles(pack.stickers[index]);
      pack.stickers[index].source = stickerFile.path;
      pack.stickers[index].editorData = editorDataFile?.path;
    } else {
      pack.stickers.add(Sticker(stickerFile.path, ["❤"], editorDataFile?.path));
    }
  }

  pack.onEdit();
  await FileImage(stickerFile).evict();
  await savePacks(packs);
  // Clear media cache after adding a sticker
  print("Clearing media cache");
  Directory(mediaCacheDir).list().listen((entry) => entry.delete());
}

Future<File> saveTemp(Uint8List data) async {
  File output = File("$mediaCacheDir/${uid()}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
