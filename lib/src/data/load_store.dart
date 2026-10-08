import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:image_editor/image_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_encoding.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/data/storage.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/util.dart';
import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

import 'editor_data.dart';

export 'sticker_encoding.dart' show StickerFormat;

Future<void> _pendingSave = Future.value();

/// Saves [packs] to packs.json.
///
/// The packs are serialized right away, and the saves are written one after
/// the other, each replacing the file at once, so concurrent saves can't
/// corrupt it and the last call always wins.
Future<void> savePacks(List<StickerPack> packs) {
  final json = jsonEncode(packs.map((pack) => pack.toJson()).toList());
  final save = _pendingSave.then((_) => writeAtomically(File("$packsDir/packs.json"), json));
  _pendingSave = save.catchError((Object e) => debugPrint("Couldn't save packs: $e"));
  return save;
}

/// Directory next to an editor data file holding its background.
String _editorAssetsPath(String editorDataPath) => editorDataPath.replaceAll(RegExp(r"\.json$"), "");

/// Finds a file referenced by editor data.
///
/// Relative paths are resolved against [root]. Absolute paths, stored by older
/// versions, are only followed when [absoluteAllowed] (data from this device).
/// Then the file is looked up by name in [assetsDir]. When nothing matches, a
/// file in [assetsDir] whose name starts with [fallbackPrefix] is used, which
/// recovers backgrounds saved by older exports under the wrong extension.
Future<File?> _findEditorFile(
  Object? stored, {
  required Directory assetsDir,
  required String root,
  bool absoluteAllowed = false,
  String? fallbackPrefix,
}) async {
  if (stored is String && stored.isNotEmpty) {
    final isAbsolute = isAbsolutePath(stored);
    final candidates = [
      if (isAbsolute && absoluteAllowed) File(resolvePath(stored, root)),
      if (!isAbsolute) File("$root/$stored"),
      File("${assetsDir.path}/${baseName(stored)}"),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) return candidate;
    }
  }
  if (fallbackPrefix != null && await assetsDir.exists()) {
    await for (final entry in assetsDir.list()) {
      if (entry is File && baseName(entry.path).startsWith(fallbackPrefix)) return entry;
    }
  }
  return null;
}

/// Copies the editor data of a sticker into [targetBase].json and its
/// background into the [targetBase] directory, storing the background path
/// returned by [pathFor].
///
/// Paths in the data are resolved against [root].
///
/// Returns the rewritten data, or null when the data or its background can't
/// be found or parsed. The sticker is then kept without editor data, and can
/// still be edited using its image as background.
Future<Map<String, dynamic>?> _copyEditorData(
  String editorDataPath,
  String targetBase, {
  required String Function(String fileName) pathFor,
  required String root,
  bool absoluteAllowed = false,
}) async {
  final targetDir = Directory(targetBase);
  try {
    final data = jsonDecode(await File(editorDataPath).readAsString());
    if (data is! Map<String, dynamic> || data["layers"] is! List) return null;
    // Validates the layers, which would otherwise only fail when opening the editor.
    EditorData.fromJson(data, GlobalKey());

    final background = await _findEditorFile(
      data["background"],
      assetsDir: Directory(_editorAssetsPath(editorDataPath)),
      root: root,
      absoluteAllowed: absoluteAllowed,
      fallbackPrefix: "background.",
    );
    if (background == null) {
      debugPrint("Background of $editorDataPath not found, dropping editor data");
      return null;
    }

    await targetDir.create(recursive: true);
    final backgroundName = "background.${extensionOf(background.path)}";
    await background.copy("${targetDir.path}/$backgroundName");
    data["background"] = pathFor(backgroundName);

    await File("$targetBase.json").writeAsString(jsonEncode(data));
    return data;
  } catch (e) {
    debugPrint("Couldn't copy editor data $editorDataPath: $e");
    try {
      if (await targetDir.exists()) await targetDir.delete(recursive: true);
    } catch (_) {}
    return null;
  }
}

/// Font families used by the text layers of editor data.
Iterable<String> _fontsUsed(Map<String, dynamic> editorData) => (editorData["layers"] as List)
    .whereType<Map>()
    .where((layer) => layer["type"] == "text" && layer["fontName"] is String)
    .map((layer) => layer["fontName"] as String);

