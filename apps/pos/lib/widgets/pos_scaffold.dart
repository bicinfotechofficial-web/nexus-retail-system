import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/destinations.dart';
import '../app/providers.dart';
import '../app/router.dart';
import '../features/billing/cart.dart';
import 'offline_banner.dart';
import 'sync_chip.dart';

/// The app bar with the sync chip, and the permission-aware drawer.
class PosScaffold extends ConsumerWidget {
  const PosScaffold({
    required this.title,
    required this.body,
    this.showDrawer = true,
    this.actions = const [],
    this.bottom,
    super.key,
  });

  final String title;
  final Widget body;
  final bool showDrawer;
  final List<Widget> actions;

  /// Pinned below the body, e.g. the Save button.
  final Widget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final low = showDrawer ? ref.watch(_visibleLowStockProvider) : 0;
    return Scaffold(
      appBar: AppBar(
        leading: showDrawer
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: Badge(
                    key: const Key('menu-badge'),
                    isLabelVisible: low > 0,
                    label: Text('$low'),
                    child: const Icon(Icons.menu),
                  ),
                ),
              )
            : null,
        title: Text(title),
        actions: [...actions, const SyncChip()],
      ),
      drawer: showDrawer ? const PosDrawer() : null,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OfflineBanner(),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: bottom == null ? null : SafeArea(child: bottom!),
    );
  }
}

/// How many items are low, for a session that may open Stock (D-015).
final _visibleLowStockProvider = Provider<int>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !Destinations.stock.allowedFor(session)) return 0;
  return ref.watch(lowStockProvider).value?.length ?? 0;
});

class PosDrawer extends ConsumerWidget {
  const PosDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final items = session == null
        ? const <Destination>[]
        : Destinations.allowedFor(session);
    final here = GoRouterState.of(context).uri.path;
    final selected = items.indexWhere((d) => d.path == here);
    final low = ref.watch(_visibleLowStockProvider);
    final errors = ref.watch(syncErrorsProvider).value?.length ?? 0;
    final syncIndex = session == null ? null : items.length;
    final onSync = here == Routes.syncHealth;
    return NavigationDrawer(
      selectedIndex: onSync ? syncIndex : (selected < 0 ? null : selected),
      onDestinationSelected: (i) {
        Navigator.of(context).pop();
        context.go(i < items.length ? items[i].path : Routes.syncHealth);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
          child: Text(
            'Caramel Cottage',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (session != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 16, 12),
            child: Text(
              [session.user.name, ?session.location?.name].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final d in items)
          NavigationDrawerDestination(
            key: Key('nav-${d.label}'),
            icon: d == Destinations.stock && low > 0
                ? Badge(
                    key: const Key('low-stock-badge'),
                    label: Text('$low'),
                    child: Icon(d.icon),
                  )
                : Icon(d.icon),
            label: Text(d.label),
          ),
        if (session != null) ...[
          const Divider(indent: 28, endIndent: 28),
          NavigationDrawerDestination(
            key: const Key('nav-Sync health'),
            icon: errors > 0
                ? Badge(
                    key: const Key('sync-errors-badge'),
                    label: Text('$errors'),
                    child: const Icon(Icons.sync_problem),
                  )
                : const Icon(Icons.sync),
            label: const Text('Sync health'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: ListTile(
              key: const Key('sign-out'),
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                Navigator.of(context).pop();
                // The next login must not inherit this cart.
                ref.read(cartProvider.notifier).clear();
                await ref.read(authServiceProvider).signOut();
              },
            ),
          ),
        ],
      ],
    );
  }
}
