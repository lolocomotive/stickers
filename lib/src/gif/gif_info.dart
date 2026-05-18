import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class GifInfo {
  final Duration duration;
  final int frameCount;

  const GifInfo({required this.duration, required this.frameCount});
}

Future<GifInfo> readGifInfo(File file) async {
  return parseGifInfo(await file.readAsBytes());
}

GifInfo parseGifInfo(Uint8List data) {
  if (data.length < 13) {
    throw const FormatException("GIF data is too short");
  }

  final signature = String.fromCharCodes(data.take(6));
  if (signature != "GIF87a" && signature != "GIF89a") {
    throw const FormatException("Not a GIF file");
  }

  var offset = 13;
  final packed = data[10];
  if ((packed & 0x80) != 0) {
    offset += 3 * (1 << ((packed & 0x07) + 1));
  }

  var frameCount = 0;
  var totalDelayMs = 0;
  var pendingDelayMs = 0;

  while (offset < data.length) {
    final block = data[offset++];
    if (block == 0x3B) {
      break;
    }

    if (block == 0x21) {
      if (offset >= data.length) break;
      final label = data[offset++];
      if (label == 0xF9 && offset < data.length) {
        final blockSize = data[offset++];
        if (blockSize == 4 && offset + 4 <= data.length) {
          final delayHundredths = data[offset + 1] | (data[offset + 2] << 8);
          pendingDelayMs = max(delayHundredths * 10, 10);
        }
        offset += blockSize;
        if (offset < data.length && data[offset] == 0) offset++;
      } else {
        offset = _skipSubBlocks(data, offset);
      }
      continue;
    }

    if (block == 0x2C) {
      if (offset + 9 > data.length) break;
      final imagePacked = data[offset + 8];
      offset += 9;
      if ((imagePacked & 0x80) != 0) {
        offset += 3 * (1 << ((imagePacked & 0x07) + 1));
      }
      if (offset >= data.length) break;
      offset++;
      offset = _skipSubBlocks(data, offset);
      frameCount++;
      totalDelayMs += pendingDelayMs == 0 ? 100 : pendingDelayMs;
      pendingDelayMs = 0;
      continue;
    }

    break;
  }

  if (frameCount == 0) {
    throw const FormatException("GIF contains no frames");
  }

  return GifInfo(duration: Duration(milliseconds: totalDelayMs), frameCount: frameCount);
}

int _skipSubBlocks(Uint8List data, int offset) {
  while (offset < data.length) {
    final length = data[offset++];
    if (length == 0) break;
    offset += length;
  }
  return offset;
}
