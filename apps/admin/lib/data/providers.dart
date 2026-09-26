import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// The `nexus_data` interfaces the console uses. Each one must be overridden
/// at startup: with the fakes (`--dart-define=FAKE_DATA=true`) or with the
/// Firestore implementations from `nexus_data`.
final authServiceProvider = Provider<AuthService>(
  (ref) => throw UnimplementedError('authServiceProvider is not overridden'),
);

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) =>
      throw UnimplementedError('locationRepositoryProvider is not overridden'),
);

final summaryRepositoryProvider = Provider<SummaryRepository>(
  (ref) =>
      throw UnimplementedError('summaryRepositoryProvider is not overridden'),
);

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) =>
      throw UnimplementedError('stockRepositoryProvider is not overridden'),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) =>
      throw UnimplementedError('catalogRepositoryProvider is not overridden'),
);

final catalogServiceProvider = Provider<CatalogService>(
  (ref) => throw UnimplementedError('catalogServiceProvider is not overridden'),
);

final locationServiceProvider = Provider<LocationService>(
  (ref) =>
      throw UnimplementedError('locationServiceProvider is not overridden'),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => throw UnimplementedError('userRepositoryProvider is not overridden'),
);

final userServiceProvider = Provider<UserService>(
  (ref) => throw UnimplementedError('userServiceProvider is not overridden'),
);

final deviceServiceProvider = Provider<DeviceService>(
  (ref) => throw UnimplementedError('deviceServiceProvider is not overridden'),
);

/// The current instant. Tests override it to pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Today's business date in IST (D-022).
final todayProvider = Provider<String>(
  (ref) => BusinessDate.of(ref.watch(clockProvider)()),
);

/// The signed-in session, or null when signed out.
final sessionProvider = NotifierProvider<SessionNotifier, SessionContext?>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<SessionContext?> {
  @override
  SessionContext? build() {
    final auth = ref.watch(authServiceProvider);
    final sub = auth.session.listen((s) => state = s);
    ref.onDispose(() {
      unawaited(sub.cancel());
    });
    return auth.current;
  }
}

/// Every location, as the data layer returns them.
final locationsProvider = StreamProvider<List<Location>>(
  (ref) => ref.watch(locationRepositoryProvider).watchLocations(),
);

/// The top-bar location switcher. Null means "All locations".
final selectedLocationProvider =
    NotifierProvider<SelectedLocationNotifier, String?>(
      SelectedLocationNotifier.new,
    );

class SelectedLocationNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? locationId) => state = locationId;
}

/// Whether the session may pick "All locations".
bool canSeeAllLocations(SessionContext session) =>
    session.can(Permission.reportAll);

/// The locations the session may report on, in code order.
List<Location> reportableLocations(
  SessionContext session,
  List<Location> locations,
) {
  final result = [
    for (final l in locations)
      if (l.active &&
          (session.canAt(Permission.reportOwn, l.code) ||
              session.can(Permission.reportAll)))
        l,
  ]..sort((a, b) => a.code.compareTo(b.code));
  return result;
}

/// The locations the dashboard and reports cover, after applying the
/// switcher. Empty while loading or when signed out.
final scopeLocationsProvider = Provider<List<Location>>((ref) {
  final session = ref.watch(sessionProvider);
  final all = ref.watch(locationsProvider).value;
  if (session == null || all == null) return const [];
  final allowed = reportableLocations(session, all);
  final selected = ref.watch(selectedLocationProvider);
  if (selected != null) {
    return [
      for (final l in allowed)
        if (l.code == selected) l,
    ];
  }
  if (canSeeAllLocations(session)) return allowed;
  // Without report.all the default is the user's own location only.
  return allowed.take(1).toList();
});

/// Product names by ID, for top-product lists. Unknown IDs fall back to the
/// ID itself.
final productNamesProvider = StreamProvider<Map<String, String>>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .watchAll()
      .map((products) => {for (final p in products) p.id: p.name}),
);
