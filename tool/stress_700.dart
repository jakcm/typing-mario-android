import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/game/core/stress_harness.dart';
import 'package:typing_mario_android/game/core/stress_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('run formal TypingMarioGame 700 stress and write artifacts', () async {
    final output = Platform.environment['STRESS_REPORT_DIR'];
    if (output == null || output.isEmpty) {
      fail('STRESS_REPORT_DIR is required');
    }
    final directory = Directory(output).absolute;
    final result = await FormalGameStressHarness(
      targetScore: 700,
      seed: 20260717,
      fixedDt: 1 / 120,
      minimumUpdates: 3000,
      sampleEvery: 60,
      rssBytes: () => ProcessInfo.currentRss,
    ).run();
    final outcome = StressReporter(directory).write(
      result,
      StressRunMetadata(
        gitSha: Platform.environment['STRESS_GIT_SHA'] ?? 'unknown',
        gitDirty: Platform.environment['STRESS_GIT_DIRTY'] == 'true',
        flutterVersion:
            Platform.environment['STRESS_FLUTTER_VERSION'] ?? 'unknown',
        dartVersion: Platform.version.split(' ').first,
        platform:
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        command:
            Platform.environment['STRESS_COMMAND'] ??
            'flutter test tool/stress_700.dart',
      ),
    );

    stdout
      ..writeln('report=${directory.path}')
      ..writeln('score=${result.finalScore}')
      ..writeln('obstacles_matched=${result.obstaclesMatched}')
      ..writeln('updates=${result.updateCount}')
      ..writeln(
        'simulated_seconds=${result.simulatedSeconds.toStringAsFixed(2)}',
      )
      ..writeln('max_detached_tracked=${result.maxDetachedTracked}')
      ..writeln('rss_growth_bytes=${result.rssGrowthBytes}')
      ..writeln('verdict=${outcome.passed ? 'PASS' : 'FAIL'}');
    expect(outcome.passed, isTrue, reason: outcome.failures.join(', '));
  });
}
