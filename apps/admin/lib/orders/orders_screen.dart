import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../common/store_picker.dart';
import '../data/providers.dart';

/// The server-side filters of the Orders page: status and due-date range.
/// The store is filtered on the client, because the query spans all stores.
typedef OrderQuery = ({OrderStatus? status, String? dueFrom, String? dueTo});

/// Orders across every store, soonest due first.
final ordersProvider = StreamProvider.family<List<PreOrder>, OrderQuery>(
  (ref, q) => ref
      .watch(orderRepositoryProvider)
      .watchAllLocations(status: q.status, dueFrom: q.dueFrom, dueTo: q.dueTo),
);

/// Soonest due first: by due date, then time (orders without a time last),
/// then order number. Sorted here too, so the page does not depend on the
/// repository's order.
List<PreOrder> sortByDue(Iterable<PreOrder> orders) =>
    [...orders]..sort((a, b) {
      final d = a.dueDate.compareTo(b.dueDate);
      if (d != 0) return d;
      final at = a.dueTime ?? '99:99';
      final bt = b.dueTime ?? '99:99';
      final t = at.compareTo(bt);
      return t != 0 ? t : a.orderNo.compareTo(b.orderNo);
    });

String orderStatusLabel(OrderStatus s) => switch (s) {
  OrderStatus.open => 'Open',
  OrderStatus.delivered => 'Delivered',
  OrderStatus.cancelled => 'Cancelled',
};

/// `HH:mm` as `4:30 PM`.
String formatDueTime(String hhmm) {
  final h = int.parse(hhmm.substring(0, 2));
  final m = hhmm.substring(3);
  final suffix = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $suffix';
}

/// Every store's pre-orders (D-043), read only. Needs `report.all` (router
/// guard).
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String? _store;
  bool _storeTouched = false;
  OrderStatus? _status;
  String? _from;
  String? _to;

  Future<String?> _pickDate(String? current, String today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: pickerDate(current ?? today),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    return picked == null ? null : businessDateOfPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final locations = ref.watch(locationsProvider).value ?? const <Location>[];
    final query = (status: _status, dueFrom: _from, dueTo: _to);
    final async = ref.watch(ordersProvider(query));
    final all = async.value;
    final store = _storeTouched ? _store : ref.watch(selectedLocationProvider);

    final shown = all == null
        ? const <PreOrder>[]
        : sortByDue([
            for (final o in all)
              if (store == null || o.locationId == store) o,
          ]);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Orders', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Pre-orders at every store, soonest due first. Read only.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KeyedSubtree(
              key: const Key('orders-store'),
              child: StorePicker(
                locations: locations,
                value: store,
                allowAll: true,
                onChanged: (v) => setState(() {
                  _store = v;
                  _storeTouched = true;
                }),
              ),
            ),
            SizedBox(
              key: const Key('orders-status'),
              width: 200,
              child: DropdownButtonFormField<OrderStatus?>(
                key: ValueKey(_status),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                onChanged: (v) => setState(() => _status = v),
                items: [
                  const DropdownMenuItem<OrderStatus?>(
                    value: null,
                    child: Text('Any status'),
                  ),
                  for (final s in OrderStatus.values)
                    DropdownMenuItem<OrderStatus?>(
                      value: s,
                      child: Text(orderStatusLabel(s)),
                    ),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const Key('orders-from'),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                _from == null
                    ? 'Due from'
                    : 'From ${formatBusinessDate(_from!)}',
              ),
              onPressed: () async {
                final d = await _pickDate(_from, today);
                if (d != null) setState(() => _from = d);
              },
            ),
            OutlinedButton.icon(
              key: const Key('orders-to'),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                _to == null ? 'Due to' : 'To ${formatBusinessDate(_to!)}',
              ),
              onPressed: () async {
                final d = await _pickDate(_to, today);
                if (d != null) setState(() => _to = d);
              },
            ),
            if (_from != null || _to != null)
              TextButton(
                key: const Key('orders-clear-dates'),
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                child: const Text('Clear dates'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (all == null)
          async.hasError
              ? Text('Could not load orders: ${async.error}')
              : const Center(child: CircularProgressIndicator())
        else ...[
          Text(
            '${shown.length} ${shown.length == 1 ? 'order' : 'orders'}',
            key: const Key('orders-count'),
            style: theme.textTheme.bodySmall,
          ),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No orders match.', key: Key('orders-empty')),
            )
          else
            for (final o in shown) _OrderCard(order: o, today: today),
        ],
      ],
    );
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({required this.order, required this.today});

  final PreOrder order;
  final String today;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  static const int _previewChars = 80;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = '${o.locationId}-${o.id}';
    final due = o.isOpen
        ? OrderValidator.dueState(o.dueDate, widget.today)
        : null;
    final urgent = due == OrderDue.today || due == OrderDue.overdue;
    final long =
        o.description.length > _previewChars || o.description.contains('\n');
    final preview = o.description.replaceAll('\n', ' ');

    Widget field(String label, String value, {Key? key}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, key: key, style: theme.textTheme.bodyMedium),
      ],
    );

    final cancel = o.cancel;
    return Card(
      key: Key('order-$id'),
      color: urgent ? scheme.errorContainer : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(o.orderNo, style: theme.textTheme.titleMedium),
                Chip(
                  key: Key('order-status-$id'),
                  label: Text(orderStatusLabel(o.status)),
                  visualDensity: VisualDensity.compact,
                ),
                if (urgent)
                  Chip(
                    key: Key('order-flag-$id'),
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      due == OrderDue.overdue ? 'Overdue' : 'Due today',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                field('Store', o.locationId ?? '—'),
                field('Customer', o.customer.name),
                field('Mobile', o.customer.phone),
                field(
                  'Due',
                  o.dueTime == null
                      ? formatBusinessDate(o.dueDate)
                      : '${formatBusinessDate(o.dueDate)}, '
                            '${formatDueTime(o.dueTime!)}',
                  key: Key('order-due-$id'),
                ),
                field('Price', o.price.format(), key: Key('order-price-$id')),
                field(
                  'Advance',
                  o.advance.format(),
                  key: Key('order-advance-$id'),
                ),
                field(
                  'Balance',
                  o.balance.format(),
                  key: Key('order-balance-$id'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Description', style: theme.textTheme.labelSmall),
            Text(
              long && !_expanded ? preview : o.description,
              key: Key('order-desc-$id'),
              maxLines: long && !_expanded ? 2 : null,
              overflow: long && !_expanded ? TextOverflow.ellipsis : null,
            ),
            if (long)
              TextButton(
                key: Key('order-expand-$id'),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show all'),
              ),
            if (cancel != null) ...[
              const SizedBox(height: 8),
              Text('Cancelled: ${cancel.reason}', key: Key('order-reason-$id')),
              Text(
                'Refunded ${cancel.refunded.format()} of the '
                '${o.advance.format()} advance',
                key: Key('order-refund-$id'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
