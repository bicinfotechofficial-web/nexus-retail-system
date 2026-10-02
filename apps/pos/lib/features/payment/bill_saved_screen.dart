import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/print_panel.dart';
import '../../widgets/total_row.dart';
import '../../widgets/whatsapp_actions.dart';

/// Shown after the bill is saved (D-035). The bill is already stored, so
/// Print and the WhatsApp buttons are optional follow-ups: a printer fault
/// offers a retry, never an error (POS-6), and Done is always available. The
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
          label: const Text('Done'),
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
            // A retry after a failure is still the first copy; printing
            // again after it came out is a reprint.
            job: (printer, location, {required printedBefore}) =>
                printer.printBill(bill, location, reprint: printedBefore),
          ),
          if (bill.customer?.whatsapp != null) ...[
            const SizedBox(height: 12),
            WhatsappActions(bill: bill),
          ],
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
