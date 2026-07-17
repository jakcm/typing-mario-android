import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/screens/main_menu_screen.dart';
import 'package:typing_mario_android/version.dart';

void main() {
  testWidgets('start menu shows build version and no word option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MainMenuScreen()));

    expect(find.text('单词发音'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('START GAME'), findsOneWidget);
    expect(find.text('Version: $kBuildVersion'), findsOneWidget);
    expect(RegExp(r'^\d{12}$').hasMatch(kBuildVersion), isTrue);
  });
}
