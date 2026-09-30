/// The backend's WritePlan JSON fixtures (D-027, docs/agents/BACKEND.md
/// "Plan fixtures") and an in-memory document store that applies them with
/// Firestore's write semantics. Written from the fixture format and the
/// Firestore docs, not from `nexus_data`, which this package can't import
/// (QA-016): the fixtures are the contract between the two.
///
/// Semantics (docs/agents/BACKEND.md, `WriteKind`):
/// - `create`: the whole doc; the doc must not exist (the rules make bills,
///   returns, movements, audit docs and expenses create-only with
///   `!exists`).
/// - `setMerge`: `set(..., merge: true)`. A nested map merges field by
///   field; any other value replaces the field.
/// - `update`: each top-level key is a dotted field path whose value
///   replaces that field; the doc must exist.
/// - `{"__op": "increment", "by": n}` adds to the stored number (0 when the
///   field is missing or not a number), `{"__op": "serverTimestamp"}` is the
///   store's server time, and `{"__op": "timestamp", "value": ...}` a
///   [DateTime].
library;

import 'dart:convert';
import 'dart:io';

/// Where the backend exports the fixtures, relative to `test/e2e`.
final Directory planFixtureDir = Directory(
  '../../firebase/test/fixtures/plans',
);

/// `FieldValue.increment(by)`.
final class Inc {
  const Inc(this.by);
  final int by;

  @override
  String toString() => 'Inc($by)';
}

/// `FieldValue.serverTimestamp()`.
final class ServerTs {
  const ServerTs();

  @override
  String toString() => 'ServerTs';
}

enum OpKind { create, update, setMerge }

final class PlanOp {
  PlanOp(this.path, this.kind, this.data);

  final String path;
  final OpKind kind;
  final Map<String, Object?> data;

  List<String> get segments => path.split('/');
  String get id => segments.last;

  /// `locations/PTB/bills/D01-000007` → `bills`; `auditLog/X` → `auditLog`.
  String get collection => segments[segments.length - 2];

  /// The location of a doc under `locations/{loc}/...`, else null.
  String? get locationId =>
      segments.length >= 4 && segments.first == 'locations'
      ? segments[1]
      : null;
}

final class PlanFixture {
  PlanFixture({
    required this.name,
    required this.description,
    required this.uid,
    required this.arrange,
    required this.ops,
  });

  factory PlanFixture.fromJson(String name, Map<String, Object?> json) {
    final arrange = <String, Map<String, Object?>>{};
    for (final a in json['arrange']! as List<Object?>) {
      final m = a! as Map<String, Object?>;
      arrange[m['path']! as String] =
          decodeValue(m['data']) as Map<String, Object?>;
    }
    return PlanFixture(
      name: name,
      description: json['description']! as String,
      uid: json['uid']! as String,
      arrange: arrange,
      ops: [
        for (final o in json['ops']! as List<Object?>)
          if (o case {
            'path': final String path,
            'kind': final String kind,
            'data': final Map<String, Object?> data,
          })
            PlanOp(
              path,
              OpKind.values.byName(kind),
              decodeValue(data)! as Map<String, Object?>,
            )
          else
            throw FormatException('bad op in $name', o),
      ],
    );
  }

  final String name;
  final String description;
  final String uid;
  final Map<String, Map<String, Object?>> arrange;
  final List<PlanOp> ops;

  PlanOp? opAt(String path) {
    for (final o in ops) {
      if (o.path == path) return o;
    }
    return null;
  }
}

/// Every fixture file, by name without `.json`.
Map<String, PlanFixture> loadPlanFixtures() {
  if (!planFixtureDir.existsSync()) {
    throw StateError('no fixtures at ${planFixtureDir.absolute.path}');
  }
  final files =
      planFixtureDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final f in files)
      _nameOf(f): PlanFixture.fromJson(
        _nameOf(f),
        jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
      ),
  };
}

String _nameOf(File f) {
  final base = f.uri.pathSegments.last;
  return base.substring(0, base.length - '.json'.length);
}

