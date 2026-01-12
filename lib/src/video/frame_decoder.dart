import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:stickers/src/util.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Represents a single decoded frame with its image data and timing information
class DecodedFrame {
  final ui.Image image;
  final int frameIndex;
  final Duration timestamp;
  final Duration duration;

  DecodedFrame({
    required this.image,
    required this.frameIndex,
    required this.timestamp,
    required this.duration,
  });
}

/// Metadata about a decoded animation
class AnimationMetadata {
  final int frameCount;
  final double fps;
  final Duration totalDuration;
  final int width;
  final int height;
  final bool hasAlpha;

  AnimationMetadata({
    required this.frameCount,
    required this.fps,
    required this.totalDuration,
    required this.width,
    required this.height,
    required this.hasAlpha,
  });

  Duration get frameDuration => Duration(microseconds: (1000000 / fps).round());
}

/// Quick frame count check result
class QuickFrameInfo {
  final int estimatedFrameCount;
  final double fps;
  final Duration duration;
  final String? error;

  QuickFrameInfo({
    required this.estimatedFrameCount,
    required this.fps,
    required this.duration,
    this.error,
  });

  bool get hasEnoughFrames => estimatedFrameCount >= 2 && error == null;
  bool get isEmpty => estimatedFrameCount == 0;
  bool get isSingleFrame => estimatedFrameCount == 1;
}

/// Static utilities for quick media validation without full decoding
class MediaValidator {
  /// Get estimated frame count for a video/animation file using FFprobe
  /// This is faster than full decoding and useful for validation before processing
  static Future<QuickFrameInfo> getQuickFrameInfo(String filePath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(filePath);
      final info = session.getMediaInformation();

      if (info == null) {
        return QuickFrameInfo(
          estimatedFrameCount: 0,
          fps: 0,
          duration: Duration.zero,
          error: 'Failed to get media information',
        );
      }

      final streams = info.getStreams();
      if (streams.isEmpty) {
        return QuickFrameInfo(
          estimatedFrameCount: 0,
          fps: 0,
          duration: Duration.zero,
          error: 'No streams found in media',
        );
      }

      // Find video stream
      final videoStream = streams.firstWhere(
        (s) => s.getType() == 'video',
        orElse: () => streams.first,
      );

      // Parse frame rate
      final fpsStr =
          videoStream.getRealFrameRate() ??
          videoStream.getAverageFrameRate() ??
          '24/1';
      double fps = 24.0;
      if (fpsStr.contains('/')) {
        final parts = fpsStr.split('/');
        if (parts.length == 2) {
          final num = double.tryParse(parts[0]) ?? 24;
          final den = double.tryParse(parts[1]) ?? 1;
          fps = den > 0 ? num / den : 24;
        }
      } else {
        fps = double.tryParse(fpsStr) ?? 24;
      }
      fps = fps.clamp(1.0, 120.0);

      // Get duration
      final durationStr = info.getDuration() ?? '0';
      final durationSec = double.tryParse(durationStr) ?? 0;
      final duration = Duration(microseconds: (durationSec * 1000000).round());

      // Estimate frame count - use floor to be conservative
      final frameCount = (durationSec * fps).floor().clamp(0, 100000);

      return QuickFrameInfo(
        estimatedFrameCount: frameCount,
        fps: fps,
        duration: duration,
      );
    } catch (e) {
      return QuickFrameInfo(
        estimatedFrameCount: 0,
        fps: 0,
        duration: Duration.zero,
        error: 'Error analyzing media: $e',
      );
    }
  }
}

/// Service to decode animated images (WebP, GIF) and videos into individual RGBA frames
/// Preserves alpha channel throughout the decoding process
class FrameDecoderService {
  String? _framesDir;
  AnimationMetadata? _metadata;
  List<DecodedFrame>? _frames;
  bool _isDecoding = false;
  bool _ownershipTransferred =
      false; // Track if frames were transferred to cache

  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  AnimationMetadata? get metadata => _metadata;
  List<DecodedFrame>? get frames => _frames;
  bool get isDecoding => _isDecoding;
  bool get isReady => _frames != null && _frames!.isNotEmpty;

  /// Mark that frame ownership has been transferred (e.g., to FrameCache)
  /// This prevents dispose() from destroying the frames
  void transferOwnership() {
    _ownershipTransferred = true;
  }

