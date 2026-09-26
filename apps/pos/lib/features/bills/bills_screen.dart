import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/date_bar.dart';
import '../../widgets/pos_scaffold.dart';

/// Bills of one business day, today by default, plus find by bill number
/// (POS-7). Tapping a bill opens its detail.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  /// Null follows today, so the list rolls over at midnight IST.
  String? _date;
  final _search = TextEditingController();
  bool _finding = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// What the Store Manager typed, as a full bill number. `123` means bill
  /// 123 of this device, and `D02-45` bill 45 of device D02, at this store.
  static String? normalize(String input, String location, String? deviceId) {
    final t = input.trim().toUpperCase();
    if (t.isEmpty) return null;
    final seqOnly = RegExp(r'^\d{1,6}$');
    final devSeq = RegExp(r'^(D\d{2})-(\d{1,6})$');
    if (seqOnly.hasMatch(t) && deviceId != null) {
      final seq = int.parse(t);
      if (seq < 1) return null;
      return Ids.billNo(location, Ids.billId(deviceId, seq));
    }
    final m = devSeq.firstMatch(t);
    if (m != null) {
      final seq = int.parse(m.group(2)!);
      if (seq < 1) return null;
      return Ids.billNo(location, Ids.billId(m.group(1)!, seq));
    }
    return t;
  }

  Future<void> _find() async {
    if (_finding) return;
    final loc = ref.read(locationCodeProvider);
    if (loc == null) return;
    final billNo = normalize(
      _search.text,
      loc,
      ref.read(deviceServiceProvider).deviceId,
    );
    if (billNo == null) return;
    setState(() => _finding = true);
    Bill? bill;
    String? error;
    try {
      bill = await ref.read(salesRepositoryProvider).findByBillNo(billNo);
      if (bill == null) {
        error = 'No bill $billNo was found.';
      } else if (bill.billNo != Ids.billNo(loc, bill.id)) {
        error = '$billNo is from another store.';
        bill = null;
      }
    } catch (_) {
      error = "Couldn't search for $billNo. Please try again.";
    }
    if (!mounted) return;
    setState(() => _finding = false);
    if (bill != null) {
      await context.push(Routes.bill(bill.id));
    } else if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error, key: const Key('find-error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = BusinessDate.of(ref.read(clockProvider)());
    final date = _date ?? today;
    final bills = ref.watch(billsForDayProvider(date));
    return PosScaffold(
      title: 'Bills',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              key: const Key('bill-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Find by bill number',
                hintText: 'e.g. 123 or PTB-D01-000123',
                suffixIcon: IconButton(
                  key: const Key('bill-search-go'),
                  tooltip: 'Find bill',
                  icon: _finding
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  onPressed: _find,
                ),
              ),
              onSubmitted: (_) => _find(),
            ),
          ),
          DateBar(
            date: date,
            today: today,
            onChanged: (d) => setState(() => _date = d == today ? null : d),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (bills) {
              AsyncData(:final value) when value.isEmpty => const Center(
                child: Text('No bills on this day.', key: Key('no-bills')),
              ),
              AsyncData(:final value) => ListView.separated(
                itemCount: value.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => BillTile(bill: value[i]),
              ),
              AsyncError() => const Center(
                child: Text("Couldn't load the bills. Please try again."),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class BillTile extends StatelessWidget {
  const BillTile({required this.bill, super.key});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = bill.status == BillStatus.cancelled;
    final items = bill.lines.fold(0, (n, l) => n + l.qty);
    return ListTile(
      key: Key('bill-${bill.id}'),
      minVerticalPadding: 12,
      title: Text(bill.billNo),
      subtitle: Text(
        [
          formatIstTime(bill.clientCreatedAt),
          '$items item${items == 1 ? '' : 's'}',
          if (cancelled) 'Cancelled',
          if (!cancelled && bill.returnedQty.isNotEmpty) 'Has returns',
        ].join(' · '),
      ),
      trailing: Text(
        bill.total.format(),
        style: theme.textTheme.titleMedium?.copyWith(
          decoration: cancelled ? TextDecoration.lineThrough : null,
          color: cancelled ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      onTap: () => context.push(Routes.bill(bill.id)),
    );
  }
}
