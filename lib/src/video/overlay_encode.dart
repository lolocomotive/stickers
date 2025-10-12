import 'dart:async';

import 'package:flutter/services.dart';

import 'common.dart';

class OverlayAndEncodeService {
  // The channel names must match those defined in MainActivity.kt
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');
  static const _eventChannel = EventChannel('de.loicezt.stickers/progress_encode');

  // A stream controller to expose a single, unified progress stream.
  final _progressController = StreamController<Progress>.broadcast();

  Stream<Progress> get progressStream => _progressController.stream;

  OverlayAndEncodeService() {
    // Listen to the native event channel as soon as the service is created.
    _eventChannel.receiveBroadcastStream().listen(_onProgress, onError: _onError);
  }

  /// Handles incoming data from the native EventChannel.
  void _onProgress(dynamic data) {
    if (data is Map) {
      final statusString = data['status'] as String?;

      // Safely parse the status string into an enum.
      final status = Status.values.firstWhere(
        (e) => e.name == statusString,
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

  /// Handles errors from the native EventChannel.
  void _onError(Object error) {
    // ignore: avoid_print
    print("Error on EventChannel: $error");
    _progressController.add(Progress(status: Status.FAILED));
  }

  /// Calls the native method to start the overlay and encoding process.
  Future<void> start({
    required String videoFile,
    required String overlayFile,
    required String outputFile,
    required WebPConfig config,
    required int fps,
  }) async {
    try {
      // The method name 'startOverlay' and the argument keys must match
      // what is expected in MainActivity.kt.
      await _methodChannel.invokeMethod(
        'startOverlay',
        {
          'videoFile': videoFile,
          'overlayFile': overlayFile,
          'outputFile': outputFile,
          'fps': fps,
          'config': config.toMap(),
        },
      );
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print("Failed to start overlay process: '${e.message}'.");
      _progressController.add(Progress(status: Status.FAILED));
    }
  }

  /// Calls the native method to cancel the ongoing process.
  Future<void> cancel() async {
    try {
      await _methodChannel.invokeMethod('cancel');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print("Failed to cancel overlay process: '${e.message}'.");
    }
  }

  /// Cleans up the stream controller.
  void dispose() {
    _progressController.close();
  }
}