  /// Inject pre-decoded frames (from FrameCache) instead of decoding
  /// This avoids redundant decode cycles
  void injectCachedFrames(
    List<DecodedFrame> frames,
    AnimationMetadata metadata,
  ) {
    _frames = frames;
    _metadata = metadata;
    _ownershipTransferred = false; // We now own these frames
  }

  /// Decode an animated file (WebP, GIF, or video) into individual frames
  /// Returns true on success, false on failure
  Future<bool> decode(String inputPath) async {
    if (_isDecoding) return false;
    _isDecoding = true;
    _ownershipTransferred = false; // Reset ownership flag for new decode cycle
    _progressController.add(0.0);

    try {
      final extension = inputPath.toLowerCase().split('.').last;

      // For WebP and GIF, try native Flutter decoding first (more reliable)
      if (extension == 'webp' || extension == 'gif') {
        final success = await _decodeWithNativeCodec(inputPath);
        if (success) {
          _progressController.add(1.0);
          _isDecoding = false;
          return true;
        }
        print('Native codec failed, falling back to FFmpeg');
      }

      // Create temp directory for frames (for FFmpeg fallback)
      final tempDir = await getTemporaryDirectory();
      _framesDir = '${tempDir.path}/frames_${uid()}';
      await Directory(_framesDir!).create(recursive: true);

      // Get media information
      _metadata = await _getMediaInfo(inputPath);
      if (_metadata == null) {
        print('Failed to get media info for $inputPath');
        _isDecoding = false;
        return false;
      }

      _progressController.add(0.1);

      // Extract frames with alpha channel preserved
      final success = await _extractFrames(inputPath);
      if (!success) {
        print('Failed to extract frames from $inputPath');
        _isDecoding = false;
        return false;
      }

      _progressController.add(0.5);

      // Load frames into memory
      _frames = await _loadFrames();
      if (_frames == null || _frames!.isEmpty) {
        print('Failed to load frames');
        _isDecoding = false;
        return false;
      }

      _progressController.add(1.0);
      _isDecoding = false;
      return true;
    } catch (e) {
      print('Error decoding: $e');
      _isDecoding = false;
      return false;
    }
  }

  /// Decode animated WebP/GIF using Flutter's native image codec
  /// This is more reliable than FFmpeg for these formats
  Future<bool> _decodeWithNativeCodec(String inputPath) async {
    try {
      final file = File(inputPath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);

      final frameCount = codec.frameCount;
      if (frameCount == 0) {
        codec.dispose();
        return false;
      }

      _progressController.add(0.1);

      // Decode all frames
      final frames = <DecodedFrame>[];
      Duration totalDuration = Duration.zero;
      int width = 0;
      int height = 0;

      for (int i = 0; i < frameCount; i++) {
        final frameInfo = await codec.getNextFrame();
        final image = frameInfo.image;
        final duration = frameInfo.duration;

        if (width == 0) {
          width = image.width;
          height = image.height;
        }

        frames.add(
          DecodedFrame(
            image: image,
            frameIndex: i,
            timestamp: totalDuration,
            duration: duration,
          ),
        );

        totalDuration += duration;
        _progressController.add(0.1 + 0.9 * (i + 1) / frameCount);
      }

      codec.dispose();

      if (frames.isEmpty) return false;

      // Calculate FPS from average frame duration
      final avgDurationMs = totalDuration.inMilliseconds / frameCount;
      final fps = avgDurationMs > 0
          ? (1000 / avgDurationMs).clamp(1.0, 120.0)
          : 24.0;

      _metadata = AnimationMetadata(
        frameCount: frameCount,
        fps: fps,
        totalDuration: totalDuration,
        width: width,
        height: height,
        hasAlpha: true, // WebP and GIF can have alpha
      );

      _frames = frames;
      return true;
    } catch (e) {
      print('Native codec decoding failed: $e');
      return false;
    }
  }

