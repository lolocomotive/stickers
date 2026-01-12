import 'dart:async';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_video/statistics.dart';

import 'common.dart';

class OverlayAndEncodeService {
  // A stream controller to expose a single, unified progress stream.
  final _progressController = StreamController<Progress>.broadcast();

  Stream<Progress> get progressStream => _progressController.stream;
  FFmpegSession? _session;

  Future<void> start({
    required String videoFile,
    required String overlayFile,
    required String outputFile,
    required WebPConfig config,
    required int fps,
    double speed = 1.0,
  }) async {
    double duration = 0;
    try {
      final mediaInfoSession = await FFprobeKit.getMediaInformation(videoFile);
      final mediaInfo = mediaInfoSession.getMediaInformation();
      final durationStr = mediaInfo?.getDuration();
      if (durationStr != null) {
        duration = double.tryParse(durationStr) ?? 0;
      }
    } catch (e) {
      print("Error getting media info: $e");
    }

    // Use setpts to adjust speed (duration), then fps to resample (reducing frame count if speeding up)
    // Scale and Pad should happen after to ensure consistent output size
    // Note: setpts must handle potentially weird timestamps, but usually PTS/speed works.
    final filterComplex = '[0:v]setpts=PTS/${speed.toStringAsFixed(4)},fps=$fps,scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2:color=0x00000000[base];[base][1:v]overlay=0:0';

    final arguments = [
      '-y',
      '-i', videoFile,
      '-i', overlayFile,
      '-filter_complex', filterComplex,
      '-c:v', 'libwebp',
      '-pix_fmt', 'yuva420p',
      '-loop', '0',
      '-an',
    ];

    if (config.lossless == true) {
      arguments.addAll(['-lossless', '1']);
    }

    if (config.quality != null) {
      arguments.addAll(['-q:v', '${config.quality}']);
    }

    if (config.method != null) {
      arguments.addAll(['-compression_level', '${config.method}']);
    }

    if (config.imageHint != null) {
      arguments.add('-preset');
      switch (config.imageHint!) {
        case WebPImageHint.picture:
        case WebPImageHint.photo:
          arguments.add('picture');
          break;
        case WebPImageHint.graph:
          arguments.add('drawing');
          break;
        default:
          arguments.add('default');
      }
    }

    arguments.add(outputFile);

    _progressController.add(Progress(status: Status.running, progress: 0.0));

    _session = await FFmpegKit.executeWithArgumentsAsync(
        arguments,
        (FFmpegSession session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            _progressController.add(Progress(status: Status.success, progress: 1.0));
          } else if (ReturnCode.isCancel(returnCode)) {
            _progressController.add(Progress(status: Status.cancelled, progress: 0.0));
          } else {
            print("FFmpeg overlay failed with rc $returnCode");
            print(await session.getOutput());
            _progressController.add(Progress(status: Status.failed));
          }
        },
        null, // Log callback
        (Statistics statistics) {
          final time = statistics.getTime();
          double progress = 0;
          if (duration > 0 && time > 0) {
            progress = (time / 1000.0) / duration;
          }
          if (progress > 1.0) progress = 1.0;
          _progressController.add(Progress(
              status: Status.running,
              progress: progress,
              currentFrame: statistics.getVideoFrameNumber(),
          ));
        }
    );
  }

  Future<void> cancel() async {
    _session?.cancel();
  }

  void dispose() {
    _progressController.close();
  }
}
