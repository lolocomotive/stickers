import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path_provider/path_provider.dart';

enum FontType { bundled, custom, googleFont }

/// Register a single bundled font to the image editor plugin
/// Returns the font file path.
Future<String?> _registerBundledFont(String family, Directory fontsDir) async {
  if (family == "sans-serif" || family == "monospace") return null;
  File fontFile = File("${fontsDir.path}$family.ttf");
  if (!await fontFile.exists()) {
    debugPrint("Copying file to ${fontFile.path}");
    await fontFile.create();
    await fontFile.writeAsBytes((await rootBundle.load("assets/fonts/$family.ttf")).buffer.asInt8List());
  }
  final registeredName = await FontManager.registerFont(fontFile, family);
  if (registeredName != family) {
    throw Exception("Registered Name and font name do not match!\n$registeredName != $family!");
  }
  debugPrint("Registered font $family");
  return fontFile.path;
}

/// Register a single font to the image editor plugin
/// Returns the font file path.
Future<String?> registerFont(FontsRegistryEntry entry) async {
  File fontFile = File(entry.fontFile!);
  if (!await fontFile.exists()) {
    throw Exception("Font file doesn't exist");
  }
  final registeredName = await FontManager.registerFont(fontFile, entry.family);
  if (registeredName != entry.family) {
    throw Exception("Registered Name and font name do not match!\n$registeredName != ${entry.family}!");
  }
  debugPrint("Registered font ${entry.family}");
  return fontFile.path;
}

/// This registers the bundled fonts to the Image editor plugin - not the flutter engine.
Future<void> loadFonts(List<FontsRegistryEntry> fonts) async {
  debugPrint("Registering fonts...");
  Stopwatch sw = Stopwatch()..start();
  Directory fontsDir = Directory("${(await getApplicationDocumentsDirectory()).path}/bundled_fonts/");
  if (!await fontsDir.exists()) await fontsDir.create(recursive: true);
  final futures = <Future>[];
  for (final font in fonts) {
    futures.add((() async {
      if (font.type == FontType.bundled) {
        font.fontFile = await _registerBundledFont(font.family, fontsDir);
      } else {
        await registerFont(font);
      }
    }).call());
  }
  await Future.wait(futures);
  debugPrint("${fonts.length} fonts registered in ${sw.elapsedMilliseconds}ms");
}

final List<FontsRegistryEntry> _bundledFonts = [
  FontsRegistryEntry("sans-serif", FontType.bundled, display: "Classic"),
  FontsRegistryEntry("Saira Stencil One", FontType.bundled, display: "Stencil"),
  FontsRegistryEntry("Lobster", FontType.bundled, display: "Lobster"),
  FontsRegistryEntry("Press Start 2P", FontType.bundled, display: "Game", sizeMultiplier: .7),
  FontsRegistryEntry("Racing Sans One", FontType.bundled, display: "Racing"),
  FontsRegistryEntry("Unifraktur Maguntia", FontType.bundled, display: "Gothic"),
  FontsRegistryEntry("Roboto Mono", FontType.bundled, display: "type", sizeMultiplier: .8),
  FontsRegistryEntry("DM Serif Text", FontType.bundled, display: "Serif"),
  FontsRegistryEntry("Pacifico", FontType.bundled, display: "Pacifico"),
  FontsRegistryEntry("Sacramento", FontType.bundled, display: "Sacramento"),
  FontsRegistryEntry("Passions Conflict", FontType.bundled, display: "Passion", sizeMultiplier: 1.4),
  FontsRegistryEntry("Island Moments", FontType.bundled, display: "Island", sizeMultiplier: 1.3),
];

class FontsRegistryEntry {
  String family;
  String? display;
  bool isLoaded;
  String? previewFile;
  String? fontFile;
  FontType type;
  double sizeMultiplier;

  FontsRegistryEntry(this.family, this.type,
      {this.isLoaded = false, this.previewFile, this.fontFile, this.sizeMultiplier = 1, this.display});

  Map<String, dynamic> toJson() {
    return {
      'family': family,
      'previewFile': previewFile,
      'fontFile': fontFile,
      'type': type.toString(),
      'sizeMultiplier': sizeMultiplier,
      'display': display,
    };
  }

  factory FontsRegistryEntry.fromJson(Map<String, dynamic> json) {
    return FontsRegistryEntry(
      json['family'],
      FontType.values.firstWhere((element) => element.toString() == json['type']),
      previewFile: json['previewFile'],
      fontFile: json['fontFile'],
      sizeMultiplier: json['sizeMultiplier'],
      display: json['display'],
    );
  }
}

/// Used to handle fonts in the app
/// There's a map and a list, as we have to look up the fonts by name and by index in different parts of the app.
/// This keeps it neatly organized
class FontsRegistry {
  /// Entries contains all the fonts downloaded by the user and the preview fonts the app automatically downloads on
  /// the google fonts page.
  static final Map<String, FontsRegistryEntry> _entries = {};

  /// OrderedEntries only contains the fonts the user explicitly added to the app, either by downloading them from
  /// the google fonts page, or from a TTF file.
  static final List<FontsRegistryEntry> _orderedEntries = [];

  /// How many fonts are downloaded by the user
  static int get fontCount => _orderedEntries.length;

  /// How many fonts are downloaded or cached
  static int get size => _entries.length;

