import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_data/src/firestore/device_service.dart';

/// An in-memory backend with optimistic transactions. A transaction whose
/// read of the location went stale fails at commit the way the emulator
/// fails it: as PERMISSION_DENIED (`notPermitted`), because the rules see
/// `nextDeviceNo` already moved on.
final class _FakeBackend implements DeviceBackend {
  final Map<String, Map<String, Object?>> docs = {};
  final Map<String, int> versions = {};
  int commits = 0;
  bool offline = false;
  bool denyAll = false;

  @override
  Future<T> transaction<T>(Future<T> Function(DeviceTxn tx) body) async {
    if (offline) throw const DataFailure(FailureReason.offline);
    final tx = _FakeTxn(this);
    final result = await body(tx);
    await Future<void>.delayed(Duration.zero);
    if (denyAll) throw const DataFailure(FailureReason.notPermitted);
    for (final e in tx.readVersions.entries) {
      if ((versions[e.key] ?? 0) != e.value) {
        throw const DataFailure(FailureReason.notPermitted, 'stale read');
      }
    }
    for (final plan in tx.plans) {
      _apply(plan);
    }
    commits++;
    return result;
  }

  void _apply(WritePlan plan) {
    for (final op in plan.ops) {
      switch (op.kind) {
        case WriteKind.create:
          if (docs.containsKey(op.path)) {
            throw const DataFailure(FailureReason.notPermitted, 'exists');
          }
          docs[op.path] = Map.of(op.data);
        case WriteKind.update:
          docs[op.path] = {...docs[op.path]!, ...op.data};
        case WriteKind.setMerge:
          docs[op.path] = {...?docs[op.path], ...op.data};
      }
      versions[op.path] = (versions[op.path] ?? 0) + 1;
    }
  }

  @override
  Future<void> commit(WritePlan plan) async => _apply(plan);

  @override
  Stream<List<Device>> watchDevices(String locationId) => Stream.value([
    for (final e in docs.entries)
      if (e.key.startsWith('${FirestorePaths.devices(locationId)}/'))
        Device.fromMap(e.key.split('/').last, {
          for (final f in e.value.entries)
            if (f.value is! ServerTimestamp) f.key: f.value,
        }),
  ]);
}

final class _FakeTxn implements DeviceTxn {
  _FakeTxn(this.backend);
  final _FakeBackend backend;
  final Map<String, int> readVersions = {};
  final List<WritePlan> plans = [];

  @override
  Future<Map<String, Object?>?> get(String path) async {
    // Yield, so concurrent transactions interleave their reads.
    await Future<void>.delayed(Duration.zero);
    readVersions[path] = backend.versions[path] ?? 0;
    final d = backend.docs[path];
    return d == null ? null : Map.of(d);
  }

  @override
  void apply(WritePlan plan) => plans.add(plan);
}

FirestoreDeviceService _service(
  _FakeBackend backend, {
  DurableStore? local,
  String? uid = 'sm-ptb',
  int attempts = 8,
}) => FirestoreDeviceService(
  backend: backend,
  local: local ?? MemoryDurableStore(),
  uid: () => uid,
  clock: () => DateTime.utc(2026, 9, 26, 4, 30),
  attempts: attempts,
  sleep: (_) async {},
);

_FakeBackend _withPtb({int nextDeviceNo = 0}) =>
    _FakeBackend()
      ..docs['locations/PTB'] = {'code': 'PTB', 'nextDeviceNo': nextDeviceNo};