/// Zips [pack] into [exportDir], which must not hold another zip of the same pack.
Future<File> createPackZip(StickerPack pack, Directory exportDir, {bool includeEditData = true}) async {
  Directory packDir = Directory("${exportDir.path}/${uid()}/");
  await packDir.create(recursive: true);
  try {
    Map<String, dynamic> exportData = pack.toJson();
    final exportedStickers = <Map<String, dynamic>>[];
    final fonts = <String>{};
    for (final sticker in pack.stickers) {
      final stickerFile = File(sticker.source);
      if (!await stickerFile.exists()) {
        debugPrint("Skipping missing sticker ${sticker.source}");
        continue;
      }
      final i = exportedStickers.length;
      await stickerFile.copy("${packDir.path}$i.webp");
      final stickerJson = sticker.toJson()
        ..["source"] = "$i.webp"
        ..["editorData"] = null;
      if (includeEditData && sticker.editorData != null) {
        final data = await _copyEditorData(
          sticker.editorData!,
          "${packDir.path}$i",
          pathFor: (name) => "$i/$name",
          root: packsDir,
          absoluteAllowed: true,
        );
        if (data != null) {
          stickerJson["editorData"] = "$i.json";
          fonts.addAll(_fontsUsed(data));
        }
      }
      exportedStickers.add(stickerJson);
    }
    exportData["stickers"] = exportedStickers;
    exportData["fonts"] = await _exportFonts(fonts, packDir);

    exportData["trayIcon"] = null;
    if (pack.trayIcon != null) {
      final trayFile = File(pack.trayIcon!);
      if (await trayFile.exists()) {
        final trayName = "tray.${extensionOf(trayFile.path)}";
        await trayFile.copy("${packDir.path}$trayName");
        exportData["trayIcon"] = trayName;
      }
    }
    await File("${packDir.path}pack.json").writeAsString(jsonEncode(exportData));

    final sanitizedTitle = pack.title.replaceAll(RegExp(r"[^ \-_!&a-zA-Z0-9]"), "_");
    final zipFile = File("${exportDir.path}/$sanitizedTitle.zip");
    await ZipFile.createFromDirectory(sourceDir: packDir, zipFile: zipFile);
    return zipFile;
  } finally {
    await packDir.delete(recursive: true);
  }
}

/// Copies the downloaded and custom fonts among [families] into the archive,
/// so text layers keep their font on devices that don't have it. Bundled fonts
/// ship with the app and are skipped.
Future<List<Map<String, dynamic>>> _exportFonts(Set<String> families, Directory packDir) async {
  final exported = <Map<String, dynamic>>[];
  for (final family in families) {
    try {
      final entry = FontsRegistry.get(family);
      if (entry == null || entry.type == FontType.bundled || entry.fontFile == null) continue;
      final fontFile = File(entry.fontFile!);
      if (!await fontFile.exists()) continue;
      final name = "fonts/${exported.length}.${extensionOf(fontFile.path)}";
      await Directory("${packDir.path}fonts").create();
      await fontFile.copy("${packDir.path}$name");
      exported.add({
        "family": family,
        "file": name,
        "type": entry.type.name,
        "sizeMultiplier": entry.sizeMultiplier,
        "display": entry.display,
      });
    } catch (e) {
      debugPrint("Couldn't export font $family: $e");
    }
  }
  return exported;
}

Future<bool> exportPack(StickerPack pack, {bool includeEditData = true}) async {
  return await exportPacks([pack], includeEditData: includeEditData);
}

