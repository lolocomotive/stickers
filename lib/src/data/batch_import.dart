import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

/// Converts the whole image to a sticker without trimming its content.
Future<Uint8List> prepareUncroppedSticker(String path) async {
  // The descriptor reads the dimensions from the header without decoding pixels.
  final buffer = await ImmutableBuffer.fromFilePath(path);
  final ImageDescriptor descriptor;
  try {
    descriptor = await ImageDescriptor.encoded(buffer);
  } finally {
    buffer.dispose();
  }
  final width = descriptor.width;
  final height = descriptor.height;
  descriptor.dispose();
  return cropStickerFile(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), path, 0);
}

/// Writes the entire batch before publishing it to the pack. A failure rolls
/// back the new entries and files, so retrying never duplicates earlier items.
Future<void> saveStickerBatch(StickerPack pack, List<Uint8List> images) async {
  if (images.isEmpty) return;
  if (pack.animated || pack.stickers.length + images.length > 30) {
    throw StateError('The selected images do not fit in this static sticker pack.');
  }
  final directory = Directory('$packsDir/${pack.id}');
  await directory.create(recursive: true);
  final batchDirectory = await directory.createTemp('batch_');
  final added = <Sticker>[];
  final previousVersion = pack.imageDataVersion;
  try {
    final files = await Future.wait([
      for (var i = 0; i < images.length; i++)
        File('${batchDirectory.path}/$i.webp').writeAsBytes(images[i], flush: true),
    ]);
    added.addAll(files.map((file) => Sticker(file.path, ['❤'], null)));
    // Recheck after asynchronous file writes in case the pack changed.
    if (pack.stickers.length + added.length > 30) {
      throw StateError('The sticker pack is full.');
    }
    pack.stickers.addAll(added);
    pack.imageDataVersion = (int.parse(previousVersion) + 1).toString();
    final manifest = File('$packsDir/packs.json');
    final temporaryManifest = File('${batchDirectory.path}/packs.json');
    await temporaryManifest.writeAsString(jsonEncode(packs.map((p) => p.toJson()).toList()), flush: true);
    await temporaryManifest.rename(manifest.path);
  } catch (_) {
    pack.stickers.removeWhere(added.contains);
    pack.imageDataVersion = previousVersion;
    await batchDirectory.delete(recursive: true);
    rethrow;
  }
}
