/// A FIFO gate for one non-interruptible audio channel.
///
/// [enqueue] returns the next item that may start immediately. While a clip is
/// active, new items are retained until the caller reports completion.
class CriticalAudioQueue<T> {
  CriticalAudioQueue({this.maxPending, this.coalescePendingDuplicates = false});

  final int? maxPending;
  final bool coalescePendingDuplicates;
  final List<T> _pending = <T>[];
  bool _isBusy = false;

  bool get isBusy => _isBusy;
  int get pendingCount => _pending.length;

  T? enqueue(T item) {
    if (!_isBusy) {
      _isBusy = true;
      return item;
    }
    if (coalescePendingDuplicates && _pending.contains(item)) return null;
    if (maxPending != null && _pending.length >= maxPending!) return null;
    _pending.add(item);
    return null;
  }

  T? complete() {
    if (_pending.isEmpty) {
      _isBusy = false;
      return null;
    }
    return _pending.removeAt(0);
  }

  void reset() {
    _pending.clear();
    _isBusy = false;
  }
}