Future<bool> exportPacks(List<StickerPack> packsToExport, {bool includeEditData = true}) async {
  if (packsToExport.isEmpty) return false;
  Stopwatch sw = Stopwatch()..start();
  return await withExportDirectory((exportDir) async {
    File shared;
    if (packsToExport.length == 1) {
      shared = await createPackZip(packsToExport.first, exportDir, includeEditData: includeEditData);
    } else {
      // The pack zips go into one zip, which importPack unpacks.
      final bundleDir = Directory("${exportDir.path}/bundle");
      await bundleDir.create();
      for (final (i, pack) in packsToExport.indexed) {
        // Packs with the same title would get the same zip name.
        final packDir = Directory("${exportDir.path}/$i");
        await packDir.create();
        final zip = await createPackZip(pack, packDir, includeEditData: includeEditData);
        await zip.rename("${bundleDir.path}/${baseName(zip.path)}".replaceFirst(RegExp(r"\.zip$"), "_$i.zip"));
      }
      shared = File("${exportDir.path}/stickers.zip");
      await ZipFile.createFromDirectory(sourceDir: bundleDir, zipFile: shared);
    }

    debugPrint("Exported ${packsToExport.length} packs t=${sw.elapsedMilliseconds}ms");
    await SharePlus.instance.share(ShareParams(files: [XFile(shared.path)]));
    return true;
  });
}

/// Runs [export] with a new directory in the export cache, deleted afterwards.
///
/// The share sheet copies the files it shares, so they can be deleted once
/// it returns.
Future<T> withExportDirectory<T>(Future<T> Function(Directory exportDir) export) async {
  final exportDir = Directory("$exportCacheDir/${uid()}");
  await exportDir.create(recursive: true);
  try {
    return await export(exportDir);
  } finally {
    try {
      await exportDir.delete(recursive: true);
    } catch (e) {
      debugPrint("Couldn't delete ${exportDir.path}: $e");
    }
  }
}

/// Converts [stickers] to [format] into [exportDir] and returns the files,
/// skipping stickers whose file is missing.
///
/// [onProgress] receives the overall progress (0 to 1) and the 1-based index
/// of the sticker being converted.
Future<List<XFile>> convertStickers(
  List<Sticker> stickers,
  Directory exportDir, {
  required StickerFormat format,
  String? packTitle,
  void Function(double progress, int current)? onProgress,
}) async {
  final List<XFile> files = [];
  final cleanTitle = (packTitle != null && packTitle.isNotEmpty)
      ? packTitle.replaceAll(RegExp(r"[^ \-_!&a-zA-Z0-9]"), "_")
      : "sticker";

  for (int i = 0; i < stickers.length; i++) {
    final sticker = stickers[i];
    onProgress?.call(i / stickers.length, i + 1);
    if (!await File(sticker.source).exists()) continue;

    final convertedBytes = await convertSticker(
      sticker.source,
      format,
      onProgress: (progress) => onProgress?.call((i + progress) / stickers.length, i + 1),
    );

    final fileName = stickers.length == 1
        ? "${cleanTitle}_sticker.${format.extension}"
        : "${cleanTitle}_sticker_${i + 1}.${format.extension}";

    final targetFile = File("${exportDir.path}/$fileName");
    await targetFile.writeAsBytes(convertedBytes);
    files.add(XFile(targetFile.path));
  }
  return files;
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
      final editorDir = Directory(_editorAssetsPath(sticker.editorData!));
      if (await editorDir.exists()) {
        await editorDir.delete(recursive: true);
      }
    }
  } catch (e) {
    debugPrint("Failed to delete sticker files: $e");
  }
}

/// Prefix of pack directories being deleted, which [cleanUpPacks] finishes
/// deleting if the app stopped first.
const _trashPrefix = ".trash_";

/// Removes [pack] from [packs] and WhatsApp, saves the packs, then deletes its files.
Future<void> deletePack(StickerPack pack) async {
  packs.remove(pack);
  await savePacks(packs);
  try {
    final dir = Directory(pack.directory);
    if (await dir.exists()) {
      // Renamed first, so a new pack can't get files of this one if deleting fails.
      final trash = await dir.rename("$packsDir/$_trashPrefix${uid()}");
      await trash.delete(recursive: true);
    }
  } catch (e) {
    debugPrint("Failed to delete pack directory: $e");
  }
  try {
    await WhatsappStickers.removeStickerPack(pack.id);
  } catch (e) {
    debugPrint("Couldn't remove ${pack.id} from WhatsApp: $e");
  }
}

/// Makes [id] unique among the packs and the pack directories.
String _uniquePackId(String id) {
  while (packs.any((p) => p.id == id) || Directory("$packsDir/$id").existsSync()) {
    id = "${id}_";
  }
  return id;
}

