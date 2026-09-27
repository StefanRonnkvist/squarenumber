import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/app/main_app.dart';
import 'package:squarenumber/features/game/widgets/falling_squares_area.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop game play area uses most of the window height', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MainApp());
    await tester.pump();

    final playAreaHeight = tester
        .getSize(find.byType(FallingSquaresArea))
        .height;

    expect(playAreaHeight, greaterThan(750));
  });
}
