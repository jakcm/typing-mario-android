import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/game/core/stress_harness.dart';
import 'package:typing_mario_android/game/core/stress_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('正式 TypingMarioGame 700 分 host 压力测试', () {
    test('驱动真实 Flame 生命周期并精确达到 700 后排空', () async {
      final result = await FormalGameStressHarness(
        targetScore: 700,
        seed: 20260717,
        fixedDt: 1 / 120,
        minimumUpdates: 3000,
        rssBytes: () => ProcessInfo.currentRss,
      ).run();

      expect(result.gameClass, 'TypingMarioGame');
      expect(result.finalScore, 700);
      expect(
        result.obstaclesMatched,
        70,
        reason: 'score=${result.finalScore} spawned=${result.spawnedByType}',
      );
      expect(result.updateCount, greaterThanOrEqualTo(3000));
      expect(result.simulatedSeconds, greaterThan(25));
      expect(result.spawnedByType['ObstacleSprite'], greaterThanOrEqualTo(70));
      expect(result.spawnedByType['FloatingCoinSprite'], greaterThan(0));
      expect(result.spawnedByType['PlatformSprite'], greaterThan(0));
      expect(result.spawnedByType['GapSprite'], greaterThan(0));
      expect(result.spawnedByType['PowerUpSprite'], greaterThan(0));
      expect(result.samples.any((s) => s.activeTargets > 0), isTrue);
      expect(result.samples.any((s) => s.componentTotal > 4), isTrue);
      expect(result.samples.any((s) => s.coinEffects > 0), isTrue);
      expect(result.maxDetachedTracked, 0);
      expect(result.finalActiveTargets, 0);
      expect(result.finalUsedLetters, 0);
      expect(result.pendingEvents, 0);
      expect(result.audioCoverage, AudioCoverage.disabled);
    });

    test('报告包含可审计元数据、对象曲线和明确限制', () async {
      final directory = Directory.systemTemp.createTempSync('formal-stress-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final result = await FormalGameStressHarness(
        targetScore: 700,
        seed: 20260717,
        minimumUpdates: 3000,
      ).run();
      final metadata = StressRunMetadata(
        gitSha: 'abc123',
        gitDirty: true,
        flutterVersion: 'Flutter test',
        dartVersion: 'Dart test',
        platform: 'host-test',
        command: 'flutter test test/stress_harness_test.dart',
      );

      final outcome = StressReporter(
        directory,
        thresholds: const StressThresholds(
          maxActiveTargets: 1000,
          maxComponentTotal: 5000,
          maxRssGrowthBytes: 1 << 60,
        ),
      ).write(result, metadata);

      expect(outcome.passed, isTrue, reason: outcome.failures.join(', '));
      final csv = File('${directory.path}/metrics.csv').readAsStringSync();
      expect(csv, contains('active_targets,detached_tracked,component_total'));
      expect(csv, contains('obstacles,coins,platforms,gaps,powerups'));
      expect(csv.split('\n').length, greaterThan(10));
      final diagnostic = File(
        '${directory.path}/diagnostic.md',
      ).readAsStringSync();
      expect(diagnostic, contains('TypingMarioGame'));
      expect(diagnostic, contains('abc123'));
      expect(diagnostic, contains('dirty'));
      expect(diagnostic, contains('不覆盖原生音频'));
      expect(diagnostic, contains('预热后 RSS'));
      expect(File('${directory.path}/run.log').lengthSync(), greaterThan(100));
      expect(
        File('${directory.path}/memory_curve.svg').readAsStringSync(),
        contains('<polyline'),
      );
    });

    test('非法参数在 release 语义下也抛出 ArgumentError', () {
      expect(
        () => FormalGameStressHarness(targetScore: 701),
        throwsArgumentError,
      );
      expect(() => FormalGameStressHarness(fixedDt: 0), throwsArgumentError);
      expect(
        () => FormalGameStressHarness(minimumUpdates: 0),
        throwsArgumentError,
      );
    });
  });
}
