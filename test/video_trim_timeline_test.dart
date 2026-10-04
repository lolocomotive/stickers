import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/video/trim_range.dart';
import 'package:stickers/src/widgets/video_trim_timeline.dart';

void main() {
  testWidgets('one filmstrip trims by its handles and scrubs when tapped inside', (tester) async {
    RangeValues? changedRange;
    Duration? soughtTime;
    TrimEdge? selectedEdge;
    final playhead = ValueNotifier(const Duration(seconds: 3));
    addTearDown(playhead.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: VideoTrimTimeline(
                duration: const Duration(seconds: 10),
                range: const RangeValues(.2, .8),
                playhead: playhead,
                thumbnails: const [],
                enabled: true,
                onRangeChangeStart: () {},
                onRangeChanged: (value) => changedRange = value,
                onRangeChangeEnd: () {},
                onSeekStart: () {},
                onSeekChanged: (value) => soughtTime = value,
                onSeekEnd: (value) => soughtTime = value,
                onEdgeSelected: (edge) => selectedEdge = edge,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0:02.000'), findsOneWidget);
    expect(find.text('0:06.000'), findsOneWidget);
    expect(find.text('0:08.000'), findsOneWidget);
    expect(tester.takeException(), isNull);

    playhead.value = const Duration(seconds: 4);
    await tester.pump();
    expect(find.text('0:04.000'), findsOneWidget);

    final timeline = tester.getRect(
      find.descendant(of: find.byType(VideoTrimTimeline), matching: find.byType(Listener)),
    );
    await tester.dragFrom(
      Offset(timeline.left + 16 + (timeline.width - 32) * .2, timeline.center.dy),
      const Offset(35, 0),
    );
    await tester.pump();
    expect(changedRange?.start, greaterThan(.2));
    expect(selectedEdge, TrimEdge.start);

    changedRange = null;
    await tester.dragFrom(
      Offset(timeline.left + 16 + (timeline.width - 32) * .8, timeline.center.dy),
      const Offset(-35, 0),
    );
    await tester.pump();
    expect(changedRange?.end, lessThan(.8));
    expect(selectedEdge, TrimEdge.end);

    changedRange = null;
    await tester.tapAt(timeline.center);
    await tester.pump();
    expect(soughtTime, isNotNull);
    expect((soughtTime! - const Duration(seconds: 5)).abs(), lessThan(const Duration(milliseconds: 20)));
    expect(changedRange, isNull);

    soughtTime = null;
    await tester.dragFrom(timeline.center, const Offset(30, 0));
    await tester.pump();
    expect(soughtTime!, greaterThan(const Duration(seconds: 5)));
    expect(changedRange, isNull);
    expect(tester.takeException(), isNull);
  });
}
