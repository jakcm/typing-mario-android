import 'dart:io';

import 'stress_harness.dart';

class StressThresholds {
  const StressThresholds({
    // Accelerated spawn scale 0.08 deliberately permits a much denser screen
    // than normal play. The leak signal is unbounded growth or failed drain,
    // not exceeding the normal-play simultaneous-target count.
    this.maxActiveTargets = 64,
    this.maxDetachedTracked = 0,
    this.maxComponentTotal = 96,
    this.maxRssGrowthBytes = 96 * 1024 * 1024,
    this.maxElapsedMicros = 30 * 1000 * 1000,
  });
  final int maxActiveTargets;
  final int maxDetachedTracked;
  final int maxComponentTotal;
  final int maxRssGrowthBytes;
  final int maxElapsedMicros;
}

class StressRunMetadata {
  const StressRunMetadata({
    required this.gitSha,
    required this.gitDirty,
    required this.flutterVersion,
    required this.dartVersion,
    required this.platform,
    required this.command,
  });
  final String gitSha;
  final bool gitDirty;
  final String flutterVersion;
  final String dartVersion;
  final String platform;
  final String command;
}

class StressReportOutcome {
  const StressReportOutcome({required this.passed, required this.failures});
  final bool passed;
  final List<String> failures;
}

class StressReporter {
  StressReporter(this.directory, {this.thresholds = const StressThresholds()});
  final Directory directory;
  final StressThresholds thresholds;

  StressReportOutcome write(
    FormalGameStressResult result,
    StressRunMetadata metadata,
  ) {
    directory.createSync(recursive: true);
    final maxActive = result.samples.map((s) => s.activeTargets).reduce(maxInt);
    final maxComponents = result.samples
        .map((s) => s.componentTotal)
        .reduce(maxInt);
    final checks = <String, bool>{
      '精确 700 分': result.finalScore == result.targetScore,
      '70 个正式障碍匹配': result.obstaclesMatched == result.targetScore ~/ 10,
      '至少 3000 updates': result.updateCount >= 3000,
      'active targets 有界': maxActive <= thresholds.maxActiveTargets,
      '无 detached tracked':
          result.maxDetachedTracked <= thresholds.maxDetachedTracked,
      '组件总数有界': maxComponents <= thresholds.maxComponentTotal,
      'drain 后 target 清空':
          result.finalActiveTargets == 0 && result.finalUsedLetters == 0,
      'pending events 清空': result.pendingEvents == 0,
      '预热后 RSS 增长': result.rssGrowthBytes <= thresholds.maxRssGrowthBytes,
      'host 运行耗时': result.elapsedMicros <= thresholds.maxElapsedMicros,
    };
    final failures = checks.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();
    final passed = failures.isEmpty;
    _writeCsv(result);
    _writeSvg(result.samples);
    _writeDiagnostic(
      result,
      metadata,
      checks,
      passed,
      maxActive,
      maxComponents,
    );
    _writeLog(result, metadata, passed, failures, maxActive, maxComponents);
    return StressReportOutcome(passed: passed, failures: failures);
  }

