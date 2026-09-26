import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'catalog/catalog_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'data/providers.dart';
import 'devices/devices_screen.dart';
import 'locations/locations_screen.dart';
import 'login/login_screen.dart';
import 'reports/reports_screen.dart';
import 'shell/admin_shell.dart';
import 'shell/destinations.dart';
import 'shell/permission_guard.dart';
import 'stock/stock_screen.dart';
import 'users/users_screen.dart';

class _SessionChanges extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Signed out → `/login`; signed in → the shell. Each page sits behind a
/// [PermissionGuard] for its destination's permissions.
final routerProvider = Provider<GoRouter>((ref) {
  final changes = _SessionChanges();
  ref.listen(sessionProvider, (_, _) => changes.ping());

  final router = GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: changes,
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.matchedLocation, child: child),
        routes: [
          _guarded('/dashboard', const DashboardScreen()),
          _guarded('/reports', const ReportsScreen()),
          _guarded('/stock', const StockScreen()),
          _guarded('/catalog', const CatalogScreen()),
          _guarded('/locations', const LocationsScreen()),
          _guarded('/users', const UsersScreen()),
          _guarded('/devices', const DevicesScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    changes.dispose();
  });
  return router;
});

GoRoute _guarded(String path, Widget page) => GoRoute(
  path: path,
  pageBuilder: (context, state) => NoTransitionPage(
    child: PermissionGuard(anyOf: destinationFor(path).anyOf, child: page),
  ),
);
