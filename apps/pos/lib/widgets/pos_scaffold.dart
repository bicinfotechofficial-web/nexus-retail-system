import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/destinations.dart';
import '../app/providers.dart';
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
      body: SafeArea(bottom: bottom == null, child: body),
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
    return NavigationDrawer(
      selectedIndex: selected < 0 ? null : selected,
      onDestinationSelected: (i) {
        Navigator.of(context).pop();
        context.go(items[i].path);
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
      ],
    );
  }
}