Future<void> importPack(File f) async {
  //TODO show progress
  Stopwatch sw = Stopwatch()..start();
  Directory unzipDir = Directory("$mediaCacheDir/import_${uid()}/");
  await unzipDir.create(recursive: true);
  try {
    await ZipFile.extractToDirectory(zipFile: f, destinationDir: unzipDir);
    debugPrint("Unzip t=${sw.elapsedMilliseconds}ms");

    List<StickerPack> packsToAdd = [];
    // Directory that relative editor data paths start from.
    final root = unzipDir.path.replaceAll(RegExp(r"/$"), "");

    // A zip of pack zips, made by exporting several packs at once.
    if (!await File("$root/pack.json").exists()) {
      final nested = unzipDir.listSync().whereType<File>().where((e) => e.path.toLowerCase().endsWith(".zip")).toList();
      if (nested.isNotEmpty) {
        for (final zip in nested) {
          await importPack(zip);
        }
        return;
      }
    }

    switch (f.path.split(".").last.toLowerCase()) {
      case "wastickers":
        final dirContents = unzipDir.listSync();
        final pack = StickerPack(
          (await File("${unzipDir.path}title.txt").readAsString()).replaceAll("\n", ""),
          (await File("${unzipDir.path}author.txt").readAsString()).replaceAll("\n", ""),
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
              "${packJson["image_data_version"]}",
              packJson["animated_sticker_pack"] ?? false,
              publisherWebsite: packJson["publisher_website"],
              licenseAgreementWebsite: packJson["license_agreement_website"],
              privacyPolicyWebsite: packJson["privacy_policy_website"],
              trayIcon: packJson["tray_image_file"] is String ? "${dir.path}/${packJson["tray_image_file"]}" : null,
            );
            packsToAdd.add(pack);
          }
        }
        break;
      default:
        //TODO support stickify's backup file format
        final json = jsonDecode(await File("$root/pack.json").readAsString());
        await _importFonts(json["fonts"], root);
        packsToAdd.add(StickerPack.fromJson(json, root: root));
    }
    debugPrint("Parse t=${sw.elapsedMilliseconds}ms");

    var added = false;
    try {
      for (final pack in packsToAdd) {
        await _addImportedPack(pack, root: root);
        added = true;
        debugPrint("[${pack.id}] Copy t=${sw.elapsedMilliseconds}ms");
      }
    } finally {
      // Keeps the packs added before a failure.
      if (added) await savePacks(packs);
    }
  } finally {
    // Clean up unzipped temporary folder
    try {
      await unzipDir.delete(recursive: true);
    } catch (e) {
      debugPrint("Failed to delete unzipDir: $e");
    }
  }
}

/// Copies the files of an extracted [pack] into its own directory and adds it
/// to [packs]. Nothing is kept if this fails.
///
/// Stickers whose image is missing are skipped. Editor data that can't be
/// restored is dropped, and the sticker stays editable from its image.
Future<void> _addImportedPack(StickerPack pack, {required String root}) async {
  pack.id = _uniquePackId(pack.id);
  // StickerPack.onEdit increments the version, so it must be an integer.
  if (int.tryParse(pack.imageDataVersion) == null) pack.imageDataVersion = "1";
  final packDir = Directory(pack.directory);
  await packDir.create(recursive: true);
  try {
    final imported = <Sticker>[];
    for (final sticker in pack.stickers) {
      final source = File(sticker.source);
      if (!await source.exists()) {
        debugPrint("Skipping missing sticker ${sticker.source}");
        continue;
      }
      // Same naming as addToPack, so later stickers never collide.
      final name = "${imported.length}_${uid()}";
      final target = await source.copy("${packDir.path}/$name.webp");
      String? editorData;
      if (sticker.editorData != null) {
        final data = await _copyEditorData(
          sticker.editorData!,
          "${packDir.path}/$name",
          pathFor: (file) => "${pack.id}/$name/$file",
          root: root,
        );
        if (data != null) editorData = "${packDir.path}/$name.json";
      }
      imported.add(Sticker(target.path, sticker.emojis.isEmpty ? ["❤"] : sticker.emojis, editorData));
    }
    if (imported.isEmpty) throw Exception("The pack contains no stickers");
    pack.stickers = imported;

    final tray = pack.trayIcon == null ? null : File(pack.trayIcon!);
    pack.trayIcon = tray != null && await tray.exists()
        ? (await tray.copy("${packDir.path}/tray.${extensionOf(tray.path)}")).path
        : null;
  } catch (_) {
    await packDir.delete(recursive: true);
    rethrow;
  }
  packs.add(pack);
}

