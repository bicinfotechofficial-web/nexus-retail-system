import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../../app/providers.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/total_row.dart';

/// Shown after Save. The bill is already stored, so it prints the receipt
/// and, if printing fails, offers a retry rather than an error.
class BillSavedScreen extends ConsumerStatefulWidget {
  const BillSavedScreen({required this.bill, super.key});

  final Bill bill;

  @override
  ConsumerState<BillSavedScreen> createState() => _BillSavedScreenState();
}

class _BillSavedScreenState extends ConsumerState<BillSavedScreen> {
  PrintResult? _result;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_print());
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() {
      _printing = true;
      _result = null;
    });
    final location = ref.read(sessionProvider).value?.location;
    PrintResult result;
    if (location == null) {
      result = const PrintFailed('No store is set for this login.');
    } else {
      try {
        result = await ref
            .read(printerServiceProvider)
            .printBill(widget.bill, location);
      } catch (e) {
        result = PrintFailed('$e');
      }
    }
    if (!mounted) return;
    setState(() {
      _printing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final theme = Theme.of(context);
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
          _printStatus(theme),
        ],
      ),
    );
  }

  Widget _printStatus(ThemeData theme) {
    final result = _result;
    if (_printing || result == null) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Printing receipt…'),
        ],
      );
    }
    return switch (result) {
      Printed() => const Text(
        'Receipt printed.',
        key: Key('print-ok'),
        textAlign: TextAlign.center,
      ),
      PrintFailed(:final reason) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "The bill is saved, but the receipt didn't print: $reason",
            key: const Key('print-failed'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('retry-print'),
            onPressed: _print,
            icon: const Icon(Icons.print),
            label: const Text('Retry print'),
          ),
        ],
      ),
    };
  }
}
