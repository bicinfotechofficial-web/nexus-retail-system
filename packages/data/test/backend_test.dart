// The composition root wired on fake_cloud_firestore and firebase_auth_mocks:
// every service is built, and a sign-in, bill, stock-in and cancel go all
// the way to the (fake) database. fake_cloud_firestore can't take FieldPath
// keys in `update`, so the plans are applied with dotted string keys here,
// and the device doc is seeded instead of registered.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_data/src/firestore/plan_adapter.dart';

import 'repos/docs.dart';
import 'write/support.dart' show cashBill, settle;

void main() {
  late FakeFirebaseFirestore db;
  late NexusBackend backend;
  late MemoryDurableStore store;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await put(
      db,
      FirestorePaths.role(SeedRoles.storeManagerId),
      role(
        SeedRoles.storeManagerId,
        permissions: SeedRoles.storeManagerPermissions,
      ).toMap(),
    );
    await put(db, FirestorePaths.user('sm1'), appUser('sm1').toMap());
    await put(db, FirestorePaths.location('PTB'), {
      ...location('PTB').toMap(),
      'nextDeviceNo': 0,
    });
    await put(db, FirestorePaths.rawMaterial('flour'), {
      'name': 'Flour',
      'unit': 'G',
      'active': true,
      'createdBy': 'admin1',
    });
    store = MemoryDurableStore();
    backend = await NexusBackend.assemble(
      firestore: db,
      firebaseAuth: MockFirebaseAuth(
        mockUser: MockUser(uid: 'sm1', email: 'sm1@example.com'),
      ),
      deviceStore: store,
      ledger: MemorySyncLedger(),
      committer: _FakeDbCommitter(db),
      network: ManualNetworkMonitor(),
      observeLifecycle: false,
    );
  });

  tearDown(() => backend.dispose());

  test('sign in, bill, stock in and cancel through the one factory', () async {
    expect(backend.sync.lastSyncAt, isNull);
    await backend.auth.signIn(email: 'sm1@example.com', password: 'x');
    await settle();
    expect(
      backend.sync.lastSyncAt,
      isNotNull,
      reason: 'an interactive sign-in counts as a sync',
    );
    final signInSync = backend.sync.lastSyncAt;

    await put(db, FirestorePaths.device('PTB', 'D01'), {
      ...const Device(
        code: 'D01',
        label: 'Counter 1',
        registeredBy: 'sm1',
        lastBillSeq: 0,
        retired: false,
      ).toMap(),
    });
    await store.write(FirestoreDeviceService.deviceIdKey, 'D01');
    await store.write(FirestoreDeviceService.locationIdKey, 'PTB');
    expect(backend.devices.deviceId, 'D01');
    expect(signInSync, isNotNull);

    expect(backend.offlineGuard.evaluate(), isA<WithinLimit>());
    final bill = await backend.sales.createBill(cashBill);
    expect(bill.id, 'D01-000001');
    final stored = await db.doc(FirestorePaths.bill('PTB', bill.id)).get();
    expect(stored.data()!['billNo'], 'PTB-D01-000001');
    final dev = await db.doc(FirestorePaths.device('PTB', 'D01')).get();
    expect(dev.data()!['lastBillSeq'], 1);
    expect(store.disk[CounterStore.key('D01', SeqKind.bill)], 1);

    final m = await backend.stock.stockIn(const [
      StockLineInput(itemKey: 'RM_flour', qty: 2500),
    ]);
    final flour = await db
        .doc(FirestorePaths.stockItem('PTB', 'RM_flour'))
        .get();
    expect(flour.data()!['qty'], 2500);
    expect(flour.data()!['lastMovementId'], m.id);

    expect(backend.ledger.entries.map((e) => e.path), [
      'locations/PTB/bills/D01-000001',
      'locations/PTB/movements/D01-000001',
      'locations/PTB/movements/D01-M000001',
    ]);

    // The bill reads back through the repository the cancel uses.
    final cancelled = await backend.sales.cancelBill(
      billId: bill.id,
      reason: 'Wrong cake',
    );
    expect(cancelled.status, BillStatus.cancelled);
    final after = await backend.salesRepo.getBill('PTB', bill.id);
    expect(after!.status, BillStatus.cancelled);
  });

  test('FirestorePlanCommitter commits a batch and hands back the server '
      'outcome, locally-first or awaited', () async {
    for (final awaitServer in [false, true]) {
      final path = FirestorePaths.rawMaterial('cocoa-$awaitServer');
      final plan = (PlanBuilder()..create(path, {'name': 'Cocoa'})).build();
      final committed = await FirestorePlanCommitter(
        db,
        awaitServer: awaitServer,
      ).commit(plan);
      await committed.serverAck;
      expect((await db.doc(path).get()).data(), {'name': 'Cocoa'});
    }
  });

  test('the sync backend reads the server doc, and a lastSeenAt plan is a '
      'server-timestamp update', () async {
    final sb = FirestoreSyncBackend(db, FirestorePlanCommitter(db));
    expect(await sb.check(FirestorePaths.user('sm1')), DocCheck.exists);
    expect(await sb.check(FirestorePaths.user('nobody')), DocCheck.missing);
    final plan = OfflinePlans.lastSeen(locationId: 'PTB', deviceId: 'D01');
    expect(plan.ops.single.kind, WriteKind.update);
    expect(plan.ops.single.data, {'lastSeenAt': serverTimestamp});
  });
}

final class _FakeDbCommitter implements PlanCommitter {
  _FakeDbCommitter(this.db);

  final FakeFirebaseFirestore db;

  @override
  Future<CommittedPlan> commit(WritePlan plan) async {
    final batch = db.batch();
    for (final op in plan.ops) {
      final ref = db.doc(op.path);
      final data = PlanAdapter.encodeMap(op.data);
      switch (op.kind) {
        case WriteKind.create:
          batch.set(ref, data);
        case WriteKind.setMerge:
          batch.set(ref, data, SetOptions(merge: true));
        case WriteKind.update:
          batch.update(ref, data);
      }
    }
    await batch.commit();
    return CommittedPlan(plan, Future.value());
  }
}
