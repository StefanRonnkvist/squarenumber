import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/app/main_app.dart';
import 'package:squarenumber/features/game/widgets/falling_squares_area.dart';
import 'package:squarenumber/features/settings/widgets/settings_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScoreHistoryEntryData', () {
    test('round-trips current status through JSON', () {
      const entry = ScoreHistoryEntryData(
        score: 420,
        speedMultiplier: 1.2,
        layout: 'Phone',
        isCurrent: true,
      );

      final encoded = entry.toJson();
      final decoded = ScoreHistoryEntryData.fromJson(encoded);

      expect(encoded['isCurrent'], isTrue);
      expect(decoded.isCurrent, isTrue);
      expect(decoded.score, 420);
      expect(decoded.layout, 'Phone');
    });

    test('copyWith updates the current marker', () {
      const entry = ScoreHistoryEntryData(
        score: 240,
        speedMultiplier: 0.8,
        layout: 'Desktop',
      );

      final updated = entry.copyWith(isCurrent: true);

      expect(updated.isCurrent, isTrue);
      expect(updated.score, 240);
      expect(updated.layout, 'Desktop');
    });

    testWidgets('loads a persisted best score from SharedPreferences', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'best_score': 420});

      await tester.pumpWidget(const MaterialApp(home: MainApp()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Highest score: 420'), findsOneWidget);
    });

    testWidgets('shows persisted score history on a phone layout', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'score_history': [
          jsonEncode(
            const ScoreHistoryEntryData(
              score: 420,
              speedMultiplier: 1.2,
              layout: 'Phone',
            ).toJson(),
          ),
        ],
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Score History'));
      await tester.pumpAndSettle();

      expect(find.text('Top scores: 1/10'), findsOneWidget);
      expect(find.text('Score: 420'), findsOneWidget);
    });

    testWidgets('persists a completed phone game across an app restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      final game = tester.widget<FallingSquaresArea>(
        find.byType(FallingSquaresArea),
      );
      game.onScoreChanged?.call(420);
      await tester.pump();
      game.onGameCompleted?.call(420);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Score History'));
      await tester.pumpAndSettle();

      expect(find.text('Top scores: 1/10'), findsOneWidget);
      expect(find.text('Score: 420'), findsOneWidget);
    });
  });
}