  /// The registry automatically saves its contents when modified. This cooldown prevents it from being saved
  /// Many times if it's modified many times in a row. It should only save when the last modification was `cooldown` ago
  static Duration cooldown = Duration(milliseconds: 500);
  static int _saveID = 0;

  static late File _config;

  static bool _init = false;

  static Future<void> init() async {
    if (_init) {
      throw Exception("Already initialized or initializing");
    }
    _init = true;

    try {
      _config = File("${(await getApplicationDocumentsDirectory()).path}/fonts.json");
      try {
        if (await _config.exists()) {
          Stopwatch sw = Stopwatch()..start();
          final List<FontsRegistryEntry> data = jsonDecode(await _config.readAsString())
              .map<FontsRegistryEntry>((e) => FontsRegistryEntry.fromJson(e))
              .toList();
          debugPrint("[FontsRegistry] read t=${sw.elapsedMilliseconds}ms");
          final registerTasks = <Future>[];
          for (final f in data) {
            _entries[f.family] = f;
            if (f.fontFile != null || f.type == FontType.bundled) {
              _orderedEntries.add(f);
            }
            if (f.type != FontType.bundled) {
              if (f.previewFile != null) {
                // The cache has been deleted in between
                if (!File(f.previewFile!).existsSync()) {
                  f.previewFile = null;
                  if (f.fontFile == null) {
                    _entries.remove(f.family);
                  }
                } else {
                  registerTasks.add(_registerFontToEngine(f, true));
                }
              }
              if (f.fontFile != null) {
                registerTasks.add(_registerFontToEngine(f, false));
              }
            }
            f.isLoaded = true;
          }

          registerTasks.add(loadFonts(_orderedEntries));
          await Future.wait(registerTasks);
          debugPrint("[FontsRegistry] loaded ${_entries.length} fonts in ${sw.elapsedMilliseconds}ms");
          return;
        }
      } on Exception catch (e, st) {
        debugPrint("Couldn't read FontsRegistry config");
        debugPrint(e.toString());
        debugPrintStack(stackTrace: st);
      }

      // Fall back to loading only bundled fonts if config couldn't be read.
      for (final f in _bundledFonts) {
        _entries[f.family] = f;
        _orderedEntries.add(f);
        f.isLoaded = true;
      }
      await loadFonts(_orderedEntries);
      enqueueSave();
    } on Exception catch (_) {
      _init = false;
      rethrow;
    }
  }

  static Future<void> _registerFontToEngine(FontsRegistryEntry f, bool preview) async {
    final loader = FontLoader("${f.family}${preview ? '-PREVIEW' : ''}");
    loader.addFont(
        Future.value(ByteData.view((await File(preview ? f.previewFile! : f.fontFile!).readAsBytes()).buffer)));
    await loader.load();
  }

  static void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = _orderedEntries.removeAt(oldIndex);
    _orderedEntries.insert(newIndex, item);
    enqueueSave();
  }

  static double? sizeMultiplier(String fontName) {
    if (!_init) throw Exception("Fonts registry not initalized yet!");
    return _entries[fontName]?.sizeMultiplier;
  }

  static FontsRegistryEntry? get(String fontName) {
    if (!_init) throw Exception("Fonts registry not initalized yet!");
    return _entries[fontName];
  }

  static bool contains(String fontName) {
    if (!_init) throw Exception("Fonts registry not initalized yet!");

    return _entries.containsKey(fontName);
  }

  static void enqueueSave() {
    final saveIDCopy = ++_saveID;
    Future.delayed(cooldown, () {
// This ensures only the last called save actually saves
      if (_saveID == saveIDCopy) {
        save();
      }
    });
  }

  static Future<void> save() async {
    Stopwatch sw = Stopwatch()..start();
    List data = [];

    data.addAll(_orderedEntries.map((e) => e.toJson()));
// The logic here is that all entries that have a font file (not only preview) should already be in the list,
// so this should be sufficient to deduplicate the data. (except for sans-serif)
    data.addAll(_entries.values.where((f) => f.fontFile == null && f.family != "sans-serif").map((e) => e.toJson()));

    await _config.create(recursive: true);
    await _config.writeAsString(jsonEncode(data));
    debugPrint("Saved Fonts registry to ${_config.path} in ${sw.elapsedMilliseconds}ms");
  }

  // Delete a font from the registry
  // Also removes associated TTF files
  static void delete(String fontName) {
    final entry = _entries.remove(fontName);
    if (entry == null) return;
    if (entry.fontFile != null) {
      File(entry.fontFile!).delete();
    }
    if (entry.previewFile != null) {
      File(entry.fontFile!).delete();
    }
    _orderedEntries.remove(entry);
    enqueueSave();
  }

  /// Make sure to call put again when the font is downloaded
  static void put(String fontName, FontsRegistryEntry entry) {
    if (!_init) throw Exception("Fonts registry not initalized yet!");
    _entries[fontName] = entry;
    if (entry.fontFile != null) {
      if (!_orderedEntries.contains(entry)) {
        _orderedEntries.add(entry);
      }
    }
    enqueueSave();
    return;
  }

  static int indexOf(String fontName) {
    return _orderedEntries.indexWhere((f) => f.family == fontName, 0);
  }

  static FontsRegistryEntry at(int i) {
    if (!_init) throw Exception("Fonts registry not initalized yet!");
    return _orderedEntries[i];
  }
}
