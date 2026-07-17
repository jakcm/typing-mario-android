import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/utils/audio_manager.dart';
import 'package:typing_mario_android/utils/critical_audio_queue.dart';

void main() {
  test('critical gameplay channels use completion-capable media players', () {
    expect(AudioManager.criticalEffectPlayerMode, PlayerMode.mediaPlayer);
  });

  group('CriticalAudioQueue', () {
    test(
      'keeps every critical sound in FIFO order while its channel is busy',
      () {
        final queue = CriticalAudioQueue<String>();

        expect(queue.enqueue('coin-1'), 'coin-1');
        expect(queue.enqueue('coin-2'), isNull);
        expect(queue.enqueue('coin-3'), isNull);
        expect(queue.pendingCount, 2);

        expect(queue.complete(), 'coin-2');
        expect(queue.complete(), 'coin-3');
        expect(queue.complete(), isNull);
        expect(queue.isBusy, isFalse);
      },
    );

    test('reset drops only sounds that have not started', () {
      final queue = CriticalAudioQueue<String>();
      queue.enqueue('stomp-1');
      queue.enqueue('stomp-2');

      queue.reset();

      expect(queue.pendingCount, 0);
      expect(queue.isBusy, isFalse);
      expect(queue.enqueue('stomp-3'), 'stomp-3');
    });

    test('bounded spam queue coalesces stale duplicate cues', () {
      final queue = CriticalAudioQueue<String>(
        maxPending: 1,
        coalescePendingDuplicates: true,
      );

      expect(queue.enqueue('jump'), 'jump');
      for (var i = 0; i < 20; i++) {
        expect(queue.enqueue('jump'), isNull);
      }

      expect(queue.pendingCount, 1);
      expect(queue.complete(), 'jump');
      expect(queue.complete(), isNull);
    });

    test('default critical queue never drops reward events', () {
      final queue = CriticalAudioQueue<String>();

      expect(queue.enqueue('coin-0'), 'coin-0');
      for (var i = 1; i <= 100; i++) {
        expect(queue.enqueue('coin-$i'), isNull);
      }

      expect(queue.pendingCount, 100);
      for (var i = 1; i <= 100; i++) {
        expect(queue.complete(), 'coin-$i');
      }
    });
  });
}
