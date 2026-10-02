import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../app/providers.dart';

/// The shop name in the WhatsApp text (D-036).
const String shopName = 'Caramel Cottage';

/// WhatsApp message and image buttons for a saved bill (POS-14, D-036).
/// Nothing is sent automatically and nothing is recorded as sent: the
/// cashier presses Send in WhatsApp, or picks the chat in the share sheet.
/// Hidden when the bill's customer isn't on WhatsApp. Opening or sharing
/// never touches the bill, so a failure only shows a message.
class WhatsappActions extends ConsumerStatefulWidget {
  const WhatsappActions({required this.bill, super.key});

  final Bill bill;

  @override
  ConsumerState<WhatsappActions> createState() => _WhatsappActionsState();
}

class _WhatsappActionsState extends ConsumerState<WhatsappActions> {
  bool _opening = false;
  bool _sharing = false;
  String? _problem;

  Future<void> _message(String number, Location? location) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _problem = null;
    });
    final text = WhatsappReceipt.build(
      shopName: shopName,
      locationName: location?.name ?? '',
      bill: widget.bill,
    );
    var opened = false;
    try {
      opened = await ref
          .read(linkLauncherProvider)
          .open(WhatsappReceipt.link(number, text));
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (!opened) _problem = "WhatsApp isn't installed on this phone.";
    });
  }

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
    final number = widget.bill.customer?.whatsapp;
    if (number == null) return const SizedBox.shrink();
    final location = ref.watch(sessionProvider).value?.location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('whatsapp-message'),
          onPressed: _opening ? null : () => _message(number, location),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('WhatsApp message'),
        ),
        const SizedBox(height: 8),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
