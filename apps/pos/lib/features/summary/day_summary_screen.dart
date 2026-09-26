import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/date_bar.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/section_card.dart';
import '../../widgets/total_row.dart';

/// The day's totals from the daily summary doc (POS-11, D-014). The
/// headline "Sales" is net revenue: billed, less returns and cancellations
/// (02-DATA-MODEL summaries, QA-013).
class DaySummaryScreen extends ConsumerStatefulWidget {
  const DaySummaryScreen({super.key});

  @override
  ConsumerState<DaySummaryScreen> createState() => _DaySummaryScreenState();
}

class _DaySummaryScreenState extends ConsumerState<DaySummaryScreen> {
  /// Null follows today.
  String? _date;

  @override
  Widget build(BuildContext context) {
    final today = BusinessDate.of(ref.read(clockProvider)());
    final date = _date ?? today;
    final summary = ref.watch(dailySummaryProvider(date));
    return PosScaffold(
      title: 'Day summary',
      body: Column(
        children: [
          DateBar(
            date: date,
            today: today,
            onChanged: (d) => setState(() => _date = d == today ? null : d),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (summary) {
              AsyncValue(value: final s?) => _body(context, s),
              AsyncError() => const Center(
                child: Text("Couldn't load the summary. Please try again."),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Summary s) {
    final theme = Theme.of(context);
    String count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sales', style: theme.textTheme.titleMedium),
                Text(
                  s.netRevenue.format(),
                  key: const Key('summary-sales'),
                  style: theme.textTheme.displaySmall,
                ),
                Text(
                  '${count(s.billCount, 'bill')} · net of returns and '
                  'cancellations',
                  key: const Key('summary-bill-count'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        SectionCard(
          title: 'Breakdown',
          children: [
            TotalRow(
              'Billed (${count(s.billCount, 'bill')})',
              s.netSales.format(),
              key: const Key('summary-billed'),
            ),
            TotalRow(
              'Returns (${count(s.returnCount, 'return')})',
              (-s.returns).format(),
              key: const Key('summary-returns'),
            ),
            TotalRow(
              'Cancelled (${count(s.cancelCount, 'bill')})',
              (-s.cancelled).format(),
              key: const Key('summary-cancelled'),
            ),
            const Divider(),
            TotalRow(
              'Sales',
              s.netRevenue.format(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TotalRow('Gross (before discounts)', s.grossSales.format()),
            TotalRow('Discounts', (-s.discounts).format()),
            TotalRow('Round-off', s.roundOff.format()),
          ],
        ),
        SectionCard(
          title: 'By payment mode',
          children: [
            if (s.byMode.values.every((m) => m.isZero))
              const Text('No payments.')
            else
              for (final m in PaymentMode.values)
                if (!(s.byMode[m] ?? Money.zero).isZero)
                  TotalRow(
                    Messages.paymentMode(m),
                    s.byMode[m]!.format(),
                    key: Key('summary-mode-${m.wire}'),
                  ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Payments less refunds and cancellations.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
