/// The pure write plan every business operation produces (D-027).
///
/// A [WritePlan] is an ordered list of [WriteOp]s: the docs one atomic batch
/// writes (03-SYNC §2). It holds plain Dart values, [DateTime]s and two
/// sentinels, [Increment] and [ServerTimestamp], and no Firestore types, so
/// every business rule is testable with plain `flutter test`. The adapter in
/// `firestore/plan_adapter.dart` turns a plan into a `WriteBatch`; the JSON
/// form ([WritePlan.toJson]) is the fixture format the rules suite and QA's
/// pure-Dart tests read.
///
/// What `data` means depends on the op's [WriteKind]:
/// - [WriteKind.create]: the whole new doc; nested maps are literal values.
///   Applied as `set` without merge. The rules decide create-only docs
///   (bills, returns, movements, audit) with `!exists`.
/// - [WriteKind.setMerge]: `set(..., merge: true)`. Nested maps merge into
///   the stored doc field by field, so `{'byMode': {'CASH': Increment(5)}}`
///   touches only `byMode.CASH`. Keys are field names, never dotted paths.
/// - [WriteKind.update]: `update`. Each top-level key is a **field path**
///   whose segments are separated by dots (`returnedQty.P1`), and its value
///   replaces that field. The doc must exist.
library;

import 'dart:convert';

enum WriteKind {
  create('create'),
  update('update'),
  setMerge('setMerge');

  const WriteKind(this.wire);

  /// The name used in JSON fixtures.
  final String wire;
}

/// `FieldValue.increment(by)`. Integers only (D-005, D-006).
final class Increment {
  const Increment(this.by);

  final int by;

  @override
  bool operator ==(Object other) => other is Increment && other.by == by;

  @override
  int get hashCode => by.hashCode;

  @override
  String toString() => 'Increment($by)';
}

/// `FieldValue.serverTimestamp()`.
final class ServerTimestamp {
  const ServerTimestamp();

  @override
  bool operator ==(Object other) => other is ServerTimestamp;

  @override
  int get hashCode => (ServerTimestamp).hashCode;

  @override
  String toString() => 'ServerTimestamp()';
}

/// The shared [ServerTimestamp] sentinel.
const ServerTimestamp serverTimestamp = ServerTimestamp();

/// One doc write in a plan.
final class WriteOp {
  const WriteOp(this.path, this.kind, this.data);

  /// Relative to the database root, from `FirestorePaths`.
  final String path;
  final WriteKind kind;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.wire,
    'data': encodePlanValue(data),
  };

  @override
  String toString() => 'WriteOp(${kind.wire} $path $data)';
}

/// An ordered list of doc writes that must land as one batch.
final class WritePlan {
  WritePlan(Iterable<WriteOp> ops) : ops = List.unmodifiable(ops);

  /// Firestore allows 500 writes per batch; the largest plan (a 20-line
  /// movement) is far below it.
  static const int maxOps = 500;

  final List<WriteOp> ops;

  /// The op writing [path], or null. A plan writes each doc at most once.
  WriteOp? opAt(String path) {
    for (final o in ops) {
      if (o.path == path) return o;
    }
    return null;
  }

  List<String> get paths => [for (final o in ops) o.path];

  /// `{"ops": [...]}` in the fixture encoding (see [encodePlanValue]).
  Map<String, Object?> toJson() => {
    'ops': [for (final o in ops) o.toJson()],
  };

  @override
  String toString() => 'WritePlan(${ops.length} ops)';
}

/// Collects ops, rejecting a second write to the same doc: two writes to
/// one doc in a batch would make the rules evaluate against a state the
/// plan doesn't describe.
final class PlanBuilder {
  final List<WriteOp> _ops = [];
  final Set<String> _paths = {};

  void create(String path, Map<String, Object?> data) =>
      _add(WriteOp(path, WriteKind.create, data));

  void setMerge(String path, Map<String, Object?> data) =>
      _add(WriteOp(path, WriteKind.setMerge, data));

  void update(String path, Map<String, Object?> data) =>
      _add(WriteOp(path, WriteKind.update, data));

  void _add(WriteOp op) {
    if (!_paths.add(op.path)) {
      throw StateError('plan writes ${op.path} twice');
    }
    _ops.add(op);
  }

  WritePlan build() {
    if (_ops.length > WritePlan.maxOps) {
      throw StateError('plan has ${_ops.length} ops');
    }
    return WritePlan(_ops);
  }
}

/// Turns dotted field paths into nested maps, for [WriteKind.setMerge]:
/// `{'byMode.CASH': 5}` → `{'byMode': {'CASH': 5}}`.
Map<String, Object?> nestFieldPaths(Map<String, Object?> flat) {
  final out = <String, Object?>{};
  for (final e in flat.entries) {
    final parts = e.key.split('.');
    var node = out;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = node.putIfAbsent(parts[i], () => <String, Object?>{});
      if (next is! Map<String, Object?>) {
        throw ArgumentError('field ${e.key} clashes with ${parts[i]}');
      }
      node = next;
    }
    if (node.containsKey(parts.last)) {
      throw ArgumentError('field ${e.key} is given twice');
    }
    node[parts.last] = e.value;
  }
  return out;
}

/// The JSON fixture encoding (docs/agents/BACKEND.md, "Plan fixtures"):
/// [Increment] → `{"__op": "increment", "by": n}`, [ServerTimestamp] →
/// `{"__op": "serverTimestamp"}`, and a [DateTime] →
/// `{"__op": "timestamp", "value": "<ISO-8601 UTC>"}`. Maps and lists are
/// encoded recursively; everything else must already be JSON.
Object? encodePlanValue(Object? v) => switch (v) {
  null || String() || bool() || int() => v,
  Increment(:final by) => {'__op': 'increment', 'by': by},
  ServerTimestamp() => {'__op': 'serverTimestamp'},
  DateTime() => {'__op': 'timestamp', 'value': v.toUtc().toIso8601String()},
  Map<String, Object?>() => {
    for (final e in v.entries) e.key: encodePlanValue(e.value),
  },
  Map() => {for (final e in v.entries) '${e.key}': encodePlanValue(e.value)},
  Iterable() => [for (final x in v) encodePlanValue(x)],
  _ => throw ArgumentError.value(v, 'value', 'not a plan value'),
};

/// The inverse of [encodePlanValue].
Object? decodePlanValue(Object? v) {
  if (v is Map) {
    final op = v['__op'];
    if (op == 'increment') return Increment(v['by']! as int);
    if (op == 'serverTimestamp') return serverTimestamp;
    if (op == 'timestamp') return DateTime.parse(v['value']! as String);
    return <String, Object?>{
      for (final e in v.entries) e.key as String: decodePlanValue(e.value),
    };
  }
  if (v is List) return [for (final x in v) decodePlanValue(x)];
  return v;
}

/// Reads a plan back from its JSON form.
WritePlan decodePlan(Map<String, Object?> json) => WritePlan([
  for (final o in json['ops']! as List<Object?>)
    if (o case {
      'path': final String path,
      'kind': final String kind,
      'data': final Map<String, Object?> data,
    })
      WriteOp(
        path,
        WriteKind.values.firstWhere((k) => k.wire == kind),
        decodePlanValue(data)! as Map<String, Object?>,
      )
    else
      throw FormatException('bad op', o),
]);

/// Pretty JSON with a trailing newline, as committed fixtures are written.
String prettyJson(Object? json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';