/// Installs the fonts bundled with an exported pack.
Future<void> _importFonts(Object? fonts, String root) async {
  if (fonts is! List) return;
  for (final font in fonts.whereType<Map>()) {
    final family = font["family"];
    final file = font["file"];
    if (family is! String || file is! String) continue;
    try {
      await installFont(
        File("$root/$file"),
        family,
        type: FontType.values.asNameMap()[font["type"]] ?? FontType.custom,
        sizeMultiplier: (font["sizeMultiplier"] as num?)?.toDouble() ?? 1,
        display: font["display"] as String?,
      );
    } catch (e) {
      debugPrint("Couldn't import font $family: $e");
    }
  }
}

/// Whether packs.json was written by a version storing absolute paths.
bool _hasAbsolutePaths = false;

Future<List<StickerPack>> getPacks() async {
  File input = File("$packsDir/packs.json");
  if (await input.exists()) {
    final List json = jsonDecode(await input.readAsString());
    _hasAbsolutePaths = json.any((pack) =>
        pack["trayIcon"] is String && isAbsolutePath(pack["trayIcon"]) ||
        (pack["stickers"] as List).any((sticker) => isAbsolutePath(sticker["source"])));
    return json.map((json) => StickerPack.fromJson(json)).toList();
  }
  return List.empty(growable: true);
}

/// Brings the pack files in line with [packs], after they are loaded:
/// - Stores the paths written by older versions relative to [packsDir].
/// - Finishes deleting packs, and deletes the files no pack uses.
/// - Removes deleted packs from WhatsApp.
///
/// Must run before anything adds stickers, whose files would look unused.
Future<void> cleanUpPacks() async {
  try {
    if (_hasAbsolutePaths) {
      await savePacks(packs);
      await _migrateEditorData();
      _hasAbsolutePaths = false;
    }
    await for (final entry in Directory(packsDir).list()) {
      if (entry is Directory && baseName(entry.path).startsWith(_trashPrefix)) {
        await entry.delete(recursive: true);
      }
    }
    for (final pack in packs) {
      await _deleteUnusedFiles(pack);
    }
  } catch (e) {
    debugPrint("Couldn't clean up packs: $e");
  }
  WhatsappStickers.retainStickerPacks(packs.map((pack) => pack.id)).catchError((Object e) {
    debugPrint("Couldn't remove deleted packs from WhatsApp: $e");
    return false;
  });
}

/// Rewrites the absolute background paths of editor data relative to [packsDir].
Future<void> _migrateEditorData() async {
  for (final sticker in packs.expand((pack) => pack.stickers)) {
    if (sticker.editorData == null) continue;
    try {
      final file = File(sticker.editorData!);
      if (!await file.exists()) continue;
      final data = jsonDecode(await file.readAsString());
      final background = data["background"];
      if (background is! String || !isAbsolutePath(background)) continue;
      data["background"] = relativePath(resolvePath(background, packsDir), packsDir);
      await writeAtomically(file, jsonEncode(data));
    } catch (e) {
      debugPrint("Couldn't migrate ${sticker.editorData}: $e");
    }
  }
}

String _normalize(String path) => path.replaceAll(RegExp(r"[/\\]+"), "/");

