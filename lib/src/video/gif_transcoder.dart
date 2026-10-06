import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// WhatsApp rejects animated stickers above this size.
const int _maxStickerBytes = 500 * 1024;

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

    return compute(_transcodeWorker, params);
  }

  /// Transcodes an existing animated WebP sticker by compositing an overlay onto each frame.
  static Future<Uint8List> transcodeWebpWithOverlay({
    required String webpPath,
    required Uint8List overlayBytes,
  }) async {
    return compute(_transcodeWebpOverlayWorker, _WebpOverlayParams(webpPath, overlayBytes));
  }
}

class _WebpOverlayParams {
  final String webpPath;
  final Uint8List overlayBytes;

  _WebpOverlayParams(this.webpPath, this.overlayBytes);
}

Uint8List _transcodeWebpOverlayWorker(_WebpOverlayParams params) {
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
  });
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

Uint8List _transcodeWorker(_TranscodeParams params) {
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
  });
}

/// Encodes [frames] as an animated WebP, trying each of [attempts] in order until
/// the result fits in [_maxStickerBytes]. Returns the last attempt if none fit.
Uint8List _encodeUnderSizeLimit(
  List<_QualitySettings> attempts,
  List<img.Image> frames,
  img.Image Function(img.Image frame, int fpsStep) buildFrame,
) {
  late Uint8List result;
  for (final setting in attempts) {
    img.Image? animation;
    for (int i = 0; i < frames.length; i += setting.fpsStep) {
      final frame = buildFrame(frames[i], setting.fpsStep);
      if (animation == null) {
        animation = frame;
      } else {
        animation.addFrame(frame);
      }
    }

    result = img.encodeWebP(animation!, lossless: false, quality: setting.quality, method: 3);
    if (result.lengthInBytes <= _maxStickerBytes) break;
  }
  return result;
}

class _QualitySettings {
  final int fpsStep;
  final int quality;

  const _QualitySettings({
    required this.fpsStep,
    required this.quality,
  });
}
