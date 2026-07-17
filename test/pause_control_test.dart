import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/game/typing_mario_game.dart';
import 'package:typing_mario_android/screens/game_screen.dart';
import 'package:typing_mario_android/widgets/game_controls.dart';

void main() {
  testWidgets('pause control changes icon and invokes toggle', (
    WidgetTester tester,
  ) async {
    var toggleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePauseButton(isPaused: false, onToggle: () => toggleCount++),
        ),
      ),
    );

    expect(find.byTooltip('Pause game'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byTooltip('Pause game'));
    expect(toggleCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePauseButton(isPaused: true, onToggle: () => toggleCount++),
        ),
      ),
    );

    expect(find.byTooltip('Resume game'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('lifecycle pause rebuilds pause control as resume', (
    tester,
  ) async {
    final game = TypingMarioGame();
    await tester.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await tester.pump();

    expect(find.byTooltip('Pause game'), findsOneWidget);

    final state = tester.state(find.byType(GameScreen)) as dynamic;
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();

    expect(game.isPaused, isTrue);
    expect(find.byTooltip('Resume game'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
