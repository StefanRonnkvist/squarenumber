import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/app/main_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('status chip text uses an explicit readable color', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: MainApp()));
    await tester.pumpAndSettle();

    final scoreText = tester.widget<Text>(find.textContaining('Score:'));
    expect(scoreText.style?.color, isNotNull);
    expect(scoreText.style?.color, isNot(Colors.black));
  });
}
