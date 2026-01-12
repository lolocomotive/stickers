import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:stickers/src/util.dart';
import 'package:path/path.dart' as p;
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/video/frame_decoder.dart';

/// Service for exporting frames to animated WebP files
class FrameExportService {
  final StreamController<double> _progressController =
      StreamController.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  /// Export a list of decoded frames to an animated WebP file
  ///
  /// [frames] - List of decoded frames with RGBA data
  /// [outputPath] - Path for the output animated WebP
  /// [fps] - Frames per second for the animation
  /// [width] - Output width (default 512 for stickers)
  /// [height] - Output height (default 512 for stickers)
  /// [quality] - WebP quality (0-100)
  Future<bool> exportFrames({
    required List<DecodedFrame> frames,
    required String outputPath,
    required double fps,
    int width = 512,
    int height = 512,
    int quality = 80,
  }) async {
    if (frames.isEmpty) return false;

    try {
      _progressController.add(0.0);

      // Create temp directory for PNG frames
      final tempDir = Directory(
          '$mediaCacheDir/export_${uid()}');
      await tempDir.create(recursive: true);

      // Write frames as PNG files
      for (int i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final pngPath =
            p.join(tempDir.path, 'frame_${i.toString().padLeft(5, '0')}.png');

        // Convert ui.Image to PNG bytes
        final pngBytes = await _imageToRgbaPng(frame.image);
        if (pngBytes == null) {
          await tempDir.delete(recursive: true);
          return false;
        }

        await File(pngPath).writeAsBytes(pngBytes);
        _progressController.add(0.3 * (i + 1) / frames.length);
      }

      // Use FFmpeg to encode PNG sequence to animated WebP
      final inputPattern = p.join(tempDir.path, 'frame_%05d.png');

      // Build FFmpeg command for animated WebP with alpha
      final command = '-y -framerate $fps -i "$inputPattern" '
          '-vf "scale=$width:$height:flags=lanczos:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=0x00000000,format=rgba" '
          '-c:v libwebp_anim -quality $quality -lossless 0 '
          '-loop 0 -preset picture '
          '"$outputPath"';

      _progressController.add(0.4);

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      _progressController.add(0.9);

      // Cleanup temp directory
      await tempDir.delete(recursive: true);

      if (ReturnCode.isSuccess(returnCode)) {
        // Verify output exists and has content
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          if (size > 0) {
            _progressController.add(1.0);
            return true;
          }
        }
      }

      // Log error if failed
      final logs = await session.getOutput();
      print('FFmpeg export failed: $logs');
      return false;
    } catch (e) {
      print('Frame export error: $e');
      return false;
    }
  }

  /// Export frames with an overlay image applied
  ///
  /// [frames] - List of decoded frames
  /// [overlayPath] - Path to the overlay PNG (text/drawings)
  /// [outputPath] - Path for the output animated WebP
  /// [fps] - Frames per second
  Future<bool> exportFramesWithOverlay({
    required List<DecodedFrame> frames,
    required String? overlayPath,
    required String outputPath,
    required double fps,
    int width = 512,
    int height = 512,
    int quality = 80,
  }) async {
    if (frames.isEmpty) return false;

    try {
      _progressController.add(0.0);

      // Create temp directory for PNG frames
      final tempDir = Directory(
          '$mediaCacheDir/export_${uid()}');
      await tempDir.create(recursive: true);

      // Write frames as PNG files
      for (int i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final pngPath =
            p.join(tempDir.path, 'frame_${i.toString().padLeft(5, '0')}.png');

        final pngBytes = await _imageToRgbaPng(frame.image);
        if (pngBytes == null) {
          await tempDir.delete(recursive: true);
          return false;
        }

        await File(pngPath).writeAsBytes(pngBytes);
        _progressController.add(0.3 * (i + 1) / frames.length);
      }

      final inputPattern = p.join(tempDir.path, 'frame_%05d.png');

      String filterComplex;
      String inputs;

      if (overlayPath != null && await File(overlayPath).exists()) {
        // With overlay: scale frames, apply overlay, pad to square
        inputs = '-framerate $fps -i "$inputPattern" -i "$overlayPath"';
        filterComplex =
            '[0:v]scale=$width:$height:flags=lanczos:force_original_aspect_ratio=decrease,'
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=0x00000000,format=rgba[base];'
            '[1:v]scale=$width:$height:flags=lanczos,format=rgba[overlay];'
            '[base][overlay]overlay=0:0:format=auto[out]';
      } else {
        // Without overlay: just scale and pad
        inputs = '-framerate $fps -i "$inputPattern"';
        filterComplex =
            '[0:v]scale=$width:$height:flags=lanczos:force_original_aspect_ratio=decrease,'
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=0x00000000,format=rgba[out]';
      }

      final command = '-y $inputs '
          '-filter_complex "$filterComplex" '
          '-map "[out]" '
          '-c:v libwebp_anim -quality $quality -lossless 0 '
          '-loop 0 -preset picture '
          '"$outputPath"';

      _progressController.add(0.4);

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      _progressController.add(0.9);

      // Cleanup temp directory
      await tempDir.delete(recursive: true);

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          if (size > 0) {
            _progressController.add(1.0);
            return true;
          }
        }
      }

      final logs = await session.getOutput();
      print('FFmpeg export with overlay failed: $logs');
      return false;
    } catch (e) {
      print('Frame export with overlay error: $e');
      return false;
    }
  }

  /// Export trimmed frames directly to WebP with quality preservation
  /// This avoids the intermediate GIF step and preserves sticker parameters
  Future<bool> exportTrimmedWebP({
    required List<DecodedFrame> frames,
    required String outputPath,
    required double fps,
    int width = 512,
    int height = 512,
    int quality = 85, // Higher default quality for trim operations
  }) async {
    if (frames.isEmpty) return false;

    try {
      _progressController.add(0.0);

      // Create temp directory for PNG frames
      final tempDir = Directory(
          '$mediaCacheDir/export_trim_${uid()}');
      await tempDir.create(recursive: true);

      // Write frames as PNG files
      for (int i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final pngPath =
            p.join(tempDir.path, 'frame_${i.toString().padLeft(5, '0')}.png');

        final pngBytes = await _imageToRgbaPng(frame.image);
        if (pngBytes == null) {
          await tempDir.delete(recursive: true);
          return false;
        }

        await File(pngPath).writeAsBytes(pngBytes);
        _progressController.add(0.3 * (i + 1) / frames.length);
      }

      final inputPattern = p.join(tempDir.path, 'frame_%05d.png');

      // Build optimized FFmpeg command for animated WebP
      // Use higher quality settings since this is a trim operation
      final command = '-y -framerate $fps -i "$inputPattern" '
          '-vf "scale=$width:$height:flags=lanczos:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=0x00000000,format=rgba" '
          '-c:v libwebp_anim -quality $quality -lossless 0 '
          '-compression_level 4 '
          '-loop 0 -preset picture '
          '"$outputPath"';

      _progressController.add(0.4);

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      _progressController.add(0.9);

      // Cleanup temp directory
      await tempDir.delete(recursive: true);

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          if (size > 0) {
            _progressController.add(1.0);
            return true;
          }
        }
      }

      final logs = await session.getOutput();
      print('FFmpeg trimmed WebP export failed: $logs');
      return false;
    } catch (e) {
      print('Frame trim export error: $e');
      return false;
    }
  }

  /// Convert a ui.Image to PNG bytes with RGBA preserved
  Future<Uint8List?> _imageToRgbaPng(ui.Image image) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Error converting image to PNG: $e');
      return null;
    }
  }

  void dispose() {
    _progressController.close();
  }
}

// MediaType and EditArguments are defined in crop_page.dart
