import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// WhatsApp rejects animated stickers above this size.
const int _maxStickerBytes = 500 * 1024;

/// Receives the encoded fraction (0 to 1) of the current compression attempt, out of [attempts].
typedef TranscodeProgress = void Function(int attempt, int attempts, double progress);

class GifInfo {
  final int width;
  final int height;
  final Duration duration;

  GifInfo({
    required this.width,
    required this.height,
    required this.duration,
  });
}

class GifTranscoder {
  /// Checks if a file is a valid GIF by checking extension and GIF magic bytes ('GIF87a' or 'GIF89a').
  static bool isGifFile(String filePath) {
    try {
      final parts = filePath.toLowerCase().split('.');
      if (parts.length < 2 || parts.last != 'gif') return false;
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() < 6) return false;
      final raf = file.openSync();
      final header = raf.readSync(6);
      raf.closeSync();
      final headerStr = String.fromCharCodes(header);
      return headerStr == 'GIF87a' || headerStr == 'GIF89a';
    } catch (_) {
      return false;
    }
  }

  /// Inspects a GIF file to retrieve metadata.
  static Future<GifInfo?> inspectGifFile(String filePath) async {
    return compute(_inspectGifWorker, filePath);
  }

  static GifInfo? _inspectGifWorker(String filePath) {
    try {
      if (!isGifFile(filePath)) {
        return null;
      }
      final bytes = File(filePath).readAsBytesSync();
      final gif = img.decodeGif(bytes);
      if (gif == null) return null;
      int totalMs = 0;
      for (final frame in gif.frames) {
        totalMs += frame.frameDuration > 0 ? frame.frameDuration : 100;
      }
      return GifInfo(
        width: gif.width,
        height: gif.height,
        duration: Duration(milliseconds: totalMs > 0 ? totalMs : 100),
      );
    } catch (e) {
      debugPrint("Failed to inspect GIF: $e");
      return null;
    }
  }

  /// Transcodes GIF frames into an animated WebP sticker.
  ///
  /// WhatsApp animated sticker requirements:
  /// - Exact canvas dimension: 512x512
  /// - File size: <= 500 KB
  /// - Maximum duration: Typically <= 3 seconds recommended
  /// - Loop: Infinitely looping
  ///
  /// Supports:
  /// - [cropRect]: Normalized crop rect [0.0, 1.0] relative to the image after applying [rotationDegrees].
  /// - [rotationDegrees]: Rotation (0, 90, 180, 270).
  /// - [stretch]: If true, stretched to 512x512; if false, fitted with aspect ratio preserved.
  /// - [speed]: Playback speed multiplier (e.g. 1.0, 1.5, 2.0).
  /// - [startFraction] and [endFraction]: Trimming range [0.0, 1.0].
  /// - Multi-attempt compression if output exceeds 500 KB.
  static Future<Uint8List> transcodeToWebP({
    required String gifPath,
    Rect? cropRect,
    int rotationDegrees = 0,
    bool stretch = false,
    double speed = 1.0,
    double startFraction = 0.0,
    double endFraction = 1.0,
    TranscodeProgress? onProgress,
  }) async {
    final params = _TranscodeParams(
      gifPath: gifPath,
      cropLeft: cropRect?.left ?? 0.0,
      cropTop: cropRect?.top ?? 0.0,
      cropWidth: cropRect?.width ?? 1.0,
      cropHeight: cropRect?.height ?? 1.0,
      rotationDegrees: rotationDegrees,
      stretch: stretch,
      speed: speed <= 0 ? 1.0 : speed,
      startFraction: startFraction.clamp(0.0, 1.0),
      endFraction: endFraction.clamp(0.0, 1.0),
    );

    return _runWithProgress(_transcodeWorker, params, onProgress);
  }

  /// Transcodes an existing animated WebP sticker by compositing an overlay onto each frame.
  static Future<Uint8List> transcodeWebpWithOverlay({
    required String webpPath,
    required Uint8List overlayBytes,
    TranscodeProgress? onProgress,
  }) async {
    return _runWithProgress(_transcodeWebpOverlayWorker, _WebpOverlayParams(webpPath, overlayBytes), onProgress);
  }

  /// Extracts [count] evenly spaced frames from the GIF, each scaled down so its shorter side
  /// is [shortSide] pixels and PNG-encoded.
  static Future<List<Uint8List>> extractThumbnails(String gifPath, int count, int shortSide) {
    return compute(_thumbnailWorker, (gifPath, count, shortSide));
  }
}

