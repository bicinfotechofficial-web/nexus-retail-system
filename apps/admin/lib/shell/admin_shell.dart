import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import 'destinations.dart';
import 'permission_guard.dart';

/// Wide screens get a permanent side nav; narrow ones a drawer.
const double wideLayoutMinWidth = 900;

/// The signed-in frame: side nav, top bar with the location switcher and
/// the user menu, and the current page.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  /// The current route path, used to highlight the nav entry.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final visible = [
      for (final d in destinations)
        if (hasAnyPermission(session, d.anyOf)) d,
    ];
    final current = visible.indexWhere((d) => location.startsWith(d.path));
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

    final appBar = AppBar(
      title: const Text('Caramel Cottage Admin'),
      actions: [
        const LocationSwitcher(),
        const SizedBox(width: 8),
        if (session != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                session.user.email,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () {
            unawaited(ref.read(authServiceProvider).signOut());
          },
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            if (visible.isNotEmpty)
              NavigationRail(
                extended: true,
                selectedIndex: current < 0 ? null : current,
                onDestinationSelected: (i) => context.go(visible[i].path),
                destinations: [
                  for (final d in visible)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                ],
              ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      drawer: NavigationDrawer(
        selectedIndex: current < 0 ? null : current,
        onDestinationSelected: (i) {
          Navigator.of(context).pop();
          context.go(visible[i].path);
        },
        children: [
          const SizedBox(height: 16),
          for (final d in visible)
            NavigationDrawerDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      ),
      body: child,
    );
  }
}

/// "All locations" or a single one. Offers only the locations the session
/// may report on, and "All" only with `report.all`.
class LocationSwitcher extends ConsumerWidget {
  const LocationSwitcher({super.key});

  static const String allLabel = 'All locations';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final locations = ref.watch(locationsProvider).value;
    if (session == null || locations == null) return const SizedBox.shrink();
    final allowed = reportableLocations(session, locations);
    final showAll = canSeeAllLocations(session);
    var selected = ref.watch(selectedLocationProvider);
    if (selected != null && !allowed.any((l) => l.code == selected)) {
      selected = null;
    }
    if (!showAll && selected == null && allowed.isNotEmpty) {
      selected = allowed.first.code;
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        key: const Key('location-switcher'),
        value: selected,
        icon: const Icon(Icons.store_outlined),
        onChanged: (v) => ref.read(selectedLocationProvider.notifier).select(v),
        items: [
          if (showAll)
            const DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
          for (final l in allowed)
            DropdownMenuItem<String?>(
              value: l.code,
              child: Text('${l.name} (${l.code})'),
            ),
        ],
      ),
    );
  }
}
