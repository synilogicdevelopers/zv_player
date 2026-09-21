import 'package:zv_player/src/ui/zv_player_theme.dart';
import 'package:zv_player/src/widgets/zv_player_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<SeekSide> seeks;
  late int taps;

  Future<void> pumpLayer(WidgetTester tester, {bool enabled = true}) async {
    seeks = <SeekSide>[];
    taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZvPlayerThemeScope(
            theme: ZvPlayerTheme.standard,
            child: ZvPlayerGestureLayer(
              onTap: () => taps++,
              onSeek: seeks.add,
              seekStep: const Duration(seconds: 10),
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
  }

  /// Screen halves: left is rewind, right is fast-forward.
  Offset leftHalf(WidgetTester tester) {
    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    return Offset(size.width * 0.25, size.height * 0.5);
  }

  Offset rightHalf(WidgetTester tester) {
    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    return Offset(size.width * 0.75, size.height * 0.5);
  }

  testWidgets('a single tap toggles controls without seeking', (tester) async {
    await pumpLayer(tester);
    await tester.tapAt(rightHalf(tester));
    // Let the double-tap window lapse so the tap is not held as a candidate.
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, 1);
    expect(seeks, isEmpty);
  });

  testWidgets('double tap on the right half seeks forward', (tester) async {
    await pumpLayer(tester);
    final Offset target = rightHalf(tester);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 400));

    expect(seeks, <SeekSide>[SeekSide.forward]);
  });

  testWidgets('double tap on the left half seeks backward', (tester) async {
    await pumpLayer(tester);
    final Offset target = leftHalf(tester);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 400));

    expect(seeks, <SeekSide>[SeekSide.backward]);
  });

  testWidgets('repeated double taps accumulate on the same side',
      (tester) async {
    await pumpLayer(tester);
    final Offset target = rightHalf(tester);
    for (int i = 0; i < 2; i++) {
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(seeks, <SeekSide>[SeekSide.forward, SeekSide.forward]);
    // The indicator shows the running total, not a fixed 10s.
    expect(find.text('+20'), findsOneWidget);
  });

  testWidgets('seeking is refused when the source cannot be seeked',
      (tester) async {
    await pumpLayer(tester, enabled: false);
    final Offset target = rightHalf(tester);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 400));

    expect(seeks, isEmpty);
  });

  testWidgets('a single tap still toggles controls on a live stream',
      (tester) async {
    await pumpLayer(tester, enabled: false);
    await tester.tapAt(rightHalf(tester));
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, 1);
    expect(seeks, isEmpty);
  });

  testWidgets('disposing without ever double-tapping does not throw',
      (tester) async {
    await pumpLayer(tester);
    // Replaces the gesture layer, disposing it untouched.
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
