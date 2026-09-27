import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/app/main_app.dart';
import 'package:squarenumber/app/splash_screen.dart';
import 'package:squarenumber/main.dart';

void main() {
  testWidgets('shows the splash screen before launching the main app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SquareNumberBootstrap());

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(MainApp), findsNothing);

    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(MainApp), findsOneWidget);
  });
}
