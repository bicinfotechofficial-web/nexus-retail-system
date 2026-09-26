import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../data/providers.dart';
import 'location_form.dart';

/// Every location with its receipt and offline settings. Creating and
/// editing need `location.manage` (the router guards the whole page).
class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(sessionProvider)?.can(Permission.locationManage) ?? false;
    final async = ref.watch(locationsProvider);
    final locations = async.value;
    if (locations == null) {
      return async.hasError
          ? Center(child: Text('Could not load locations: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    final sorted = [...locations]..sort((a, b) => a.code.compareTo(b.code));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Locations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canManage)
              FilledButton.icon(
                key: const Key('location-add'),
                onPressed: () => showLocationForm(context),
                icon: const Icon(Icons.add),
                label: const Text('New location'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('locations-table'),
            columnSpacing: 32,
            columns: const [
              DataColumn(label: Text('Code')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Phone')),
              DataColumn(
                label: Tooltip(
                  message:
                      'Billing stops after the limit without a sync; the PIN '
                      'override extends it',
                  child: Text('Offline limit + override'),
                ),
              ),
              DataColumn(label: Text('Discount cap'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final l in sorted)
                DataRow(
                  key: ValueKey('location-${l.code}'),
                  cells: [
                    DataCell(Text(l.code, key: Key('code-${l.code}'))),
                    DataCell(Text(l.name)),
                    DataCell(Text(l.phone)),
                    DataCell(
                      Text(
                        '${l.offlineLimitHours} h + '
                        '${l.overrideExtensionHours} h',
                        key: Key('offline-${l.code}'),
                      ),
                    ),
                    DataCell(
                      Text(
                        l.maxDiscountPct == null
                            ? 'No cap'
                            : '${l.maxDiscountPct}%',
                        key: Key('cap-${l.code}'),
                      ),
                    ),
                    DataCell(Text(l.active ? 'Active' : 'Inactive')),
                    DataCell(
                      canManage
                          ? IconButton(
                              key: Key('edit-location-${l.code}'),
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  showLocationForm(context, existing: l),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
