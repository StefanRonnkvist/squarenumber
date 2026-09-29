import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squarenumber/features/settings/widgets/settings_tab.dart';

void main() {
  testWidgets('information tab shows AAB and MSIX versions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(
            speedMultiplier: 0.6,
            currentScore: 1,
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

    DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    ).animateTo(2);
    await tester.pump();
    await tester.pump(kTabScrollDuration);

    expect(find.text('AAB version'), findsOneWidget);
    expect(find.text('0.1.54+55'), findsOneWidget);
    expect(find.text('MSIX version'), findsOneWidget);
    expect(find.text('0.1.54.55'), findsOneWidget);
  });
}
