import 'package:cloud_firestore/cloud_firestore.dart';

import '../plans/write_plan.dart';

/// Applies a [WritePlan] to Firestore (D-027). Deliberately thin: every
/// business rule lives in the pure plan builders; this only maps plan
/// values to Firestore ones and ops to batch calls.
///
/// - [WriteKind.create] → `set(ref, data)`
/// - [WriteKind.setMerge] → `set(ref, data, SetOptions(merge: true))`
/// - [WriteKind.update] → `update(ref, {FieldPath: value})`, each key split
///   on dots into a [FieldPath]
/// - [Increment] → `FieldValue.increment`, [ServerTimestamp] →
///   `FieldValue.serverTimestamp()`, [DateTime] → [Timestamp], recursively.
abstract final class PlanAdapter {
  /// A new batch holding [plan]. The caller commits it; offline, the SDK
  /// queues it and applies it exactly once (03-SYNC §1).
  static WriteBatch toBatch(FirebaseFirestore db, WritePlan plan) {
    final batch = db.batch();
    apply(plan, WriteBatchSink(db, batch));
    return batch;
  }

  /// Writes [plan]'s ops into [tx], e.g. after the transaction's reads.
  static void toTransaction(
    FirebaseFirestore db,
    Transaction tx,
    WritePlan plan,
  ) => apply(plan, TransactionSink(db, tx));

  /// Sends every op of [plan] to [sink], in order.
  static void apply(WritePlan plan, PlanSink sink) {
    for (final op in plan.ops) {
      switch (op.kind) {
        case WriteKind.create:
          sink.set(op.path, encodeMap(op.data), merge: false);
        case WriteKind.setMerge:
          sink.set(op.path, encodeMap(op.data), merge: true);
        case WriteKind.update:
          sink.update(op.path, {
            for (final e in op.data.entries)
              FieldPath(e.key.split('.')): encode(e.value),
          });
      }
    }
  }

  static Map<String, Object?> encodeMap(Map<String, Object?> m) => {
    for (final e in m.entries) e.key: encode(e.value),
  };

  /// A plan value as Firestore takes it.
  static Object? encode(Object? v) => switch (v) {
    Increment(:final by) => FieldValue.increment(by),
    ServerTimestamp() => FieldValue.serverTimestamp(),
    DateTime() => Timestamp.fromDate(v),
    Map<String, Object?>() => encodeMap(v),
    List<Object?>() => [for (final x in v) encode(x)],
    _ => v,
  };

  /// A Firestore value as the core models read it: [Timestamp] →
  /// [DateTime] (UTC), recursively (`MapReader` takes `DateTime` only).
  static Object? decode(Object? v) => switch (v) {
    Timestamp() => v.toDate().toUtc(),
    Map<Object?, Object?>() => <String, Object?>{
      for (final e in v.entries) '${e.key}': decode(e.value),
    },
    List<Object?>() => [for (final x in v) decode(x)],
    _ => v,
  };

  /// A snapshot's data ready for a model's `fromMap`.
  static Map<String, Object?> decodeDoc(Map<String, Object?> data) =>
      decode(data)! as Map<String, Object?>;
}

/// Where [PlanAdapter.apply] sends ops. Lets tests record them without a
/// Firestore instance.
abstract interface class PlanSink {
  void set(String path, Map<String, Object?> data, {required bool merge});
  void update(String path, Map<FieldPath, Object?> data);
}

final class WriteBatchSink implements PlanSink {
  WriteBatchSink(this.db, this.batch);

  final FirebaseFirestore db;
  final WriteBatch batch;

  @override
  void set(String path, Map<String, Object?> data, {required bool merge}) =>
      batch.set(db.doc(path), data, merge ? SetOptions(merge: true) : null);

  @override
  void update(String path, Map<FieldPath, Object?> data) =>
      batch.update<Map<Object, Object?>>(db.doc(path), data);
}

final class TransactionSink implements PlanSink {
  TransactionSink(this.db, this.tx);

  final FirebaseFirestore db;
  final Transaction tx;

  @override
  void set(String path, Map<String, Object?> data, {required bool merge}) =>
      tx.set(db.doc(path), data, merge ? SetOptions(merge: true) : null);

  @override
  void update(String path, Map<FieldPath, Object?> data) =>
      tx.update(db.doc(path), data);
}
