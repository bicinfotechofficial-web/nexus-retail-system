import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../data/providers.dart';

/// The text for a bill's customer fields. A bill made before D-034 has no
/// customer, and every field shows a dash.
String billCustomerName(Bill b) => b.customer?.name ?? '—';

String billCustomerMobile(Bill b) => b.customer?.phone ?? '—';

/// "No WhatsApp" only when the bill has a customer who isn't on WhatsApp.
String billCustomerWhatsapp(Bill b) {
  final c = b.customer;
  if (c == null) return '—';
  return c.whatsapp ?? 'No WhatsApp';
}

/// A bill with the location it was made at.
typedef LocatedBill = ({String locationId, Bill bill});

/// The business date the Bills screen shows. Null means today.
final billsDateProvider = NotifierProvider<BillsDateNotifier, String?>(
  BillsDateNotifier.new,
);

class BillsDateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? date) => state = date;
}

/// The bills of the day at every location the switcher covers, newest first.
final billsProvider = StreamProvider<List<LocatedBill>>((ref) {
  final repo = ref.watch(salesRepositoryProvider);
  final String date = ref.watch(billsDateProvider) ?? ref.watch(todayProvider);
  final locations = ref.watch(scopeLocationsProvider);
  return _combine([
    for (final l in locations)
      repo
          .watchBills(l.code, date)
          .map(
            (bills) => [for (final b in bills) (locationId: l.code, bill: b)],
          ),
  ]);
});

Stream<List<LocatedBill>> _combine(List<Stream<List<LocatedBill>>> streams) {
  if (streams.isEmpty) return Stream.value(const []);
  return Stream.multi((c) {
    final latest = List<List<LocatedBill>?>.filled(streams.length, null);
    final subs = [
      for (var i = 0; i < streams.length; i++)
        streams[i].listen((v) {
          latest[i] = v;
          if (latest.every((e) => e != null)) {
            c.add(
              [for (final l in latest) ...l!]..sort(
                (a, b) =>
                    b.bill.clientCreatedAt.compareTo(a.bill.clientCreatedAt),
              ),
            );
          }
        }, onError: c.addError),
    ];
    c.onCancel = () => Future.wait([for (final s in subs) s.cancel()]);
  });
}

/// Bills of one day, with their customer (D-034). Read only.
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final date = ref.watch(billsDateProvider) ?? today;
    final async = ref.watch(billsProvider);
    final bills = async.value;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Bills', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              key: const Key('bills-prev'),
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => ref
                  .read(billsDateProvider.notifier)
                  .select(BusinessDate.addDays(date, -1)),
            ),
            TextButton.icon(
              key: const Key('bills-date'),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(formatBusinessDate(date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: pickerDate(today),
                  initialDate: pickerDate(date),
                  currentDate: pickerDate(today),
                );
                if (picked != null) {
                  ref
                      .read(billsDateProvider.notifier)
                      .select(businessDateOfPicked(picked));
                }
              },
            ),
            IconButton(
              key: const Key('bills-next'),
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: date.compareTo(today) >= 0
                  ? null
                  : () => ref
                        .read(billsDateProvider.notifier)
                        .select(BusinessDate.addDays(date, 1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (bills == null)
          async.hasError
              ? Text('Could not load bills: ${async.error}')
              : const Center(child: CircularProgressIndicator())
        else if (bills.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No bills on this day.', key: Key('bills-empty')),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('bills-table'),
              showCheckboxColumn: false,
              columnSpacing: 28,
              columns: const [
                DataColumn(label: Text('Bill')),
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Customer')),
                DataColumn(label: Text('Mobile')),
                DataColumn(label: Text('WhatsApp')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('Status')),
              ],
              rows: [
                for (final e in bills)
                  DataRow(
                    key: ValueKey('bill-${e.locationId}-${e.bill.id}'),
                    onSelectChanged: (_) => showDialog<void>(
                      context: context,
                      builder: (_) => BillDetailDialog(bill: e.bill),
                    ),
                    cells: [
                      DataCell(Text(e.bill.billNo)),
                      DataCell(Text(formatInstantIst(e.bill.clientCreatedAt))),
                      DataCell(
                        Text(
                          billCustomerName(e.bill),
                          key: Key('bill-customer-${e.bill.id}'),
                        ),
                      ),
                      DataCell(
                        Text(
                          billCustomerMobile(e.bill),
                          key: Key('bill-mobile-${e.bill.id}'),
                        ),
                      ),
                      DataCell(
                        Text(
                          billCustomerWhatsapp(e.bill),
                          key: Key('bill-whatsapp-${e.bill.id}'),
                        ),
                      ),
                      DataCell(Text(e.bill.total.format())),
                      DataCell(
                        Text(
                          e.bill.status == BillStatus.cancelled
                              ? 'Cancelled'
                              : 'Completed',
                        ),
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

/// One bill: customer, lines, totals and payments. Read only.
class BillDetailDialog extends StatelessWidget {
  const BillDetailDialog({required this.bill, super.key});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value, Key key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, key: key)),
        ],
      ),
    );
    return AlertDialog(
      title: Text(bill.billNo),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer', style: theme.textTheme.titleSmall),
              row('Name', billCustomerName(bill), const Key('detail-name')),
              row(
                'Mobile',
                billCustomerMobile(bill),
                const Key('detail-mobile'),
              ),
              row(
                'WhatsApp',
                billCustomerWhatsapp(bill),
                const Key('detail-whatsapp'),
              ),
              const SizedBox(height: 12),
              Text('Items', style: theme.textTheme.titleSmall),
              for (final l in bill.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('${l.qty} × ${l.name}')),
                      Text(l.lineTotal.format()),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('Total')),
                  Text(bill.total.format(), key: const Key('detail-total')),
                ],
              ),
              const SizedBox(height: 12),
              Text('Payments', style: theme.textTheme.titleSmall),
              for (final p in bill.payments)
                Row(
                  children: [
                    Expanded(child: Text(paymentModeLabel(p.mode))),
                    Text(p.amount.format()),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                'Served by ${bill.servedBy.name}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('detail-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
