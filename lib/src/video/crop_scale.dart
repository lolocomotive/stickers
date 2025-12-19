import 'dart:async';

import 'package:flutter/services.dart';

import 'common.dart';

class CropAndScaleService {
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');
  static const _eventChannel = EventChannel('de.loicezt.stickers/progress_trim');

  // A stream controller to expose a single, unified progress stream
  final _progressController = StreamController<Progress>.broadcast();

  Stream<Progress> get progressStream => _progressController.stream;

  CropAndScaleService() {
    // Listen to the native event channel as soon as the service is created
    _eventChannel.receiveBroadcastStream().listen(_onProgress, onError: _onError);
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
      _progressController.add(progress);
    }
  }

  void _onError(Object error) {
    print("Error on EventChannel: $error");
    _progressController.add(Progress(status: Status.FAILED));
  }

  Future<void> start({
    required String inputFile,
    required String outputFile,
    required Duration start,
    required Duration end,
  }) async {
    try {
      await _methodChannel.invokeMethod('startTrim', {
        'inputFile': inputFile,
        'outputFile': outputFile,
        'startTimeUs': start.inMicroseconds.toString(),
        'endTimeUs': end.inMicroseconds.toString(),
      });
    } on PlatformException catch (e) {
      print("Failed to start transcoding: '${e.message}'.");
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
    _progressController.close();
  }
}