  /// Get media information using FFprobe
  Future<AnimationMetadata?> _getMediaInfo(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final info = session.getMediaInformation();
      if (info == null) return null;

      final streams = info.getStreams();
      if (streams.isEmpty) return null;

      // Find video stream
      final videoStream = streams.firstWhere(
        (s) => s.getType() == 'video',
        orElse: () => streams.first,
      );

      final width = videoStream.getWidth() ?? 512;
      final height = videoStream.getHeight() ?? 512;

      // Parse frame rate
      final fpsStr =
          videoStream.getRealFrameRate() ??
          videoStream.getAverageFrameRate() ??
          '24/1';
      double fps = 24.0;
      if (fpsStr.contains('/')) {
        final parts = fpsStr.split('/');
        if (parts.length == 2) {
          final num = double.tryParse(parts[0]) ?? 24;
          final den = double.tryParse(parts[1]) ?? 1;
          fps = den > 0 ? num / den : 24;
        }
      } else {
        fps = double.tryParse(fpsStr) ?? 24;
      }
      // Clamp fps to reasonable range
      fps = fps.clamp(1.0, 120.0);

      // Get duration
      final durationStr = info.getDuration() ?? '0';
      final durationSec = double.tryParse(durationStr) ?? 0;
      final duration = Duration(microseconds: (durationSec * 1000000).round());

      // Estimate frame count
      final frameCount = (durationSec * fps).ceil().clamp(1, 10000);

      // Check for alpha channel (common in WebP, GIF, PNG)
      final extension = inputPath.toLowerCase().split('.').last;
      final codecName = videoStream.getCodec()?.toLowerCase() ?? '';
      final hasAlpha =
          ['webp', 'gif', 'png', 'apng'].contains(extension) ||
          codecName.contains('vp8') ||
          codecName.contains('vp9');

      return AnimationMetadata(
        frameCount: frameCount,
        fps: fps,
        totalDuration: duration,
        width: width,
        height: height,
        hasAlpha: hasAlpha,
      );
    } catch (e) {
      print('Error getting media info: $e');
      return null;
    }
  }

  /// Extract frames using FFmpeg with alpha preservation
  Future<bool> _extractFrames(String inputPath) async {
    final outputPattern = '$_framesDir/frame_%05d.png';
    final extension = inputPath.toLowerCase().split('.').last;

    // For animated WebP, FFmpeg's default decoder doesn't support ANIM chunks
    // We need to convert to an intermediate format first
    if (extension == 'webp') {
      return await _extractFramesFromAnimatedWebP(inputPath, outputPattern);
    }

    // For GIF and video, use standard extraction
    final arguments = [
      '-y',
      '-i',
      inputPath,
      '-vf',
      'format=rgba',
      '-pix_fmt',
      'rgba',
      outputPattern,
    ];

    final session = await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      print('FFmpeg frame extraction failed: ${await session.getOutput()}');
      return false;
    }

    return true;
  }

  /// Extract frames from animated WebP using intermediate GIF conversion
  /// FFmpeg's webp decoder doesn't support ANIM/ANMF chunks, but the webp_anim
  /// encoder can convert animated WebP to GIF which we can then extract from
  Future<bool> _extractFramesFromAnimatedWebP(
    String inputPath,
    String outputPattern,
  ) async {
    // First, try using libwebp demuxer with explicit format
    // This uses FFmpeg's ability to convert animated WebP to other formats
    final gifPath = '$_framesDir/temp_conversion.gif';

    // Convert animated WebP to GIF first (FFmpeg can do this conversion)
    final convertArgs = [
      '-y',
      '-f',
      'webp_pipe', // Force webp pipe demuxer which handles animation
      '-i',
      inputPath,
      '-vf',
      'split[s0][s1];[s0]palettegen=reserve_transparent=on:transparency_color=ffffff[p];[s1][p]paletteuse=alpha_threshold=128',
      '-loop',
      '0',
      gifPath,
    ];

    var session = await FFmpegKit.executeWithArguments(convertArgs);
    var returnCode = await session.getReturnCode();

    // If webp_pipe didn't work, try with image2 demuxer
    if (!ReturnCode.isSuccess(returnCode)) {
      print(
        'webp_pipe conversion failed, trying alternative: ${await session.getOutput()}',
      );

      // Alternative: use image2 with -c:v libwebp
      final altConvertArgs = [
        '-y',
        '-c:v',
        'libwebp',
        '-i',
        inputPath,
        '-vf',
        'split[s0][s1];[s0]palettegen=reserve_transparent=on:transparency_color=ffffff[p];[s1][p]paletteuse=alpha_threshold=128',
        '-loop',
        '0',
        gifPath,
      ];

      session = await FFmpegKit.executeWithArguments(altConvertArgs);
      returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        print(
          'Alternative conversion also failed: ${await session.getOutput()}',
        );
        // Last resort: try direct input without format hints
        final lastResortArgs = [
          '-y',
          '-i',
          inputPath,
          gifPath,
        ];
        session = await FFmpegKit.executeWithArguments(lastResortArgs);
        returnCode = await session.getReturnCode();

        if (!ReturnCode.isSuccess(returnCode)) {
          print('All WebP conversion attempts failed');
          return false;
        }
      }
    }

    // Check if GIF was created
    final gifFile = File(gifPath);
    if (!await gifFile.exists()) {
      print('GIF conversion file not created');
      return false;
    }

    // Now extract frames from the GIF
    final extractArgs = [
      '-y',
      '-i',
      gifPath,
      '-vf',
      'format=rgba',
      '-pix_fmt',
      'rgba',
      outputPattern,
    ];

    session = await FFmpegKit.executeWithArguments(extractArgs);
    returnCode = await session.getReturnCode();

    // Clean up intermediate GIF
    try {
      await gifFile.delete();
    } catch (_) {}

    if (!ReturnCode.isSuccess(returnCode)) {
      print(
        'FFmpeg frame extraction from GIF failed: ${await session.getOutput()}',
      );
      return false;
    }

    return true;
  }

  /// Load extracted frame files into memory as ui.Image objects
  Future<List<DecodedFrame>?> _loadFrames() async {
    if (_framesDir == null || _metadata == null) return null;

    final dir = Directory(_framesDir!);
    if (!await dir.exists()) return null;

    final files = await dir
        .list()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) return null;

    final frames = <DecodedFrame>[];
    final frameDuration = _metadata!.frameDuration;

    for (int i = 0; i < files.length; i++) {
      try {
        final file = File(files[i].path);
        final bytes = await file.readAsBytes();
        final image = await _decodeImage(bytes);

        if (image != null) {
          frames.add(
            DecodedFrame(
              image: image,
              frameIndex: i,
              timestamp: frameDuration * i,
              duration: frameDuration,
            ),
          );
        }

        // Update progress (0.5 to 1.0 range)
        _progressController.add(0.5 + (0.5 * (i + 1) / files.length));
      } catch (e) {
        print('Error loading frame ${files[i].path}: $e');
      }
    }

    // Update metadata with actual frame count
    if (frames.isNotEmpty && frames.length != _metadata!.frameCount) {
      _metadata = AnimationMetadata(
        frameCount: frames.length,
        fps: _metadata!.fps,
        totalDuration: frameDuration * frames.length,
        width: _metadata!.width,
        height: _metadata!.height,
        hasAlpha: _metadata!.hasAlpha,
      );
    }

    return frames;
  }

  /// Decode PNG bytes into a ui.Image
  Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } catch (e) {
      print('Error decoding image: $e');
      return null;
    }
  }

  /// Get a specific frame by index
  DecodedFrame? getFrame(int index) {
    if (_frames == null || index < 0 || index >= _frames!.length) {
      return null;
    }
    return _frames![index];
  }

  /// Get frame at a specific timestamp
  DecodedFrame? getFrameAtTime(Duration time) {
    if (_frames == null || _frames!.isEmpty || _metadata == null) {
      return null;
    }

    final frameIndex =
        (time.inMicroseconds / _metadata!.frameDuration.inMicroseconds)
            .floor()
            .clamp(0, _frames!.length - 1);
    return _frames![frameIndex];
  }

  /// Get frames within a time range (for trimming)
  List<DecodedFrame> getFramesInRange(Duration start, Duration end) {
    if (_frames == null || _frames!.isEmpty || _metadata == null) {
      return [];
    }

    final startIndex =
        (start.inMicroseconds / _metadata!.frameDuration.inMicroseconds)
            .floor()
            .clamp(0, _frames!.length - 1);
    final endIndex =
        (end.inMicroseconds / _metadata!.frameDuration.inMicroseconds)
            .ceil()
            .clamp(0, _frames!.length);

    return _frames!.sublist(startIndex, endIndex);
  }

  /// Clean up temporary files and resources
  Future<void> dispose() async {
    _progressController.close();

    // Dispose frame images only if ownership wasn't transferred
    if (_frames != null && !_ownershipTransferred) {
      for (final frame in _frames!) {
        frame.image.dispose();
      }
    }
    _frames = null;

    // Delete temporary directory
    if (_framesDir != null) {
      try {
        final dir = Directory(_framesDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        print('Error cleaning up frames directory: $e');
      }
      _framesDir = null;
    }

    _metadata = null;
  }
}