List<Uint8List> _thumbnailWorker((String, int, int) params) {
  final (gifPath, count, shortSide) = params;
  final gif = img.decodeGif(File(gifPath).readAsBytesSync());
  if (gif == null || gif.frames.isEmpty) return [];

  final frameEndsMs = <int>[];
  int totalMs = 0;
  for (final frame in gif.frames) {
    totalMs += frame.frameDuration > 0 ? frame.frameDuration : 100;
    frameEndsMs.add(totalMs);
  }

  final thumbnails = <Uint8List>[];
  int frameIndex = 0;
  for (int i = 0; i < count; i++) {
    // Sample the middle of each slot so the thumbnail represents its segment
    final timeMs = totalMs * (2 * i + 1) / (2 * count);
    while (frameIndex < gif.frames.length - 1 && frameEndsMs[frameIndex] <= timeMs) {
      frameIndex++;
    }
    final frame = img.Image.from(gif.frames[frameIndex], noAnimation: true);
    final scaled = frame.width <= frame.height
        ? img.copyResize(frame, width: min(shortSide, frame.width))
        : img.copyResize(frame, height: min(shortSide, frame.height));
    thumbnails.add(img.encodePng(scaled));
  }
  return thumbnails;
}

/// Runs [work] in a background isolate, forwarding its progress reports to [onProgress].
Future<Uint8List> _runWithProgress<P>(
  Uint8List Function(P params, TranscodeProgress report) work,
  P params,
  TranscodeProgress? onProgress,
) async {
  final replies = ReceivePort();
  try {
    await Isolate.spawn(
      _runJob,
      _Job(replies.sendPort, work, params),
      onError: replies.sendPort,
      onExit: replies.sendPort,
    );
    await for (final message in replies) {
      if (message is (int, int, double)) {
        onProgress?.call(message.$1, message.$2, message.$3);
      } else if (message is TransferableTypedData) {
        return message.materialize().asUint8List();
      } else if (message is List) {
        throw Exception(message.first);
      } else {
        break;
      }
    }
    throw StateError("Transcoder stopped unexpectedly");
  } finally {
    replies.close();
  }
}

class _Job<P> {
  final SendPort replies;
  final Uint8List Function(P params, TranscodeProgress report) work;
  final P params;

  _Job(this.replies, this.work, this.params);

  void run() {
    final result = work(params, (attempt, attempts, progress) => replies.send((attempt, attempts, progress)));
    replies.send(TransferableTypedData.fromList([result]));
  }
}

void _runJob(_Job job) => job.run();

class _WebpOverlayParams {
  final String webpPath;
  final Uint8List overlayBytes;

  _WebpOverlayParams(this.webpPath, this.overlayBytes);
}

Uint8List _transcodeWebpOverlayWorker(_WebpOverlayParams params, TranscodeProgress report) {
  final bytes = File(params.webpPath).readAsBytesSync();
  final webp = img.decodeWebP(bytes);
  if (webp == null || webp.numFrames == 0) {
    throw Exception("Could not decode animated WebP sticker.");
  }

  img.Image? overlayImg;
  try {
    overlayImg = img.decodeImage(params.overlayBytes);
  } catch (e) {
    debugPrint("Failed to decode overlay image: $e");
  }

  if (overlayImg == null) {
    return bytes;
  }

  const attempts = [
    _QualitySettings(fpsStep: 1, quality: 70),
    _QualitySettings(fpsStep: 1, quality: 50),
    _QualitySettings(fpsStep: 2, quality: 40),
    _QualitySettings(fpsStep: 3, quality: 30),
  ];

  return _encodeUnderSizeLimit(attempts, webp.frames, (frame, fpsStep) {
    final composed = img.Image.from(frame, noAnimation: true);
    img.compositeImage(composed, overlayImg!);
    final rawDurationMs = frame.frameDuration > 0 ? frame.frameDuration : 100;
    composed.frameDuration = rawDurationMs * fpsStep;
    return composed;
  }, report);
}

