import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../app/providers.dart';

/// Shares a saved bill's receipt as an image through the share sheet
/// (D-036b, D-041). The cashier picks the customer's chat there, because the
/// contact can't be preset, so the customer's WhatsApp number is shown above
/// the button to help find it. Nothing is sent automatically and nothing is
/// recorded as sent. Hidden when the customer isn't on WhatsApp (D-034).
/// Sharing never touches the bill, so a failure only shows a message.
class ReceiptShare extends ConsumerStatefulWidget {
  const ReceiptShare({required this.bill, this.showNumber = true, super.key});

  final Bill bill;

  /// Whether to print the WhatsApp number above the button. The bill page
  /// already lists it with the customer.
  final bool showNumber;

  @override
  ConsumerState<ReceiptShare> createState() => _ReceiptShareState();
}

class _ReceiptShareState extends ConsumerState<ReceiptShare> {
  bool _sharing = false;
  String? _problem;

  Future<void> _image(Location? location) async {
    if (_sharing) return;
    if (location == null) {
      setState(() => _problem = 'No store is set for this login.');
      return;
    }
    setState(() {
      _sharing = true;
      _problem = null;
    });
    final bill = widget.bill;
    String? problem;
    try {
      final png = await ref.read(receiptImageRendererProvider)(
        ReceiptDocument.fromBill(bill, location),
        ref.read(printerServiceProvider).paperWidth,
      );
      await ref
          .read(receiptSharerProvider)
          .shareImage(
            png,
            fileName: '${bill.id}.png',
            text: '${bill.billNo} · ${bill.total.format()}',
          );
    } on Object {
      problem = "Couldn't share the receipt image. Please try again.";
    }
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.bill.customer;
    if (customer == null) return const SizedBox.shrink();
    final number = customer.whatsapp;
    final theme = Theme.of(context);
    if (number == null) {
      return widget.showNumber
          ? Text(
              'No WhatsApp',
              key: const Key('whatsapp-number'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            )
          : const SizedBox.shrink();
    }
    final location = ref.watch(sessionProvider).value?.location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showNumber)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'WhatsApp: $number',
              key: const Key('whatsapp-number'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        OutlinedButton.icon(
          key: const Key('whatsapp-image'),
          onPressed: _sharing ? null : () => _image(location),
          icon: _sharing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          label: const Text('WhatsApp image'),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _problem!,
              key: const Key('whatsapp-problem'),
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
