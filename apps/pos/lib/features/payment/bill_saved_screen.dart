import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/print_panel.dart';
import '../../widgets/total_row.dart';

/// Shown after Save. The bill is already stored, so it prints the receipt
/// and, if printing fails, offers a retry rather than an error (POS-6). The
/// receipt preview below is the exact text sent to the printer.
class BillSavedScreen extends ConsumerWidget {
  const BillSavedScreen({required this.bill, super.key});

  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = ref.watch(sessionProvider).value?.location;
    final change = BillCalculator.checkPayments(
      bill.total,
      bill.payments,
      cashTendered: bill.cashTendered,
    ).change;
    return PosScaffold(
      title: 'Bill saved',
      showDrawer: false,
      bottom: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          key: const Key('new-bill'),
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('New bill'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.check_circle, size: 64, color: Color(0xFF1E6B2A)),
          const SizedBox(height: 8),
          Text(
            bill.billNo,
            key: const Key('bill-no'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          TotalRow(
            'Total',
            bill.total.format(),
            style: theme.textTheme.titleLarge,
          ),
          if (change != null)
            TotalRow(
              'Change to return',
              change.format(),
              key: const Key('saved-change'),
              style: theme.textTheme.titleLarge,
            ),
          const SizedBox(height: 24),
          PrintPanel(
            label: 'Print receipt',
            autoStart: true,
            // A retry after a failure is still the first copy; printing
            // again after it came out is a reprint.
            job: (printer, location, {required printedBefore}) =>
                printer.printBill(bill, location, reprint: printedBefore),
          ),
          if (location != null) ...[
            const SizedBox(height: 24),
            Text('Receipt preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ReceiptPreview(
              ref.read(printerServiceProvider).previewBill(bill, location),
              key: const Key('receipt-preview'),
            ),
          ],
        ],
      ),
    );
  }
}