  static int maxInt(int a, int b) => a > b ? a : b;
  String mib(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(2);
  String mark(bool value) => value ? 'PASS' : 'FAIL';

  void _writeCsv(FormalGameStressResult result) {
    final b = StringBuffer()
      ..writeln(
        'update,simulated_seconds,score,active_targets,detached_tracked,component_total,obstacles,coins,platforms,gaps,powerups,used_letters,terrain_segments,coin_effects,pending_events,rss_bytes',
      );
    for (final s in result.samples) {
      b.writeln(
        '${s.update},${s.simulatedSeconds.toStringAsFixed(3)},${s.score},${s.activeTargets},${s.detachedTracked},${s.componentTotal},${s.obstacles},${s.coins},${s.platforms},${s.gaps},${s.powerups},${s.usedLetters},${s.terrainSegments},${s.coinEffects},${s.pendingEvents},${s.rssBytes}',
      );
    }
    File('${directory.path}/metrics.csv').writeAsStringSync(b.toString());
  }

  void _writeDiagnostic(
    FormalGameStressResult r,
    StressRunMetadata m,
    Map<String, bool> checks,
    bool passed,
    int maxActive,
    int maxComponents,
  ) {
    final spawned = r.spawnedByType.entries
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    final b = StringBuffer()
      ..writeln('# 正式 TypingMarioGame 700 分 host 压力诊断')
      ..writeln('\n- 结论：**${passed ? 'PASS' : 'FAIL'}**')
      ..writeln('- Git：`${m.gitSha}` (${m.gitDirty ? 'dirty' : 'clean'})')
      ..writeln('- Flutter：`${m.flutterVersion}`')
      ..writeln('- Dart：`${m.dartVersion}`')
      ..writeln('- 平台：`${m.platform}`')
      ..writeln('- 命令：`${m.command}`')
      ..writeln('- 种子：`20260717`；固定步长：`1/120s`；生成倍率：`0.08`')
      ..writeln(
        '- 覆盖：正式 TypingMarioGame.onLoad/update/onLetterTyped、真实 LetterTarget/ObstacleSprite/其他 sprite、Flame add/remove、地形及 CoinEffect 生命周期。',
      )
      ..writeln(
        '- 压力模式差异：`collisionsEnabled=false`，避免自动碰撞改变精确计分；`hostLifecycleSnapshot=true`，在无 GameWidget 帧边界时显式排空 Flame 生命周期事件。',
      )
      ..writeln(
        '- 限制：host 无渲染帧耗时/GPU/Android 内存；音频通过依赖注入禁用，pending events=0 仅表示测试音频无待处理任务，**不覆盖原生音频**，也不宣称验证 Android 音频。',
      )
      ..writeln('\n## 阈值与指标\n')
      ..writeln('| 检查 | 实测 | 阈值 | 结果 |')
      ..writeln('|---|---:|---:|:---:|')
      ..writeln(
        '| 精确分数 | ${r.finalScore} | ${r.targetScore} | ${mark(checks['精确 700 分']!)} |',
      )
      ..writeln(
        '| 正式障碍匹配 | ${r.obstaclesMatched} | 70 | ${mark(checks['70 个正式障碍匹配']!)} |',
      )
      ..writeln(
        '| updates | ${r.updateCount} | >=3000 | ${mark(checks['至少 3000 updates']!)} |',
      )
      ..writeln(
        '| 模拟时间 | ${r.simulatedSeconds.toStringAsFixed(2)}s | 信息 | INFO |',
      )
      ..writeln(
        '| 最大 activeTargets | $maxActive | <=${thresholds.maxActiveTargets} | ${mark(checks['active targets 有界']!)} |',
      )
      ..writeln(
        '| 最大 detached tracked | ${r.maxDetachedTracked} | <=${thresholds.maxDetachedTracked} | ${mark(checks['无 detached tracked']!)} |',
      )
      ..writeln(
        '| 最大组件总数 | $maxComponents | <=${thresholds.maxComponentTotal} | ${mark(checks['组件总数有界']!)} |',
      )
      ..writeln(
        '| drain 后 active/letters | ${r.finalActiveTargets}/${r.finalUsedLetters} | 0/0 | ${mark(checks['drain 后 target 清空']!)} |',
      )
      ..writeln(
        '| pending events | ${r.pendingEvents} | 0 | ${mark(checks['pending events 清空']!)} |',
      )
      ..writeln('| 预热后 RSS | ${mib(r.warmupRssBytes)} MiB | 信息 | INFO |')
      ..writeln('| 结束 RSS | ${mib(r.endRssBytes)} MiB | 信息 | INFO |')
      ..writeln('| 峰值 RSS | ${mib(r.peakRssBytes)} MiB | 信息 | INFO |')
      ..writeln(
        '| 预热后 RSS 增长 | ${mib(r.rssGrowthBytes)} MiB | <=${mib(thresholds.maxRssGrowthBytes)} MiB | ${mark(checks['预热后 RSS 增长']!)} |',
      )
      ..writeln(
        '| wall time | ${(r.elapsedMicros / 1e6).toStringAsFixed(3)}s | <=${thresholds.maxElapsedMicros / 1e6}s | ${mark(checks['host 运行耗时']!)} |',
      )
      ..writeln('\n生成组件：$spawned\n')
      ..writeln(
        '`metrics.csv` 在输入前采样，因此保留有意义的非零实时对象曲线；`memory_curve.svg` 来自同次 host 进程 RSS。',
      );
    File('${directory.path}/diagnostic.md').writeAsStringSync(b.toString());
  }

  void _writeLog(
    FormalGameStressResult r,
    StressRunMetadata m,
    bool passed,
    List<String> failures,
    int maxActive,
    int maxComponents,
  ) {
    File('${directory.path}/run.log').writeAsStringSync(
      'git_sha=${m.gitSha}\ngit_dirty=${m.gitDirty}\nflutter=${m.flutterVersion}\ndart=${m.dartVersion}\nplatform=${m.platform}\ncommand=${m.command}\ngame_class=${r.gameClass}\nseed=20260717\nfinal_score=${r.finalScore}\nobstacles_matched=${r.obstaclesMatched}\nupdates=${r.updateCount}\nsimulated_seconds=${r.simulatedSeconds}\nmax_active_targets=$maxActive\nmax_detached_tracked=${r.maxDetachedTracked}\nmax_components=$maxComponents\nfinal_active_targets=${r.finalActiveTargets}\nfinal_used_letters=${r.finalUsedLetters}\npending_events=${r.pendingEvents}\nwarmup_rss_bytes=${r.warmupRssBytes}\nend_rss_bytes=${r.endRssBytes}\npeak_rss_bytes=${r.peakRssBytes}\nrss_growth_bytes=${r.rssGrowthBytes}\nelapsed_us=${r.elapsedMicros}\nfailures=${failures.join(',')}\nverdict=${passed ? 'PASS' : 'FAIL'}\n',
    );
  }

  void _writeSvg(List<StressSample> samples) {
    const left = 65.0, top = 30.0, plotW = 800.0, plotH = 270.0;
    final minRss = samples
        .map((s) => s.rssBytes)
        .reduce((a, b) => a < b ? a : b);
    final maxRss = samples.map((s) => s.rssBytes).reduce(maxInt);
    final range = maxRss == minRss ? 1 : maxRss - minRss;
    final maxUpdate = samples.last.update == 0 ? 1 : samples.last.update;
    final points = samples
        .map(
          (s) =>
              '${(left + s.update / maxUpdate * plotW).toStringAsFixed(2)},${(top + (maxRss - s.rssBytes) / range * plotH).toStringAsFixed(2)}',
        )
        .join(' ');
    File('${directory.path}/memory_curve.svg').writeAsStringSync(
      '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="350"><rect width="100%" height="100%" fill="white"/><text x="450" y="20" text-anchor="middle">TypingMarioGame host RSS after warm-up</text><line x1="$left" y1="300" x2="865" y2="300" stroke="black"/><polyline points="$points" fill="none" stroke="#1565c0" stroke-width="2"/><text x="450" y="335" text-anchor="middle">fixed-step updates (0-$maxUpdate), RSS ${mib(minRss)}-${mib(maxRss)} MiB</text></svg>',
    );
  }
}