void main() {
  test(
    'registers D01: nextDeviceNo +1, a clean device, the code stored',
    () async {
      final backend = _withPtb();
      final local = MemoryDurableStore();
      final s = _service(backend, local: local);
      expect(s.deviceId, isNull);
      final d = await s.register(locationId: 'PTB', label: ' Counter 1 ');
      expect(d.code, 'D01');
      expect(d.label, 'Counter 1');
      expect(backend.docs['locations/PTB']!['nextDeviceNo'], 1);
      expect(backend.docs['locations/PTB/devices/D01'], {
        'code': 'D01',
        'label': 'Counter 1',
        'registeredBy': 'sm-ptb',
        'lastBillSeq': 0,
        'lastMovementSeq': 0,
        'lastReturnSeq': 0,
        'retired': false,
        'registeredAt': serverTimestamp,
      });
      expect(s.deviceId, 'D01');
      expect(s.locationId, 'PTB');
      // Stored durably: a new service on the same store sees it.
      expect(_service(backend, local: local).deviceId, 'D01');
    },
  );

  test('two concurrent registrations get D01 and D02', () async {
    final backend = _withPtb();
    final a = _service(backend);
    final b = _service(backend, uid: 'cashier-ptb');
    final codes = await Future.wait([
      a.register(locationId: 'PTB', label: 'A'),
      b.register(locationId: 'PTB', label: 'B'),
    ]);
    expect(codes.map((d) => d.code).toSet(), {'D01', 'D02'});
    expect(backend.docs['locations/PTB']!['nextDeviceNo'], 2);
    expect({a.deviceId, b.deviceId}, {'D01', 'D02'});
  });

  test('five concurrent registrations get D01 to D05', () async {
    final backend = _withPtb();
    final codes = await Future.wait([
      for (var i = 0; i < 5; i++)
        _service(backend).register(locationId: 'PTB', label: '$i'),
    ]);
    expect(codes.map((d) => d.code).toSet(), {
      'D01',
      'D02',
      'D03',
      'D04',
      'D05',
    });
  });

  test(
    'a reinstall (a new local store) gets a new code, never the old one',
    () async {
      final backend = _withPtb(nextDeviceNo: 3);
      final first = await _service(
        backend,
      ).register(locationId: 'PTB', label: 'x');
      await _service(backend).retire(locationId: 'PTB', deviceId: first.code);
      expect(backend.docs['locations/PTB/devices/D04']!['retired'], isTrue);
      final again = await _service(
        backend,
      ).register(locationId: 'PTB', label: 'x');
      expect((first.code, again.code), ('D04', 'D05'));
    },
  );

  test('refuses past D99, offline, signed out, unknown location', () async {
    await expectLater(
      _service(
        _withPtb(nextDeviceNo: 99),
      ).register(locationId: 'PTB', label: 'x'),
      throwsA(
        isA<DataFailure>().having(
          (f) => f.reason,
          'r',
          FailureReason.ruleViolation,
        ),
      ),
    );
    await expectLater(
      _service(
        _withPtb()..offline = true,
      ).register(locationId: 'PTB', label: 'x'),
      throwsA(
        isA<DataFailure>().having((f) => f.reason, 'r', FailureReason.offline),
      ),
    );
    await expectLater(
      _service(_withPtb(), uid: null).register(locationId: 'PTB', label: 'x'),
      throwsA(
        isA<DataFailure>().having(
          (f) => f.reason,
          'r',
          FailureReason.notPermitted,
        ),
      ),
    );
    await expectLater(
      _service(_withPtb()).register(locationId: 'MNJ', label: 'x'),
      throwsA(
        isA<DataFailure>().having((f) => f.reason, 'r', FailureReason.notFound),
      ),
    );
  });

  test(
    'a real permission denial gives up after the last attempt, storing nothing',
    () async {
      final backend = _withPtb()..denyAll = true;
      final local = MemoryDurableStore();
      await expectLater(
        _service(
          backend,
          local: local,
          attempts: 3,
        ).register(locationId: 'PTB', label: 'x'),
        throwsA(
          isA<DataFailure>().having(
            (f) => f.reason,
            'r',
            FailureReason.notPermitted,
          ),
        ),
      );
      expect(local.disk, isEmpty);
      expect(backend.docs['locations/PTB']!['nextDeviceNo'], 0);
    },
  );

  test('without device.register in the session it fails at once, with no '
      'attempt (BE-9 review)', () async {
    final backend = _withPtb();
    var attempts = 0;
    final s = FirestoreDeviceService(
      backend: backend,
      local: MemoryDurableStore(),
      uid: () => 'sm-ptb',
      session: () => _session(const []),
      clock: () => DateTime.utc(2026, 9, 26, 4, 30),
      sleep: (_) async => attempts++,
    );
    await expectLater(
      s.register(locationId: 'PTB', label: 'x'),
      throwsA(
        isA<DataFailure>().having(
          (f) => f.reason,
          'r',
          FailureReason.notPermitted,
        ),
      ),
    );
    expect(backend.commits, 0);
    expect(attempts, 0);
    expect(backend.docs['locations/PTB']!['nextDeviceNo'], 0);

    // With the permission, but at another location: also at once.
    final other = FirestoreDeviceService(
      backend: backend,
      local: MemoryDurableStore(),
      uid: () => 'sm-ptb',
      session: () => _session(const [Permission.deviceRegister]),
    );
    await expectLater(
      other.register(locationId: 'MNJ', label: 'x'),
      throwsA(isA<DataFailure>()),
    );
    expect(backend.commits, 0);
  });

  test('a registration calls onRegistered once it is stored', () async {
    final registered = <String>[];
    final local = MemoryDurableStore();
    final s = FirestoreDeviceService(
      backend: _withPtb(),
      local: local,
      uid: () => 'sm-ptb',
      session: () => _session(const [Permission.deviceRegister]),
      onRegistered: (d) {
        expect(local.disk[FirestoreDeviceService.deviceIdKey], d.code);
        registered.add(d.code);
      },
    );
    await s.register(locationId: 'PTB', label: 'x');
    expect(registered, ['D01']);
  });

  test('watchDevices lists the location devices', () async {
    final backend = _withPtb();
    await _service(backend).register(locationId: 'PTB', label: 'A');
    final list = await _service(backend).watchDevices('PTB').first;
    expect(list.single.code, 'D01');
  });

  test('Firestore error codes map to failure reasons', () {
    expect(failureReasonOf('unavailable'), FailureReason.offline);
    expect(failureReasonOf('permission-denied'), FailureReason.notPermitted);
    expect(failureReasonOf('not-found'), FailureReason.notFound);
    expect(failureReasonOf('internal'), FailureReason.unknown);
  });
}

SessionContext _session(List<String> permissions) => SessionContext(
  user: const AppUser(
    uid: 'sm-ptb',
    name: 'Store Manager',
    email: 'sm@example.com',
    roleId: SeedRoles.storeManagerId,
    locationId: 'PTB',
    active: true,
    createdBy: 'admin',
  ),
  role: Role(
    id: SeedRoles.storeManagerId,
    name: 'Store Manager',
    permissions: permissions,
    allLocations: false,
  ),
  location: null,
);
