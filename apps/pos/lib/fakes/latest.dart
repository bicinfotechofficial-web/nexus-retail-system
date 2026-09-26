import 'dart:async';

/// A stream that replays its latest value to every new listener, like a
/// Firestore snapshot listener.
final class Latest<T> {
  Latest(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    _changes.add(v);
  }

  Stream<T> get stream async* {
    yield _value;
    yield* _changes.stream;
  }

  Future<void> close() => _changes.close();
}
