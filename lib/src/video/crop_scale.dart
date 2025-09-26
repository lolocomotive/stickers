import 'dart:async';
import 'package:flutter/services.dart';

// Enums and classes to mirror the Kotlin side
enum TranscoderStatus { IDLE, RUNNING, SUCCESS, FAILED, CANCELLED }

class TranscoderProgress {
  final TranscoderStatus status;
  final double progress;
  final int currentFrame;
  final int totalFrames;

  TranscoderProgress({
    this.status = TranscoderStatus.IDLE,
    this.progress = 0.0,
    this.currentFrame = 0,
    this.totalFrames = 0,
  });
}

class CropAndScaleService {
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');
  static const _eventChannel = EventChannel('de.loicezt.stickers/events');

  // A stream controller to expose a single, unified progress stream
  final _progressController = StreamController<TranscoderProgress>.broadcast();
  Stream<TranscoderProgress> get progressStream => _progressController.stream;

  CropAndScaleService() {
    // Listen to the native event channel as soon as the service is created
    _eventChannel.receiveBroadcastStream().listen(_onProgress, onError: _onError);
  }

  void _onProgress(dynamic data) {
    if (data is Map) {
      final statusString = data['status'] as String?;
      final status = TranscoderStatus.values.firstWhere(
            (e) => e.toString() == 'TranscoderStatus.$statusString',
        orElse: () => TranscoderStatus.IDLE,
      );

      final progress = TranscoderProgress(
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
    _progressController.add(TranscoderProgress(status: TranscoderStatus.FAILED));
  }

  Future<void> start({
    required String inputFile,
    required String outputFile,
    required Duration start,
    required Duration end,
  }) async {
    try {
      await _methodChannel.invokeMethod('start', {
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
      await _methodChannel.invokeMethod('cancel');
    } on PlatformException catch (e) {
      print("Failed to cancel transcoding: '${e.message}'.");
    }
  }

  void dispose() {
    _progressController.close();
  }
}
