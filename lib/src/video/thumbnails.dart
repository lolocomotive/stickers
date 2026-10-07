import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:stickers/src/video/gif_transcoder.dart';

const _thumbnailsChannel = EventChannel('de.loicezt.stickers/thumbnails');

/// Streams [count] evenly spaced thumbnails of the video or GIF at [path], for display in a
/// timeline. Each is scaled down so its shorter side is [shortSide] pixels, enough to cover a
/// [shortSide]-pixel square cell in any orientation. Each event is the thumbnail's slot index
/// and image; video frames arrive one by one as they're decoded, and slots whose frame couldn't
/// be decoded are skipped. The listener owns the emitted images and must dispose them.
Stream<(int, ui.Image)> loadVideoThumbnails(
  String path, {
  required bool isGif,
  int count = 10,
  required int shortSide,
}) {
  final Stream<(int, Uint8List)> encoded;
  if (isGif) {
    encoded = GifTranscoder.extractThumbnails(path, count, shortSide)
        .asStream()
        .expand((frames) => [for (int i = 0; i < frames.length; i++) (i, frames[i])]);
  } else {
    encoded = _thumbnailsChannel.receiveBroadcastStream({
      'path': path,
      'count': count,
      'shortSide': shortSide,
    }).map((event) {
      final map = event as Map;
      return (map['index'] as int, map['bytes'] as Uint8List);
    });
  }

  return encoded.asyncExpand((entry) async* {
    final (index, bytes) = entry;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      yield (index, frame.image);
    } catch (e) {
      debugPrint("Failed to decode thumbnail: $e");
    }
  });
}
