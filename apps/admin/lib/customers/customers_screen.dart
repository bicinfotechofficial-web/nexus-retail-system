import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../data/providers.dart';

/// The customers the switcher selects (D-037): every location's when it
/// says "All locations", otherwise that one location's.
final customersProvider = StreamProvider<List<Customer>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final selected = ref.watch(selectedLocationProvider);
  return selected == null ? repo.watchAllLocations() : repo.watchAll(selected);
});

/// Customers whose name or mobile matches [query] (client side, case
/// insensitive; a mobile also matches when typed with spaces or `+91`).
List<Customer> filterCustomers(List<Customer> customers, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return customers;
  final digits = CustomerValidator.cleanPhone(q);
  return [
    for (final c in customers)
      if (c.name.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          (digits.isNotEmpty && c.phone.contains(digits)))
        c,
  ];
}

/// Customers across locations, read only. Needs `report.all` (router guard).
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customersProvider);
    final all = async.value;
    final selected = ref.watch(selectedLocationProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Customers', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          selected == null
              ? 'Everyone billed at any location, most recent first. Read only.'
              : 'Everyone billed at $selected, most recent first. Read only.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 320,
          child: TextField(
            key: const Key('customer-search'),
            decoration: const InputDecoration(
              labelText: 'Search by name or mobile',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 16),
        if (all == null)
          async.hasError
              ? Text('Could not load customers: ${async.error}')
              : const Center(child: CircularProgressIndicator())
        else ...[
          Text(
            '${filterCustomers(all, _query).length} of ${all.length} customers',
            style: theme.textTheme.bodySmall,
          ),
          if (filterCustomers(all, _query).isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No customers match.', key: Key('customers-empty')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('customers-table'),
                columnSpacing: 32,
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Mobile')),
                  DataColumn(label: Text('WhatsApp')),
                  DataColumn(label: Text('Location')),
                  DataColumn(label: Text('Bills'), numeric: true),
                  DataColumn(label: Text('Total spend'), numeric: true),
                  DataColumn(label: Text('Last bill')),
                ],
                rows: [
                  for (final c in filterCustomers(all, _query))
                    DataRow(
                      key: ValueKey('customer-${c.locationId}-${c.id}'),
                      cells: [
                        DataCell(Text(c.name)),
                        DataCell(Text(c.phone)),
                        DataCell(Text(c.whatsapp ?? 'No WhatsApp')),
                        DataCell(Text(c.locationId ?? '—')),
                        DataCell(Text('${c.billCount}')),
                        DataCell(Text(c.totalSpend.format())),
                        DataCell(
                          Text(
                            c.lastBillAt == null
                                ? '—'
                                : formatBusinessDate(
                                    BusinessDate.of(c.lastBillAt!),
                                  ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