/// The fixture encoding, decoded to plain values and the sentinels above.
Object? decodeValue(Object? v) {
  if (v is Map) {
    switch (v['__op']) {
      case 'increment':
        return Inc(v['by']! as int);
      case 'serverTimestamp':
        return const ServerTs();
      case 'timestamp':
        return DateTime.parse(v['value']! as String);
      case null:
        return <String, Object?>{
          for (final e in v.entries) e.key as String: decodeValue(e.value),
        };
      default:
        throw FormatException('unknown __op', v);
    }
  }
  if (v is List) return [for (final x in v) decodeValue(x)];
  return v;
}

/// Docs by path. Every value is plain: sentinels are resolved on write.
final class DocStore {
  DocStore({DateTime? serverTime})
    : serverTime = serverTime ?? DateTime.utc(2026, 9, 26, 12);

  /// What `serverTimestamp` resolves to. Tests move it between batches.
  DateTime serverTime;

  final Map<String, Map<String, Object?>> docs = {};

  DocStore copy() {
    final c = DocStore(serverTime: serverTime);
    for (final e in docs.entries) {
      c.docs[e.key] = _deepCopy(e.value) as Map<String, Object?>;
    }
    return c;
  }

  /// Writes a doc as the rules suite's `arrange` does (rules off, plain set).
  void put(String path, Map<String, Object?> data) =>
      docs[path] = _resolve(data, null) as Map<String, Object?>;

  /// Applies every op of [ops] as one batch: all of them or, when one fails
  /// its precondition, none.
  void applyBatch(List<PlanOp> ops) {
    final next = copy();
    for (final op in ops) {
      next._apply(op);
    }
    docs
      ..clear()
      ..addAll(next.docs);
  }

  void _apply(PlanOp op) {
    final existing = docs[op.path];
    switch (op.kind) {
      case OpKind.create:
        if (existing != null) {
          throw StateError('create on existing ${op.path}');
        }
        docs[op.path] = _resolve(op.data, null) as Map<String, Object?>;
      case OpKind.setMerge:
        docs[op.path] = _merge(existing ?? {}, op.data);
      case OpKind.update:
        if (existing == null) throw StateError('update on missing ${op.path}');
        final doc = _deepCopy(existing) as Map<String, Object?>;
        for (final e in op.data.entries) {
          final parts = e.key.split('.');
          var node = doc;
          for (final p in parts.take(parts.length - 1)) {
            final child = node[p];
            if (child is Map<String, Object?>) {
              node = child;
            } else {
              final created = <String, Object?>{};
              node[p] = created;
              node = created;
            }
          }
          node[parts.last] = _resolve(e.value, node[parts.last]);
        }
        docs[op.path] = doc;
    }
  }

  Map<String, Object?> _merge(
    Map<String, Object?> into,
    Map<String, Object?> data,
  ) {
    final out = _deepCopy(into) as Map<String, Object?>;
    for (final e in data.entries) {
      final v = e.value;
      if (v is Map<String, Object?>) {
        if (v.isEmpty) {
          throw UnsupportedError('empty map in a merge (${e.key})');
        }
        final cur = out[e.key];
        out[e.key] = _merge(cur is Map<String, Object?> ? cur : {}, v);
      } else {
        out[e.key] = _resolve(v, out[e.key]);
      }
    }
    return out;
  }

  /// A written value with its sentinels resolved against [current].
  Object? _resolve(Object? v, Object? current) => switch (v) {
    Inc(:final by) => (current is int ? current : 0) + by,
    ServerTs() => serverTime,
    Map<String, Object?>() => {
      for (final e in v.entries) e.key: _resolve(e.value, null),
    },
    List<Object?>() => [for (final x in v) _resolve(x, null)],
    _ => v,
  };

  /// Docs whose path matches `prefix/<id>` exactly one level down.
  Map<String, Map<String, Object?>> collection(String prefix) => {
    for (final e in docs.entries)
      if (e.key.startsWith('$prefix/') &&
          !e.key.substring(prefix.length + 1).contains('/'))
        e.key.substring(prefix.length + 1): e.value,
  };

  /// Every location code that has a doc under `locations/{loc}/`.
  Set<String> get locationIds => {
    for (final p in docs.keys)
      if (p.startsWith('locations/') && p.split('/').length >= 4)
        p.split('/')[1],
  };
}

Object? _deepCopy(Object? v) => switch (v) {
  Map<String, Object?>() => {
    for (final e in v.entries) e.key: _deepCopy(e.value),
  },
  List<Object?>() => [for (final x in v) _deepCopy(x)],
  _ => v,
};
