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

  List<FallingSquare> buildSequentialSquares({
    required int count,
    required double squareSize,
  }) {
    return List<FallingSquare>.generate(count, (index) {
      return FallingSquare(
        x: index * squareSize,
        y: 0,
        size: squareSize,
        color: Colors.black,
        speed: 0,
        number: index + 1,
        landed: true,
        placed: true,
      );
    });
  }

  List<FallingSquare> buildCustomSequence({
    required List<int> numbers,
    required double squareSize,
    double y = 0,
  }) {
    return List<FallingSquare>.generate(numbers.length, (index) {
      return FallingSquare(
        x: index * squareSize,
        y: y,
        size: squareSize,
        color: Colors.black,
        speed: 0,
        number: numbers[index],
        landed: true,
        placed: true,
      );
    });
  }

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

  testWidgets('sequential groups of 2 do not clear', (tester) async {
    int latestScore = -1;

    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: 90,
            disableSpawning: true,
            initialSquaresBuilder: (squareSize) =>
                buildSequentialSquares(count: 2, squareSize: squareSize),
            onScoreChanged: (score) {
              latestScore = score;
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(findSquarePositioned(), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(findSquarePositioned(), findsNWidgets(2));
    expect(latestScore, anyOf(equals(-1), equals(0)));
  });

  testWidgets('sequential groups of 3 clear and score', (tester) async {
    int latestScore = -1;
    final completedScores = <int>[];

    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: 90,
            disableSpawning: true,
            initialSquaresBuilder: (squareSize) =>
                buildSequentialSquares(count: 3, squareSize: squareSize),
            onScoreChanged: (score) {
              latestScore = score;
            },
            onGameCompleted: completedScores.add,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(findSquarePositioned(), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(findSquarePositioned(), findsNothing);
    expect(latestScore, equals(18));

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(completedScores, equals([18]));
    expect(latestScore, equals(0));
  });

  testWidgets('sequential groups with duplicate numbers do not clear', (
    tester,
  ) async {
    int latestScore = -1;

    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: 90,
            disableSpawning: true,
            initialSquaresBuilder: (squareSize) => buildCustomSequence(
              numbers: [1, 2, 3, 2],
              squareSize: squareSize,
            ),
            onScoreChanged: (score) {
              latestScore = score;
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(findSquarePositioned(), findsNWidgets(4));

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Should not clear because of duplicate number 2
    expect(findSquarePositioned(), findsNWidgets(4));
    expect(latestScore, anyOf(equals(-1), equals(0)));
  });

  testWidgets('duplicates and sequences clear before the next square spawns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallingSquaresArea(
            speedMultiplier: 1,
            minNumber: 1,
            maxNumber: 20,
            preferredSquareSize: 90,
            initialSquaresBuilder: (squareSize) => buildCustomSequence(
              numbers: const [4, 4, 1, 2, 3],
              squareSize: squareSize,
              y: 590 - squareSize,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(findSquarePositioned(), findsNWidgets(5));

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(findSquarePositioned(), findsNothing);
  });
}
