import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

/// Converts the whole image to a sticker without trimming its content.
Future<Uint8List> prepareUncroppedSticker(String path, StickerPack pack) async {
  final bytes = await File(path).readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      return await cropSticker(
        Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
        bytes,
        pack,
        0,
        0,
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
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
    for (var i = 0; i < images.length; i++) {
      final file = File('${batchDirectory.path}/$i.webp');
      await file.writeAsBytes(images[i], flush: true);
      added.add(Sticker(file.path, ['❤'], null));
    }
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
