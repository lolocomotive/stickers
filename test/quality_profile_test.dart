import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/video/quality_profile.dart';

void main() {
  test('presets are ordered by quality', () {
    final max = QualityProfile.of(QualityPreset.max);
    final small = QualityProfile.of(QualityPreset.small);
    expect(max.quality, greaterThan(small.quality));
    expect(max.fps, greaterThan(small.fps));
  });

  test('custom uses the given values', () {
    const c = QualityProfile(quality: 33, fps: 12, method: 2);
    expect(QualityProfile.of(QualityPreset.custom, custom: c).fps, 12);
  });

  test('auto matches the historical defaults', () {
    final a = QualityProfile.of(QualityPreset.auto);
    expect((a.quality, a.fps, a.method), (60.0, 24, 4));
  });
}
