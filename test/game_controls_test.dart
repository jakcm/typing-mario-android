import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/screens/game_over_screen.dart';
import 'package:typing_mario_android/widgets/game_controls.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('letter keyboard is collapsed by default and expands on demand', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(OnScreenKeyboard(onLetterPressed: (_) {}, onSpacePressed: () {})),
    );

    expect(find.text('A'), findsNothing);
    expect(find.byTooltip('Expand letter keyboard'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand letter keyboard'));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('Z'), findsOneWidget);
    expect(find.byTooltip('Collapse letter keyboard'), findsOneWidget);
  });

  testWidgets('quit button invokes the supplied quit action', (
    WidgetTester tester,
  ) async {
    var quitCount = 0;

    await tester.pumpWidget(host(QuitButton(onQuit: () => quitCount++)));
    await tester.tap(find.byTooltip('Quit game'));

    expect(quitCount, 1);
  });

  testWidgets('game over screen provides a quit control', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const GameOverScreen()));

    expect(find.byTooltip('Quit game'), findsOneWidget);
  });
}
