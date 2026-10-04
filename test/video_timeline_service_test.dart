import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/video/video_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.loicezt.stickers/methods');

  test('frame navigation passes microsecond positions and direction to Android', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 1234567;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    final result = await VideoTimelineService().adjacentFrame('video.mp4', const Duration(microseconds: 1000000), -1);
    expect(received?.method, 'adjacentVideoFrame');
    expect(received?.arguments, {'inputFile': 'video.mp4', 'positionUs': 1000000, 'direction': -1});
    expect(result, const Duration(microseconds: 1234567));
  });

  test('timeline thumbnails are decoded as byte arrays', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'videoTimelineThumbnails');
      return [
        Uint8List.fromList([1, 2]),
        null,
      ];
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    final frames = await VideoTimelineService().thumbnails('video.mp4');
    expect(frames, [
      Uint8List.fromList([1, 2]),
      null,
    ]);
  });
}
