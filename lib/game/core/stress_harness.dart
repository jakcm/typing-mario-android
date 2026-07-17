import 'dart:math';

import 'package:flame/components.dart';

import '../typing_mario_game.dart';

enum AudioCoverage { disabled }

class StressSample {
  const StressSample({
    required this.update,
    required this.simulatedSeconds,
    required this.score,
    required this.activeTargets,
    required this.detachedTracked,
    required this.componentTotal,
    required this.obstacles,
    required this.coins,
    required this.platforms,
    required this.gaps,
    required this.powerups,
    required this.usedLetters,
    required this.terrainSegments,
    required this.coinEffects,
    required this.pendingEvents,
    required this.rssBytes,
  });

  final int update;
  final double simulatedSeconds;
  final int score;
  final int activeTargets;
  final int detachedTracked;
  final int componentTotal;
  final int obstacles;
  final int coins;
  final int platforms;
  final int gaps;
  final int powerups;
  final int usedLetters;
  final int terrainSegments;
  final int coinEffects;
  final int pendingEvents;
  final int rssBytes;
}

class FormalGameStressResult {
  const FormalGameStressResult({
    required this.targetScore,
    required this.finalScore,
    required this.obstaclesMatched,
    required this.updateCount,
    required this.simulatedSeconds,
    required this.spawnedByType,
    required this.maxDetachedTracked,
    required this.finalActiveTargets,
    required this.finalUsedLetters,
    required this.pendingEvents,
    required this.audioCoverage,
    required this.elapsedMicros,
    required this.samples,
    required this.warmupRssBytes,
    required this.endRssBytes,
    required this.peakRssBytes,
  });

  final String gameClass = 'TypingMarioGame';
  final int targetScore;
  final int finalScore;
  final int obstaclesMatched;
  final int updateCount;
  final double simulatedSeconds;
  final Map<String, int> spawnedByType;
  final int maxDetachedTracked;
  final int finalActiveTargets;
  final int finalUsedLetters;
  final int pendingEvents;
  final AudioCoverage audioCoverage;
  final int elapsedMicros;
  final List<StressSample> samples;
  final int warmupRssBytes;
  final int endRssBytes;
  final int peakRssBytes;

  int get rssGrowthBytes => endRssBytes - warmupRssBytes;
}

/// Host-only stress driver for the production game and real Flame component tree.
class FormalGameStressHarness {
  FormalGameStressHarness({
    this.targetScore = 700,
    this.seed = 20260717,
    this.fixedDt = 1 / 120,
    this.minimumUpdates = 3000,
    this.sampleEvery = 60,
    this.spawnIntervalScale = 0.08,
    int Function()? rssBytes,
  }) : rssBytes = rssBytes ?? _zeroRss {
    if (targetScore <= 0 || targetScore % 10 != 0) {
      throw ArgumentError.value(targetScore, 'targetScore');
    }
    if (!fixedDt.isFinite || fixedDt <= 0) {
      throw ArgumentError.value(fixedDt, 'fixedDt');
    }
    if (minimumUpdates <= 0) {
      throw ArgumentError.value(minimumUpdates, 'minimumUpdates');
    }
    if (sampleEvery <= 0) throw ArgumentError.value(sampleEvery, 'sampleEvery');
  }

  final int targetScore;
  final int seed;
  final double fixedDt;
  final int minimumUpdates;
  final int sampleEvery;
  final double spawnIntervalScale;
  final int Function() rssBytes;

  static int _zeroRss() => 0;

