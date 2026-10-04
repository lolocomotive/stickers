import 'dart:async';

import 'package:flutter/services.dart';

import 'common.dart';

class CropAndScaleService {
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');
  static const _eventChannel = EventChannel('de.loicezt.stickers/progress_trim');

  // A stream controller to expose a single, unified progress stream
  final _progressController = StreamController<Progress>.broadcast();

  Stream<Progress> get progressStream => _progressController.stream;

  late final StreamSubscription<dynamic> _subscription;

  CropAndScaleService() {
    // Listen to the native event channel as soon as the service is created
    _subscription = _eventChannel.receiveBroadcastStream().listen(_onProgress, onError: _onError);
  }

  void _onProgress(dynamic data) {
    if (data is Map) {
      final statusString = data['status'] as String?;
      final status = Status.values.firstWhere(
        (e) => e.toString() == 'Status.$statusString',
        orElse: () => Status.IDLE,
      );

      final progress = Progress(
        status: status,
        progress: (data['progress'] as num?)?.toDouble() ?? 0.0,
        currentFrame: data['currentFrame'] as int? ?? 0,
        totalFrames: data['totalFrames'] as int? ?? 0,
      );
      if (!_progressController.isClosed) _progressController.add(progress);
    }
  }

  void _onError(Object error) {
    print("Error on EventChannel: $error");
    if (!_progressController.isClosed) _progressController.add(Progress(status: Status.FAILED));
  }

  Future<void> start({
    required String inputFile,
    required String outputFile,
    required Duration start,
    required Duration end,
    required Rect crop,
    required bool stretch,
    required int quarterTurns,
  }) async {
    try {
      await _methodChannel.invokeMethod('startTrim', {
        'inputFile': inputFile,
        'outputFile': outputFile,
        'startTimeUs': start.inMicroseconds.toString(),
        'endTimeUs': end.inMicroseconds.toString(),
        'cropLeft': crop.left.clamp(0.0, 1.0),
        'cropTop': crop.top.clamp(0.0, 1.0),
        'cropRight': crop.right.clamp(0.0, 1.0),
        'cropBottom': crop.bottom.clamp(0.0, 1.0),
        'stretch': stretch,
        'quarterTurns': quarterTurns,
      });
    } on PlatformException catch (e) {
      print("Failed to start transcoding: '${e.message}'.");
      rethrow;
    }
  }

  Future<void> cancel() async {
    try {
      await _methodChannel.invokeMethod('cancelTrim');
    } on PlatformException catch (e) {
      print("Failed to cancel transcoding: '${e.message}'.");
    }
  }

  void dispose() {
    _subscription.cancel();
    _progressController.close();
  }
}
