# 正式 TypingMarioGame 700 分 host 压力诊断

- 结论：**PASS**
- Git：`26a859f` (dirty)
- Flutter：`Flutter 3.44.6 • channel stable • https://github.com/flutter/flutter.git`
- Dart：`3.12.2`
- 平台：`macos Version 26.2 (Build 25C56)`
- 命令：`flutter test tool/stress_700.dart -- /Users/admin/projects/typing_mario_android/reports/stress/20260717T075221Z`
- 种子：`20260717`；固定步长：`1/120s`；生成倍率：`0.08`
- 覆盖：正式 TypingMarioGame.onLoad/update/onLetterTyped、真实 LetterTarget/ObstacleSprite/其他 sprite、Flame add/remove、地形及 CoinEffect 生命周期。
- 压力模式差异：`collisionsEnabled=false`，避免自动碰撞改变精确计分；`hostLifecycleSnapshot=true`，在无 GameWidget 帧边界时显式排空 Flame 生命周期事件。
- 限制：host 无渲染帧耗时/GPU/Android 内存；音频通过依赖注入禁用，pending events=0 仅表示测试音频无待处理任务，**不覆盖原生音频**，也不宣称验证 Android 音频。

## 阈值与指标

| 检查 | 实测 | 阈值 | 结果 |
|---|---:|---:|:---:|
| 精确分数 | 700 | 700 | PASS |
| 正式障碍匹配 | 70 | 70 | PASS |
| updates | 5069 | >=3000 | PASS |
| 模拟时间 | 42.24s | 信息 | INFO |
| 最大 activeTargets | 44 | <=64 | PASS |
| 最大 detached tracked | 0 | <=0 | PASS |
| 最大组件总数 | 54 | <=96 | PASS |
| drain 后 active/letters | 0/0 | 0/0 | PASS |
| pending events | 0 | 0 | PASS |
| 预热后 RSS | 155.19 MiB | 信息 | INFO |
| 结束 RSS | 163.59 MiB | 信息 | INFO |
| 峰值 RSS | 166.84 MiB | 信息 | INFO |
| 预热后 RSS 增长 | 8.41 MiB | <=96.00 MiB | PASS |
| wall time | 0.240s | <=30.0s | PASS |

生成组件：ObstacleSprite=70, FloatingCoinSprite=54, PlatformSprite=33, GapSprite=21, PowerUpSprite=3

`metrics.csv` 在输入前采样，因此保留有意义的非零实时对象曲线；`memory_curve.svg` 来自同次 host 进程 RSS。