class _TranscodeParams {
  final String gifPath;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  final int rotationDegrees;
  final bool stretch;
  final double speed;
  final double startFraction;
  final double endFraction;

  _TranscodeParams({
    required this.gifPath,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.rotationDegrees,
    required this.stretch,
    required this.speed,
    required this.startFraction,
    required this.endFraction,
  });
}

Uint8List _transcodeWorker(_TranscodeParams params, TranscodeProgress report) {
  if (!GifTranscoder.isGifFile(params.gifPath)) {
    throw Exception("Unsupported or invalid GIF format.");
  }
  final bytes = File(params.gifPath).readAsBytesSync();
  final gif = img.decodeGif(bytes);
  if (gif == null || gif.numFrames == 0) {
    throw Exception("Could not decode GIF animation.");
  }

  final totalSourceFrames = gif.numFrames;
  final startIndex = (totalSourceFrames * params.startFraction).floor().clamp(0, totalSourceFrames - 1);
  final endIndex = (totalSourceFrames * params.endFraction).ceil().clamp(startIndex + 1, totalSourceFrames);
  final selectedSourceFrames = gif.frames.sublist(startIndex, endIndex);

  final normRotation = ((params.rotationDegrees % 360) + 360) % 360;

  // Multi-pass compression to stay under 500 KB WhatsApp limit
  // Pass 1: standard (fps up to 24, quality 70)
  // Pass 2: lower quality 50
  // Pass 3: frame drop (skip every 2nd frame) + quality 40
  // Pass 4: frame drop (skip 2 of 3) + quality 30
  // Pass 5: frame drop (skip 3 of 4) + quality 20
  const attempts = [
    _QualitySettings(fpsStep: 1, quality: 70),
    _QualitySettings(fpsStep: 1, quality: 50),
    _QualitySettings(fpsStep: 2, quality: 40),
    _QualitySettings(fpsStep: 3, quality: 30),
    _QualitySettings(fpsStep: 4, quality: 20),
  ];

  return _encodeUnderSizeLimit(attempts, selectedSourceFrames, (srcFrame, fpsStep) {
    // 1. Rotate first: the crop rect is normalized to the rotated preview
    final rotated = normRotation == 0 ? srcFrame : img.copyRotate(srcFrame, angle: normRotation);

    // 2. Crop
    final cropX = (rotated.width * params.cropLeft).round().clamp(0, rotated.width - 1);
    final cropY = (rotated.height * params.cropTop).round().clamp(0, rotated.height - 1);
    final cropW = (rotated.width * params.cropWidth).round().clamp(1, rotated.width - cropX);
    final cropH = (rotated.height * params.cropHeight).round().clamp(1, rotated.height - cropY);
    final cropped = img.copyCrop(rotated, x: cropX, y: cropY, width: cropW, height: cropH);

    // 3. Scale / Fit onto 512x512 canvas
    final img.Image finalFrame;
    if (params.stretch) {
      finalFrame = img.copyResize(cropped, width: 512, height: 512, interpolation: img.Interpolation.linear);
    } else {
      // Fit within 512x512 with transparent background
      final double scale = min(512.0 / cropped.width, 512.0 / cropped.height);
      final int targetW = (cropped.width * scale).round().clamp(1, 512);
      final int targetH = (cropped.height * scale).round().clamp(1, 512);
      final resized = img.copyResize(cropped, width: targetW, height: targetH, interpolation: img.Interpolation.linear);

      finalFrame = img.Image(width: 512, height: 512, numChannels: 4);
      img.compositeImage(finalFrame, resized, dstX: (512 - targetW) ~/ 2, dstY: (512 - targetH) ~/ 2);
    }

    // 4. Calculate frame duration adjusted by speed and dropped frames
    final rawDurationMs = srcFrame.frameDuration > 0 ? srcFrame.frameDuration : 100;
    finalFrame.frameDuration = (rawDurationMs * fpsStep / params.speed).round().clamp(20, 10000);
    return finalFrame;
  }, report);
}

