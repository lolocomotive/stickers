import 'dart:async';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_video/statistics.dart';

import 'common.dart';

class CropAndScaleService {
  // A stream controller to expose a single, unified progress stream
  final _progressController = StreamController<Progress>.broadcast();
  Stream<Progress> get progressStream => _progressController.stream;
  FFmpegSession? _session;

  Future<void> start({
    required String inputFile,
    required String outputFile,
    required Duration start,
    required Duration end,
    double?
    fps, // Optional: if provided, used to calculate frame-accurate end time
  }) async {
    // Use microseconds for maximum precision
    final startSec = start.inMicroseconds / 1000000.0;

    // FFmpeg's trim filter 'end' parameter is EXCLUSIVE - it stops BEFORE reaching the end time.
    // When the user selects a range that includes frame at time T, they expect that frame to be
    // included. To fix this, we add a small buffer (half a frame duration) to the end time.
    // This ensures the final frame is included without accidentally including an extra frame.
    double endSec = end.inMicroseconds / 1000000.0;

    // Add half a frame duration as buffer to ensure the end frame is included
    // Default to 24fps if fps not provided (this gives ~0.021s buffer)
    final frameDuration = 1.0 / (fps ?? 24.0);
    final endSecAdjusted = endSec + (frameDuration * 0.5);

    final duration = endSecAdjusted - startSec;

    // Use high precision formatting for timestamps (6 decimal places = microsecond precision)
    final startStr = startSec.toStringAsFixed(6);
    final endStr = endSecAdjusted.toStringAsFixed(6);

    // Use executeWithArguments to handle paths with spaces correctly
    // Use filter complex for accurate trimming of short durations
    // Note: 'trim' and 'atrim' filters are frame-accurate unlike -ss/-to before/after -i which can be imprecise
    final arguments = [
      '-y',
      '-i', inputFile,
      '-c:v', 'mpeg4', // use mpeg4 which is always available
      // Video filter: trim -> reset PTS -> scale
      // trunc(iw/2)*2 ensures compatible dimensions
      '-vf',
      'trim=start=$startStr:end=$endStr,setpts=PTS-STARTPTS,scale=trunc(iw/2)*2:trunc(ih/2)*2',
      // Audio filter: atrim -> reset PTS
      '-af', 'atrim=start=$startStr:end=$endStr,asetpts=PTS-STARTPTS',
      '-pix_fmt', 'yuv420p',
      '-q:v', '4',
      '-c:a', 'aac',
      outputFile,
    ];

    _progressController.add(Progress(status: Status.running, progress: 0.0));

    _session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (FFmpegSession session) async {
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          _progressController.add(
            Progress(status: Status.success, progress: 1.0),
          );
        } else if (ReturnCode.isCancel(returnCode)) {
          _progressController.add(
            Progress(status: Status.cancelled, progress: 0.0),
          );
        } else {
          print("FFmpeg failed with rc $returnCode");
          print(await session.getOutput());
          _progressController.add(
            Progress(status: Status.failed, progress: 0.0),
          );
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
        _progressController.add(
          Progress(status: Status.running, progress: progress),
        );
      },
    );
  }

  Future<void> cancel() async {
    _session?.cancel();
  }

  void dispose() {
    _progressController.close();
  }
}
