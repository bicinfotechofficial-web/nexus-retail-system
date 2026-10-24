import 'dart:async';

/// A value that streams its current state to every new listener and again on
/// each change, like a Firestore snapshot listener.
class Live<T> {
  Live(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast(
    sync: true,
  );

  T get value => _value;
  set value(T v) {
    _value = v;
    _changes.add(v);
  }

  Stream<R> watch<R>(R Function(T) project) async* {
    yield project(_value);
    yield* _changes.stream.map(project);
  }
}
