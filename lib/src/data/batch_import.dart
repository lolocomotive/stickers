import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/util.dart';

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
  await Directory(pack.directory).create(recursive: true);
  final first = pack.stickers.length;
  // Same naming as addToPack.
  final added = [
    for (var i = 0; i < images.length; i++) Sticker('${pack.directory}/${first + i}_${uid()}.webp', ['❤'], null),
  ];
  final previousVersion = pack.imageDataVersion;
  try {
    await Future.wait([
      for (var i = 0; i < images.length; i++) File(added[i].source).writeAsBytes(images[i], flush: true),
    ]);
    // Recheck after asynchronous file writes in case the pack changed.
    if (pack.stickers.length + added.length > 30) {
      throw StateError('The sticker pack is full.');
    }
    pack.stickers.addAll(added);
    await pack.onEdit();
  } catch (_) {
    pack.stickers.removeWhere(added.contains);
    pack.imageDataVersion = previousVersion;
    await Future.wait(added.map(deleteStickerFiles));
    rethrow;
  }
}
