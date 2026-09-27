import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squarenumber/features/settings/widgets/settings_tab.dart';

void main() {
  testWidgets('help tab explains current gameplay and saved runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(
            speedMultiplier: 0.6,
            currentScore: 0,
            minNumber: 1,
            maxNumber: 20,
            squareSize: null,
            themeMode: ThemeMode.system,
            scoreHistory: const [],
            onClearScoreHistory: () {},
            onSpeedChanged: (_) {},
            onMinNumberChanged: (_) {},
            onMaxNumberChanged: (_) {},
            onSquareSizeChanged: (_) {},
            onThemeModeChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('How to Play'), findsOneWidget);
    expect(find.text('Move the active square'), findsOneWidget);
    expect(find.text('Make a clear'), findsOneWidget);
    expect(find.text('Score and build cascades'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Track your scores'),
      find.byType(SingleChildScrollView),
      const Offset(0, -250),
    );

    expect(find.text('Pause, restore, and restart'), findsOneWidget);
    expect(find.text('Track your scores'), findsOneWidget);
    expect(find.textContaining('10 best completed runs'), findsOneWidget);
    expect(find.textContaining('appears as Current'), findsOneWidget);
    expect(find.text('Tune the game'), findsOneWidget);
  });
}
