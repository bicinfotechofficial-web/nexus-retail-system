import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

/// The data and printer interfaces the app builds against (D-026). Each is
/// overridden at startup: with fakes under `FAKE_DATA=true`, and with the
/// `nexus_data` and `nexus_printer` implementations once they are merged.
Never _notConfigured(String what) => throw UnimplementedError(
  '$what has no implementation yet. Run with --dart-define=FAKE_DATA=true.',
);

final authServiceProvider = Provider<AuthService>(
  (ref) => _notConfigured('AuthService'),
);
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => _notConfigured('CatalogRepository'),
);
final salesServiceProvider = Provider<SalesService>(
  (ref) => _notConfigured('SalesService'),
);
final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => _notConfigured('SalesRepository'),
);
final syncServiceProvider = Provider<SyncService>(
  (ref) => _notConfigured('SyncService'),
);
final offlineGuardProvider = Provider<OfflineGuard>(
  (ref) => _notConfigured('OfflineGuard'),
);
final deviceServiceProvider = Provider<DeviceService>(
  (ref) => _notConfigured('DeviceService'),
);
final printerServiceProvider = Provider<PrinterService>(
  (ref) => _notConfigured('PrinterService'),
);

/// The device clock. Tests override it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The signed-in user, role and location. Null when signed out.
final sessionProvider = StreamProvider<SessionContext?>(
  (ref) => ref.watch(authServiceProvider).session,
);

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).status,
);

/// Products sellable at the session's location, in `sortOrder`.
final sellableProductsProvider = StreamProvider<List<Product>>((ref) {
  final locationId = ref.watch(
    sessionProvider.select((s) => s.value?.location?.code),
  );
  if (locationId == null) return Stream.value(const []);
  return ref.watch(catalogRepositoryProvider).watchSellable(locationId);
});
