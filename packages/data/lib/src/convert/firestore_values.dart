import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads that ask Firestore for an estimate of pending server timestamps, so
/// a doc written on this device and not yet synced shows a time instead of
/// null. Snapshot listeners can't take this option in the FlutterFire API
/// (they always use [ServerTimestampBehavior.none]); [plainFromFirestore]
/// fills those in instead.
const GetOptions estimateServerTimestamps = GetOptions(
  serverTimestampBehavior: ServerTimestampBehavior.estimate,
);

/// Converts Firestore document data into the plain map core's `fromMap`
/// expects (`MapReader`): every [Timestamp], at any depth in maps and lists,
/// becomes a local-time [DateTime], and a double with no fractional part
/// becomes an [int] (web and hand-edited docs can hand those back; a real
/// fraction is left alone so `MapReader` still rejects it).
///
/// Pending server timestamps: a field written with
/// `FieldValue.serverTimestamp()` reads as null until the server confirms
/// it, under [ServerTimestampBehavior.none], which is what snapshot
/// listeners use. When [hasPendingWrites] is true, each top-level field in
/// [serverTimestampFields] that is null is set to [now], the same estimate
/// [ServerTimestampBehavior.estimate] gives. A doc without pending writes
/// keeps its nulls: there the field is really unset.
Map<String, Object?> plainFromFirestore(
  Map<String, dynamic> data, {
  Set<String> serverTimestampFields = const {},
  bool hasPendingWrites = false,
  DateTime Function() now = DateTime.now,
}) {
  final out = <String, Object?>{
    for (final e in data.entries) e.key: plainValue(e.value),
  };
  if (hasPendingWrites) {
    for (final f in serverTimestampFields) {
      if (out.containsKey(f) && out[f] == null) out[f] = now();
    }
  }
  return out;
}

/// One value, converted as [plainFromFirestore] describes.
Object? plainValue(Object? v) => switch (v) {
  Timestamp() => v.toDate(),
  double() when v.isFinite && v == v.truncateToDouble() => v.toInt(),
  Map() => <String, Object?>{
    for (final e in v.entries) e.key.toString(): plainValue(e.value),
  },
  List() => [for (final e in v) plainValue(e)],
  _ => v,
};

/// Converts [snap] with [plainFromFirestore] and hands it to [fromMap], or
/// returns null when the doc doesn't exist.
T? modelOrNull<T>(
  DocumentSnapshot<Map<String, dynamic>> snap,
  T Function(String id, Map<String, Object?> map) fromMap, {
  Set<String> serverTimestampFields = const {},
  DateTime Function() now = DateTime.now,
}) {
  final data = snap.data();
  if (!snap.exists || data == null) return null;
  return fromMap(
    snap.id,
    plainFromFirestore(
      data,
      serverTimestampFields: serverTimestampFields,
      hasPendingWrites: snap.metadata.hasPendingWrites,
      now: now,
    ),
  );
}

/// Every doc of a query snapshot, converted with [modelOrNull].
List<T> modelsOf<T>(
  QuerySnapshot<Map<String, dynamic>> snap,
  T Function(String id, Map<String, Object?> map) fromMap, {
  Set<String> serverTimestampFields = const {},
  DateTime Function() now = DateTime.now,
}) => [
  for (final d in snap.docs)
    fromMap(
      d.id,
      plainFromFirestore(
        d.data(),
        serverTimestampFields: serverTimestampFields,
        hasPendingWrites: d.metadata.hasPendingWrites,
        now: now,
      ),
    ),
];
