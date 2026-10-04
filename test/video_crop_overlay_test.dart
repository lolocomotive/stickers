import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/widgets/video_crop_overlay.dart';

void main() {
  testWidgets('dragging a corner changes the crop while preserving a selected ratio', (tester) async {
    Rect crop = const Rect.fromLTRB(0, 0, 1, 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return VideoCropOverlay(
                    crop: crop,
                    aspectRatio: 1,
                    onChanged: (value) => setState(() => crop = value),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(VideoCropOverlay));
    await tester.dragFrom(topLeft + const Offset(4, 4), const Offset(50, 50));
    await tester.pump();

    expect(crop.left, greaterThan(0));
    expect(crop.top, greaterThan(0));
    expect(crop.width, closeTo(crop.height, .001));
    expect(crop.bottomRight, const Offset(1, 1));
  });

  testWidgets('moving a selection cannot move it outside the video', (tester) async {
    Rect crop = const Rect.fromLTRB(.2, .2, .6, .6);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return VideoCropOverlay(crop: crop, onChanged: (value) => setState(() => crop = value));
                },
              ),
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(VideoCropOverlay));
    await tester.dragFrom(topLeft + const Offset(80, 80), const Offset(200, 200));
    await tester.pump();

    expect(crop.right, closeTo(1, .001));
    expect(crop.bottom, closeTo(1, .001));
    expect(crop.width, closeTo(.4, .001));
    expect(crop.height, closeTo(.4, .001));
  });

  testWidgets('moving the crop responds to small motions without an initial dead zone', (tester) async {
    Rect crop = const Rect.fromLTRB(.2, .2, .6, .6);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return VideoCropOverlay(crop: crop, onChanged: (value) => setState(() => crop = value));
                },
              ),
            ),
          ),
        ),
      ),
    );

    final center = tester.getTopLeft(find.byType(VideoCropOverlay)) + const Offset(80, 80);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(4, 3));
    await tester.pump();
    expect(crop.left, closeTo(.22, .001));
    expect(crop.top, closeTo(.215, .001));

    await gesture.moveBy(const Offset(4, 3));
    await tester.pump();
    expect(crop.left, closeTo(.24, .001));
    expect(crop.top, closeTo(.23, .001));
    await gesture.up();
  });
}
