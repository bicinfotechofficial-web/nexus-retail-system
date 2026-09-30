import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/device.dart';
import '../api/failures.dart';
import '../api/session.dart';
import '../counters/durable_store.dart';
import '../plans/device_plans.dart';
import '../plans/plan_support.dart';
import '../plans/write_plan.dart';
import 'plan_adapter.dart';

/// The reads and writes one registration transaction makes. Firestore in
/// the app ([FirestoreDeviceBackend]); a fake in tests.
abstract interface class DeviceTxn {
  /// The doc at [path] as the core models read it, or null.
  Future<Map<String, Object?>?> get(String path);

  /// Queues [plan]'s writes in the transaction.
  void apply(WritePlan plan);
}

/// What [FirestoreDeviceService] needs from Firestore. Implementations
/// throw `DataFailure` (offline, notPermitted, ...) rather than Firestore
/// exceptions.
abstract interface class DeviceBackend {
  Future<T> transaction<T>(Future<T> Function(DeviceTxn tx) body);
  Stream<List<Device>> watchDevices(String locationId);
  Future<void> commit(WritePlan plan);
}

/// [DeviceService] on Firestore (BE-9, 03-SYNC §3, D-004).
///
/// [register] runs one transaction: read `nextDeviceNo`, write
/// [DevicePlans.register] (`nextDeviceNo` + 1 and a clean `devices/D{n}`),
/// then stores the code locally, flushed, before returning. When two
/// registrations race, the loser's writes can be evaluated against the
/// winner's `nextDeviceNo` and come back PERMISSION_DENIED instead of
/// ABORTED (seen on the emulator), which the SDK doesn't retry; so a
/// `notPermitted` is retried a few times with a growing random pause,
/// re-reading the new value. A user whose session lacks `device.register`
/// at the location gets `notPermitted` at once, before any attempt.
final class FirestoreDeviceService implements DeviceService {
  FirestoreDeviceService({
    required DeviceBackend backend,
    required DurableStore local,
    required String? Function() uid,
    SessionContext? Function()? session,
    this.onRegistered,
    DateTime Function()? clock,
    this.attempts = 8,
    Future<void> Function(Duration)? sleep,
    Random? random,
  }) : _backend = backend,
       _local = local,
       _uid = uid,
       _session = session,
       _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random();

  static const String deviceIdKey = 'device.id';
  static const String locationIdKey = 'device.location';

  final DeviceBackend _backend;
  final DurableStore _local;
  final String? Function() _uid;
  final SessionContext? Function()? _session;
  final DateTime Function() _clock;

  /// Called after a registration is stored locally: registration is a
  /// server round trip, so the sync service moves `lastSyncAt` (03-SYNC
  /// §6.4).
  final FutureOr<void> Function(Device device)? onRegistered;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  /// Registration attempts before a `notPermitted` is final.
  final int attempts;

  @override
  String? get deviceId {
    final v = _local.read(deviceIdKey);
    return v is String ? v : null;
  }

  /// The location this install registered at, or null.
  @override
  String? get locationId {
    final v = _local.read(locationIdKey);
    return v is String ? v : null;
  }

  @override
  Future<Device> register({
    required String locationId,
    required String label,
  }) async {
    final uid = _uid();
    if (uid == null) {
      throw const DataFailure(FailureReason.notPermitted, 'signed out');
    }
    if (!Ids.isLocationCode(locationId)) {
      throw DataFailure(FailureReason.notFound, 'location $locationId');
    }
    final session = _session?.call();
    if (_session != null &&
        (session == null ||
            !session.canAt(Permission.deviceRegister, locationId))) {
      throw DataFailure(
        FailureReason.notPermitted,
        '${Permission.deviceRegister} at $locationId',
      );
    }
    final ctx = PlanContext(uid: uid, locationId: locationId, now: _clock());
    final device = await _registerWithRetry(ctx, locationId, label);
    await onRegistered?.call(device);
    return device;
  }

  Future<Device> _registerWithRetry(
    PlanContext ctx,
    String locationId,
    String label,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final device = await _backend.transaction((tx) async {
          final loc = await tx.get(FirestorePaths.location(locationId));
          if (loc == null) {
            throw DataFailure(FailureReason.notFound, 'location $locationId');
          }
          final current = loc['nextDeviceNo'];
          if (current is! int) {
            throw DataFailure(
              FailureReason.ruleViolation,
              '$locationId has no nextDeviceNo',
            );
          }
          final planned = DevicePlans.register(
            ctx: ctx,
            locationId: locationId,
            currentNextDeviceNo: current,
            label: label,
          );
          tx.apply(planned.plan);
          return planned.value;
        });
        await _local.write(locationIdKey, locationId);
        await _local.write(deviceIdKey, device.code);
        return device;
      } on DataFailure catch (f) {
        if (f.reason != FailureReason.notPermitted || attempt >= attempts) {
          rethrow;
        }
        final ms = 20 + _random.nextInt(80 * attempt);
        await _sleep(Duration(milliseconds: ms));
      }
    }
  }

  @override
  Stream<List<Device>> watchDevices(String locationId) =>
      _backend.watchDevices(locationId);

  @override
  Future<void> retire({required String locationId, required String deviceId}) =>
      _backend.commit(
        DevicePlans.retire(locationId: locationId, deviceId: deviceId),
      );
}

/// [DeviceBackend] on a [FirebaseFirestore] instance.
final class FirestoreDeviceBackend implements DeviceBackend {
  FirestoreDeviceBackend(this.db);

  final FirebaseFirestore db;

  @override
  Future<T> transaction<T>(Future<T> Function(DeviceTxn tx) body) =>
      _guard(() => db.runTransaction((tx) => body(_Txn(db, tx))));

  @override
  Stream<List<Device>> watchDevices(String locationId) => db
      .collection(FirestorePaths.devices(locationId))
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            Device.fromMap(d.id, PlanAdapter.decodeDoc(d.data())),
        ]..sort((a, b) => a.code.compareTo(b.code)),
      );

  @override
  Future<void> commit(WritePlan plan) =>
      _guard(() => PlanAdapter.toBatch(db, plan).commit());

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on FirebaseException catch (e) {
      throw DataFailure(failureReasonOf(e.code), e.message ?? e.code);
    }
  }
}

/// The failure reason for a Firestore error code.
FailureReason failureReasonOf(String code) => switch (code) {
  'unavailable' || 'deadline-exceeded' => FailureReason.offline,
  'permission-denied' || 'unauthenticated' => FailureReason.notPermitted,
  'not-found' => FailureReason.notFound,
  _ => FailureReason.unknown,
};

final class _Txn implements DeviceTxn {
  _Txn(this.db, this.tx);

  final FirebaseFirestore db;
  final Transaction tx;

  @override
  Future<Map<String, Object?>?> get(String path) async {
    final snap = await tx.get(db.doc(path));
    final data = snap.data();
    return data == null ? null : PlanAdapter.decodeDoc(data);
  }

  @override
  void apply(WritePlan plan) => PlanAdapter.toTransaction(db, tx, plan);
}
