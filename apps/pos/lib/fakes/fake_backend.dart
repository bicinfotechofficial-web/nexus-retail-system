import 'package:flutter_riverpod/misc.dart';
import 'package:nexus_data/nexus_data.dart';

import '../app/providers.dart';
import 'fake_data.dart';
import 'fake_printer.dart';

export 'fake_data.dart';
export 'fake_printer.dart';
export 'seed.dart';

/// Every fake, wired together, plus the provider overrides that install
/// them. Used by `FAKE_DATA=true` and by the widget tests.
final class FakeBackend {
  FakeBackend({
    SessionContext? session,
    SyncStatus syncStatus = const Online(),
    DateTime Function()? now,
  }) : auth = FakeAuthService(session),
       sync = FakeSyncService(syncStatus),
       _now = now ?? DateTime.now {
    sales = FakeSalesService(auth: auth, bills: bills, now: _now);
  }

  final DateTime Function() _now;
  final FakeAuthService auth;
  final FakeCatalogRepository catalog = FakeCatalogRepository();
  final FakeSalesRepository bills = FakeSalesRepository();
  late final FakeSalesService sales;
  final FakeSyncService sync;
  final FakeOfflineGuard offline = FakeOfflineGuard();
  final FakeDeviceService device = FakeDeviceService();
  final FakePrinterService printer = FakePrinterService();

  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    catalogRepositoryProvider.overrideWithValue(catalog),
    salesServiceProvider.overrideWithValue(sales),
    salesRepositoryProvider.overrideWithValue(bills),
    syncServiceProvider.overrideWithValue(sync),
    offlineGuardProvider.overrideWithValue(offline),
    deviceServiceProvider.overrideWithValue(device),
    printerServiceProvider.overrideWithValue(printer),
    clockProvider.overrideWithValue(_now),
  ];
}