/// Encodes [frames] as an animated WebP, trying each of [attempts] in order until
/// the result fits in [_maxStickerBytes]. Returns the last attempt if none fit.
///
/// Frames are encoded one at a time so that [report] can follow each attempt.
Uint8List _encodeUnderSizeLimit(
  List<_QualitySettings> attempts,
  List<img.Image> frames,
  img.Image Function(img.Image frame, int fpsStep) buildFrame,
  TranscodeProgress report,
) {
  late Uint8List result;
  for (int attempt = 0; attempt < attempts.length; attempt++) {
    final setting = attempts[attempt];
    final frameCount = (frames.length / setting.fpsStep).ceil();
    final encoded = <_EncodedFrame>[];
    report(attempt, attempts.length, 0);
    for (int i = 0; i < frames.length; i += setting.fpsStep) {
      final frame = buildFrame(frames[i], setting.fpsStep);
      final bytes = img.encodeWebP(frame, lossless: false, quality: setting.quality, method: 3);
      encoded.add(_EncodedFrame(frame.width, frame.height, frame.frameDuration, _frameChunks(bytes)));
      report(attempt, attempts.length, encoded.length / frameCount);
    }

    result = _buildAnimatedWebP(encoded);
    if (result.lengthInBytes <= _maxStickerBytes) break;
  }
  return result;
}

class _EncodedFrame {
  final int width;
  final int height;
  final int durationMs;

  /// The frame's bitstream chunks, preceded by its alpha plane if it has one.
  final List<(String, Uint8List)> chunks;

  _EncodedFrame(this.width, this.height, this.durationMs, this.chunks);
}

/// Extracts the image chunks from a single frame WebP file.
List<(String, Uint8List)> _frameChunks(Uint8List webp) {
  final data = ByteData.sublistView(webp);
  final chunks = <(String, Uint8List)>[];
  for (int pos = 12; pos + 8 <= webp.length;) {
    final tag = String.fromCharCodes(webp, pos, pos + 4);
    final size = data.getUint32(pos + 4, Endian.little);
    if (tag == 'ALPH' || tag == 'VP8 ' || tag == 'VP8L') {
      chunks.add((tag, Uint8List.sublistView(webp, pos + 8, pos + 8 + size)));
    }
    pos += 8 + size + (size & 1);
  }
  return chunks;
}

/// Assembles [frames] into an infinitely looping animated WebP file.
Uint8List _buildAnimatedWebP(List<_EncodedFrame> frames) {
  final width = frames.map((f) => f.width).reduce(max);
  final height = frames.map((f) => f.height).reduce(max);
  final hasAlpha = frames.any((f) => f.chunks.any((c) => c.$1 == 'ALPH'));

  final body = BytesBuilder(copy: false)..add('WEBP'.codeUnits);
  final vp8x = BytesBuilder()
    ..addByte((hasAlpha ? 1 << 4 : 0) | 1 << 1)
    ..add([0, 0, 0])
    ..add(_uint24(width - 1))
    ..add(_uint24(height - 1));
  _writeChunk(body, 'VP8X', vp8x.takeBytes());
  // Transparent background, infinite loop
  _writeChunk(body, 'ANIM', Uint8List(6));
  for (final frame in frames) {
    final anmf = BytesBuilder(copy: false)
      ..add(_uint24(0))
      ..add(_uint24(0))
      ..add(_uint24(frame.width - 1))
      ..add(_uint24(frame.height - 1))
      ..add(_uint24(frame.durationMs.clamp(0, 0xffffff)))
      // Frames are whole, so each one is disposed and drawn without blending
      ..addByte(1 | 2);
    for (final (tag, data) in frame.chunks) {
      _writeChunk(anmf, tag, data);
    }
    _writeChunk(body, 'ANMF', anmf.takeBytes());
  }

  final out = BytesBuilder(copy: false);
  _writeChunk(out, 'RIFF', body.takeBytes());
  return out.takeBytes();
}

void _writeChunk(BytesBuilder out, String tag, Uint8List data) {
  out
    ..add(tag.codeUnits)
    ..add((ByteData(4)..setUint32(0, data.length, Endian.little)).buffer.asUint8List())
    ..add(data);
  if (data.length.isOdd) out.addByte(0);
}

List<int> _uint24(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff];

class _QualitySettings {
  final int fpsStep;
  final int quality;

  const _QualitySettings({
    required this.fpsStep,
    required this.quality,
  });
}
