import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/game/sprites/floating_coin.dart';
import 'package:typing_mario_android/game/sprites/obstacle_sprite.dart';
import 'package:typing_mario_android/game/typing_mario_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('speed boots slow existing targets and restore current game speed', () {
    final game = TypingMarioGame()..gameSpeed = 200;
    final obstacle = ObstacleSprite(
      letter: 'A',
      speed: 200,
      groundY: 400,
      startX: 600,
    );
    final coin = FloatingCoinSprite(
      letter: 'B',
      speed: 160,
      groundY: 400,
      startX: 600,
    );
    game.addTargetForTesting(obstacle);
    game.addTargetForTesting(coin);

    game.activateSpeedBoots();

    expect(obstacle.speed, 100);
    expect(coin.speed, 80);

    game.gameSpeed = 240;
    game.expireSpeedBootsForTesting();

    expect(obstacle.speed, 240);
    expect(coin.speed, 192);
  });
}
