import 'package:flutter/services.dart';

class VideoTimelineService {
  static const _channel = MethodChannel('de.loicezt.stickers/methods');

  Future<List<Uint8List?>> thumbnails(String path) async {
    final frames = await _channel.invokeListMethod<dynamic>(
      'videoTimelineThumbnails',
      {'inputFile': path},
    );
    return frames?.map((frame) => frame as Uint8List?).toList() ?? [];
  }

  Future<Duration> adjacentFrame(String path, Duration position, int direction) async {
    final timeUs = await _channel.invokeMethod<int>('adjacentVideoFrame', {
      'inputFile': path,
      'positionUs': position.inMicroseconds,
      'direction': direction,
    });
    return Duration(microseconds: timeUs ?? position.inMicroseconds);
  }
}
