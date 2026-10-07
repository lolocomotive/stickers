import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:stickers/src/globals.dart';

/// Whether [path] is absolute, for paths from any platform.
bool isAbsolutePath(String path) => path.startsWith("/") || path.contains(":\\") || path.contains(":/");

/// Name of a file, without the directories, for paths from any platform.
String baseName(String path) => path.split(RegExp(r"[/\\]")).last;

/// Extension of a file name, or an empty string.
String extensionOf(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf(".");
  return dot <= 0 ? "" : name.substring(dot + 1);
}

/// [path] relative to [root], or [path] itself when it isn't inside [root].
String relativePath(String path, String root) => path.startsWith("$root/") ? path.substring(root.length + 1) : path;

/// Resolves a path stored with [relativePath] against [root].
///
/// Absolute paths were stored by older versions. Those pointing into a
/// directory named like [root] are moved to [root], which changes when the app
/// data is restored to another location.
String resolvePath(String stored, String root) {
  if (!isAbsolutePath(stored)) return "$root/$stored";
  if (stored.startsWith("$root/")) return stored;
  final marker = "/${baseName(root)}/";
  final i = stored.indexOf(marker);
  return i < 0 ? stored : "$root/${stored.substring(i + marker.length)}";
}

/// Writes [contents] to a temporary file next to [file], then renames it over
/// [file], so [file] is never left half written.
Future<void> writeAtomically(File file, String contents) async {
  final temporary = File("${file.path}.tmp");
  await temporary.writeAsString(contents, flush: true);
  await temporary.rename(file.path);
}

/// Deletes [path] if it's a file that a picker or the share sheet copied into
/// the temporary directory, along with the directories that held only it.
/// Files elsewhere belong to the user and are never touched.
Future<void> deleteTemporaryFile(String? path) async {
  if (path == null || !path.startsWith("$tempDir/")) return;
  try {
    await File(path).delete();
    var dir = File(path).parent;
    while (dir.path.startsWith("$tempDir/") && (await dir.list().isEmpty)) {
      await dir.delete();
      dir = dir.parent;
    }
  } catch (e) {
    debugPrint("Couldn't delete temporary file $path: $e");
  }
}

/// Deletes every entry in [dir], keeping [dir] itself.
Future<void> clearDirectory(Directory dir, {bool Function(FileSystemEntity entry)? where}) async {
  if (!await dir.exists()) return;
  await for (final entry in dir.list()) {
    if (where != null && !where(entry)) continue;
    try {
      await entry.delete(recursive: true);
    } catch (e) {
      debugPrint("Couldn't delete ${entry.path}: $e");
    }
  }
}

/// Removes what earlier sessions left behind in the caches. Nothing in them is
/// used across sessions, and they live in the documents directory, which
/// Android never clears on its own.
///
/// Must run before anything writes to the caches.
Future<void> clearSessionCaches() async {
  await Future.wait([
    clearDirectory(Directory(mediaCacheDir)),
    clearDirectory(Directory(exportCacheDir)),
  ]);
}

/// Removes temporary files older than a day, which pickers and the share
/// sheet leave behind when the app is closed before they are used. Recent
/// files are kept, as the share sheet may have copied the file this session
/// was started with.
Future<void> clearStaleTemporaryFiles() async {
  final threshold = DateTime.now().subtract(const Duration(days: 1));
  final dir = Directory(tempDir);
  if (!await dir.exists()) return;
  await for (final entry in dir.list()) {
    try {
      if ((await entry.stat()).modified.isAfter(threshold)) continue;
      // Directories may hold recent files.
      if (entry is Directory) {
        await clearDirectory(entry, where: (e) => e.statSync().modified.isBefore(threshold));
        if (await entry.list().isEmpty) await entry.delete();
      } else {
        await entry.delete();
      }
    } catch (e) {
      debugPrint("Couldn't delete ${entry.path}: $e");
    }
  }
}