/// Deletes the files in the directory of [pack] that it doesn't use, left
/// behind by older versions or by failures.
Future<void> _deleteUnusedFiles(StickerPack pack) async {
  final dir = Directory(pack.directory);
  if (!await dir.exists()) return;
  final stickers = pack.stickers.map((sticker) => _normalize(sticker.source)).toSet();
  final used = {
    ...stickers,
    for (final sticker in pack.stickers)
      if (sticker.editorData != null) _normalize(sticker.editorData!),
    if (pack.trayIcon != null) _normalize(pack.trayIcon!),
    _normalize(pack.whatsappTrayPath),
  };
  final usedDirs = [
    for (final sticker in pack.stickers)
      if (sticker.editorData != null) "${_normalize(_editorAssetsPath(sticker.editorData!))}/",
  ];

  final dirs = <Directory>[];
  final unused = <File>[];
  final found = <String>{};
  await for (final entry in dir.list(recursive: true, followLinks: false)) {
    final path = _normalize(entry.path);
    if (entry is Directory) {
      dirs.add(entry);
    } else if (stickers.contains(path)) {
      found.add(path);
    } else if (entry is File && !used.contains(path) && !usedDirs.any(path.startsWith)) {
      unused.add(entry);
    }
  }
  // A sticker that wasn't found means the paths don't match the files, which would delete them all.
  if (found.length != stickers.length) {
    debugPrint("[${pack.id}] Sticker files not found, not cleaning up");
    return;
  }
  for (final file in unused) {
    debugPrint("[${pack.id}] Deleting unused ${file.path}");
    await file.delete();
  }
  // Deepest first, so directories holding only empty directories go too.
  dirs.sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final d in dirs) {
    if (await d.list().isEmpty) await d.delete();
  }
}

Future<Uint8List> cropSticker(
  Rect cropRect,
  Uint8List rawImageData,
  StickerPack pack,
  int index,
  double rotation, [
  bool stretch = false,
]) {
  return _cropSticker(
    cropRect,
    rotation,
    stretch,
    (option) => ImageEditor.editImage(image: rawImageData, imageEditorOption: option),
  );
}

/// Like [cropSticker], but lets the native side read the image from [path]
/// instead of copying the whole file through Dart.
Future<Uint8List> cropStickerFile(Rect cropRect, String path, double rotation, [bool stretch = false]) {
  return _cropSticker(
    cropRect,
    rotation,
    stretch,
    (option) => ImageEditor.editFileImage(file: File(path), imageEditorOption: option),
  );
}

Future<Uint8List> _cropSticker(
  Rect cropRect,
  double rotation,
  bool stretch,
  Future<Uint8List?> Function(ImageEditorOption option) edit,
) async {
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
  final intermediate = (await edit(crop))!;

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

/// Adds the sticker [data] to [pack], or replaces the sticker at index
/// [replace], and saves the packs.
///
/// The background of [editorData] is copied next to the sticker. The caller
/// keeps ownership of the original.
Future<void> addToPack(StickerPack pack, Uint8List data, {EditorData? editorData, int? replace}) async {
  final dir = pack.directory;
  await Directory(dir).create(recursive: true);
  // This is enough to avoid filename collisions
  final filename = "${replace ?? pack.stickers.length}_${uid()}";
  final stickerFile = File("$dir/$filename.webp");
  File? editorDataFile;

  try {
    if (editorData != null) {
      final bgFile = File(editorData.background);
      if (!await bgFile.exists()) {
        throw FileSystemException("Background not found", editorData.background);
      }
      await Directory("$dir/$filename").create();
      final backgroundPath = "$dir/$filename/background.${extensionOf(editorData.background)}";
      await bgFile.copy(backgroundPath);
      editorData.background = backgroundPath;

      editorDataFile = File("$dir/$filename.json");
      await editorDataFile.writeAsString(jsonEncode(editorData.toJson()), flush: true);
    }
    await stickerFile.writeAsBytes(data, flush: true);
  } catch (_) {
    await deleteStickerFiles(Sticker(stickerFile.path, [], editorDataFile?.path ?? "$dir/$filename.json"));
    rethrow;
  }

  Sticker? replaced;
  if (replace != null) {
    final sticker = pack.stickers[replace];
    replaced = Sticker(sticker.source, sticker.emojis, sticker.editorData);
    sticker.source = stickerFile.path;
    sticker.editorData = editorDataFile?.path;
  } else {
    pack.stickers.add(Sticker(stickerFile.path, ["❤"], editorDataFile?.path));
  }

  await pack.onEdit();
  // Only deleted once packs.json no longer refers to them.
  if (replaced != null) await deleteStickerFiles(replaced);
}

Future<File> saveTemp(Uint8List data) async {
  File output = File("$mediaCacheDir/${uid()}.tmp.webp");
  await output.writeAsBytes(data);
  return output;
}
