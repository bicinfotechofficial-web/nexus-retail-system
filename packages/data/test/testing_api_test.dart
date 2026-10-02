// The test-support entry point (QA-043) has what the device scenarios'
// `TestDevice` needs. It can't open a device here (no emulator); this checks
// the API shape at compile time and the parts that run without Firebase.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_data/testing.dart';

/// Compiles only if [NexusTestDevice] matches the scenarios' `TestDevice`.
// ignore: unreachable_from_main
Future<void> _shape(NexusTestDevice d) async {
  final AuthService auth = d.auth;
  final DeviceService devices = d.devices;
  final SalesService sales = d.sales;
  final SalesRepository salesRepo = d.salesRepo;
  final StockService stock = d.stock;
  final StockRepository stockRepo = d.stockRepo;
  final SummaryRepository summaries = d.summaries;
  final CatalogService catalog = d.catalog;
  final CatalogRepository catalogRepo = d.catalogRepo;
  final CustomerRepository customers = d.customers;
  final SyncService sync = d.sync;
  final OfflineGuard guard = d.offlineGuard;
  await d.goOffline();
  await d.goOnline();
  final NexusTestDevice restarted = await d.restart();
  await d.reapplyLastPlan();
  await restarted.dispose();
  expect([
    auth,
    devices,
    sales,
    salesRepo,
    stock,
    stockRepo,
    summaries,
    catalog,
    catalogRepo,
    customers,
    sync,
    guard,
  ], isNotEmpty);
  expect(d.app.name, isNotEmpty);
}

void main() {
  test('emulator defaults match the Firebase emulator config', () {
    const h = EmulatorHost(host: '10.0.2.2');
    expect((h.firestorePort, h.authPort), (8080, 9099));
    expect(_shape, isNotNull);
  });

  test(
    'the recording committer remembers the last plan it committed',
    () async {
      final inner = _Committer();
      final r = RecordingPlanCommitter(inner);
      expect(r.lastPlan, isNull);
      final plan = (PlanBuilder()..create('rawMaterials/x', {'name': 'X'}))
          .build();
      await r.commit(plan);
      expect(r.lastPlan, same(plan));
      inner.fail = true;
      final other = (PlanBuilder()..create('rawMaterials/y', {'name': 'Y'}))
          .build();
      await expectLater(r.commit(other), throwsA(isA<DataFailure>()));
      expect(r.lastPlan, same(plan), reason: 'a failed commit is not recorded');
    },
  );
}

final class _Committer implements PlanCommitter {
  bool fail = false;

  @override
  Future<CommittedPlan> commit(WritePlan plan) async {
    if (fail) throw const DataFailure(FailureReason.unknown);
    return CommittedPlan(plan, Future.value());
  }
}
