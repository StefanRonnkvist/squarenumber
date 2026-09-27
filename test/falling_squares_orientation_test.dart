import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/features/game/models/falling_square.dart';
import 'package:squarenumber/features/game/widgets/falling_squares_area.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Finder findSquarePositioned() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is Positioned &&
          widget.left != null &&
          widget.top != null &&
          widget.child is MouseRegion,
      description: 'square positioned widget',
    );
  }

  double squareSizeForAreaWidth({
    required double areaWidth,
    required double preferredSize,
  }) {
    return min(preferredSize, areaWidth / 5);
  }

  testWidgets('game board does not scroll on a small surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: 120,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('keeps paused board aligned after orientation change', (
    tester,
  ) async {
    const preferredSize = 120.0;
    const oldSurface = Size(300, 700);
    const newSurface = Size(700, 300);

    await tester.binding.setSurfaceSize(oldSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: preferredSize,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final beforeFinder = findSquarePositioned();
    expect(beforeFinder, findsOneWidget);

    final beforePos = tester.widget<Positioned>(beforeFinder);
    final beforeSquareGesture = find.descendant(
      of: beforeFinder,
      matching: find.byType(GestureDetector),
    );

    final beforeLeft = beforePos.left!;
    final beforeTop = beforePos.top!;
    final beforeSize = tester.getSize(beforeSquareGesture).width;

    await tester.binding.setSurfaceSize(newSurface);
    await tester.pump();
    await tester.pump();

    final afterFinder = findSquarePositioned();
    expect(afterFinder, findsOneWidget);

    final afterPos = tester.widget<Positioned>(afterFinder);
    final afterSquareGesture = find.descendant(
      of: afterFinder,
      matching: find.byType(GestureDetector),
    );

    final afterLeft = afterPos.left!;
    final afterTop = afterPos.top!;
    final afterSize = tester.getSize(afterSquareGesture).width;
    final scale = afterSize / beforeSize;

    expect(afterSize, closeTo(preferredSize, 0.001));
    expect(afterLeft, closeTo(beforeLeft * scale, 0.001));
    expect(afterTop, closeTo(beforeTop * scale, 0.001));
  });

  testWidgets(
    'keeps paused square grid position after orientation/size change',
    (tester) async {
      const preferredSize = 120.0;
      const oldSurface = Size(300, 700);
      const newSurface = Size(700, 300);
      double reportedAreaWidth = 0;

      await tester.binding.setSurfaceSize(oldSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FallingSquaresArea(
              speedMultiplier: 1,
              minNumber: 1,
              maxNumber: 20,
              preferredSquareSize: preferredSize,
              onAreaWidthChanged: (value) {
                reportedAreaWidth = value;
              },
            ),
          ),
        ),
      );

      // Allow post-frame spawn of the initial square while paused.
      await tester.pump();
      await tester.pump();

      final beforeFinder = findSquarePositioned();
      expect(beforeFinder, findsOneWidget);

      final beforePos = tester.widget<Positioned>(beforeFinder);
      final beforeSquareGesture = find.descendant(
        of: beforeFinder,
        matching: find.byType(GestureDetector),
      );

      final beforeLeft = beforePos.left!;
      final beforeTop = beforePos.top!;
      final beforeSize = tester.getSize(beforeSquareGesture).width;
      final beforeAreaWidth = reportedAreaWidth;

      final oldSquareSize = squareSizeForAreaWidth(
        areaWidth: beforeAreaWidth,
        preferredSize: preferredSize,
      );

      expect(beforeSize, closeTo(oldSquareSize, 0.001));

      await tester.binding.setSurfaceSize(newSurface);
      await tester.pump();
      await tester.pump();

      final afterFinder = findSquarePositioned();
      expect(afterFinder, findsOneWidget);

      final afterPos = tester.widget<Positioned>(afterFinder);
      final afterSquareGesture = find.descendant(
        of: afterFinder,
        matching: find.byType(GestureDetector),
      );

      final afterLeft = afterPos.left!;
      final afterTop = afterPos.top!;
      final afterSize = tester.getSize(afterSquareGesture).width;
      final scale = afterSize / beforeSize;

      expect(afterSize, closeTo(preferredSize, 0.001));
      expect(afterLeft, closeTo(beforeLeft * scale, 0.001));
      expect(afterTop, closeTo(beforeTop * scale, 0.001));
    },
  );

  testWidgets(
    'keeps square grid position after running then manual pause and orientation change',
    (tester) async {
      const preferredSize = 120.0;
      const oldSurface = Size(300, 700);
      const newSurface = Size(700, 300);
      double reportedAreaWidth = 0;

      await tester.binding.setSurfaceSize(oldSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FallingSquaresArea(
              speedMultiplier: 1,
              minNumber: 1,
              maxNumber: 20,
              preferredSquareSize: preferredSize,
              onAreaWidthChanged: (value) {
                reportedAreaWidth = value;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      final runningFinder = findSquarePositioned();
      expect(runningFinder, findsOneWidget);

      final beforePos = tester.widget<Positioned>(runningFinder);
      final beforeSquareGesture = find.descendant(
        of: runningFinder,
        matching: find.byType(GestureDetector),
      );

      final beforeLeft = beforePos.left!;
      final beforeTop = beforePos.top!;
      final beforeSize = tester.getSize(beforeSquareGesture).width;
      final beforeAreaWidth = reportedAreaWidth;

      final oldSquareSize = squareSizeForAreaWidth(
        areaWidth: beforeAreaWidth,
        preferredSize: preferredSize,
      );

      expect(beforeSize, closeTo(oldSquareSize, 0.001));

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      await tester.binding.setSurfaceSize(newSurface);
      await tester.pump();
      await tester.pump();

      final afterFinder = findSquarePositioned();
      expect(afterFinder, findsOneWidget);

      final afterPos = tester.widget<Positioned>(afterFinder);
      final afterSquareGesture = find.descendant(
        of: afterFinder,
        matching: find.byType(GestureDetector),
      );

      final afterLeft = afterPos.left!;
      final afterTop = afterPos.top!;
      final afterSize = tester.getSize(afterSquareGesture).width;
      final scale = afterSize / beforeSize;

      expect(afterSize, closeTo(preferredSize, 0.001));
      expect(afterLeft, closeTo(beforeLeft * scale, 0.001));
      expect(afterTop, closeTo(beforeTop * scale, 0.001));
    },
  );

  testWidgets('keeps squares aligned and falling after pause and resize', (
    tester,
  ) async {
    const preferredSize = 120.0;
    const oldSurface = Size(300, 700);
    const newSurface = Size(700, 700);

    await tester.binding.setSurfaceSize(oldSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: preferredSize,
            disableSpawning: true,
            initialSquaresBuilder: (squareSize) => [
              FallingSquare(
                x: squareSize,
                y: -squareSize,
                size: squareSize,
                color: Colors.blue,
                speed: 80,
                number: 1,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 32));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    await tester.binding.setSurfaceSize(newSurface);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    final resumedFinder = findSquarePositioned();
    final resumedPosition = tester.widget<Positioned>(resumedFinder);
    final resumedGesture = find.descendant(
      of: resumedFinder,
      matching: find.byType(GestureDetector),
    );
    final resumedTop = resumedPosition.top!;

    expect(tester.getSize(resumedGesture).width, closeTo(preferredSize, 0.001));
    expect(resumedPosition.left! % preferredSize, closeTo(0, 0.001));

    await tester.pump(const Duration(milliseconds: 32));

    final fallingPosition = tester.widget<Positioned>(findSquarePositioned());
    expect(fallingPosition.top!, greaterThan(resumedTop));
  });
}