  Future<FormalGameStressResult> run() async {
    final stopwatch = Stopwatch()..start();
    final game = TypingMarioGame(
      random: Random(seed),
      audioEnabled: false,
      spawnIntervalScale: spawnIntervalScale,
      collisionsEnabled: false,
      hostLifecycleSnapshot: true,
    );
    game.onGameResize(Vector2(1280, 720));
    // Explicitly await formal onLoad; the idempotence guard prevents Flame's
    // root mount machinery from loading the same game twice on a host.
    await game.onLoad();
    game.onMount();
    await game.ready();

    final samples = <StressSample>[];
    var updates = 0;
    var matched = 0;
    var maxDetached = 0;
    var warmupRss = rssBytes();
    var peakRss = warmupRss;

    void capture() {
      final d = game.stressDiagnostics;
      final rss = rssBytes();
      peakRss = max(peakRss, rss);
      maxDetached = max(maxDetached, d.detachedTracked);
      int count(String type) => d.componentsByType[type] ?? 0;
      samples.add(
        StressSample(
          update: updates,
          simulatedSeconds: updates * fixedDt,
          score: game.score,
          activeTargets: d.activeTargets,
          detachedTracked: d.detachedTracked,
          componentTotal: d.componentTotal,
          obstacles: count('ObstacleSprite'),
          coins: count('FloatingCoinSprite'),
          platforms: count('PlatformSprite'),
          gaps: count('GapSprite'),
          powerups: count('PowerUpSprite'),
          usedLetters: d.usedLetters,
          terrainSegments: d.terrainSegments,
          coinEffects: d.coinEffects,
          pendingEvents: d.pendingEvents,
          rssBytes: rss,
        ),
      );
    }

    // Capture after updates, before auto-driving input, so curves include live objects.
    while (game.score < targetScore || updates < minimumUpdates) {
      game.update(fixedDt);
      updates++;
      if (updates == 240) warmupRss = rssBytes();
      if (updates % sampleEvery == 0) capture();

      if (game.score < targetScore) {
        final obstacle = game.stressObstacleTarget;
        if (obstacle != null) {
          final before = game.score;
          game.onLetterTyped(obstacle.letter);
          final delta = game.score - before;
          if (delta != 10) {
            throw StateError(
              '正式障碍输入必须仅增加 10 分，实际 delta=$delta '
              'letter=${obstacle.letter} productionMatches='
              '${game.stressDiagnostics.obstacleMatches}',
            );
          }
          matched++;
        }
      }
      // A GameWidget normally drains Flame lifecycle events between frames.
      // The host driver has no widget loop, so explicitly perform that same
      // lifecycle drain after production update/input has queued additions.
      await game.ready();
      if (updates > 30000) {
        throw StateError('未能在 30000 updates 内达到目标分数');
      }
    }

    game.stopSpawningForStress();
    // Continue the genuine update/removal path until all LetterTargets detach.
    var drainUpdates = 0;
    while (game.stressDiagnostics.activeTargets != 0 && drainUpdates < 6000) {
      game.update(fixedDt);
      await game.ready();
      updates++;
      drainUpdates++;
      if (updates % sampleEvery == 0) capture();
    }
    // Flush Flame removal queues and production detached-target cleanup.
    for (var i = 0; i < 4; i++) {
      game.update(fixedDt);
      updates++;
    }
    capture();

    final finalDiagnostics = game.stressDiagnostics;
    final endRss = rssBytes();
    peakRss = max(peakRss, endRss);
    stopwatch.stop();
    game.onRemove();

    return FormalGameStressResult(
      targetScore: targetScore,
      finalScore: game.score,
      obstaclesMatched: matched,
      updateCount: updates,
      simulatedSeconds: updates * fixedDt,
      spawnedByType: finalDiagnostics.spawnedByType,
      maxDetachedTracked: maxDetached,
      finalActiveTargets: finalDiagnostics.activeTargets,
      finalUsedLetters: finalDiagnostics.usedLetters,
      pendingEvents: finalDiagnostics.pendingEvents,
      audioCoverage: AudioCoverage.disabled,
      elapsedMicros: stopwatch.elapsedMicroseconds,
      samples: List.unmodifiable(samples),
      warmupRssBytes: warmupRss,
      endRssBytes: endRss,
      peakRssBytes: peakRss,
    );
  }
}
