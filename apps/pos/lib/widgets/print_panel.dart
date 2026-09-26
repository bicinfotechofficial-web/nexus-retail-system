import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../app/providers.dart';

/// One print job, given the printer and the session's location.
/// [printedBefore] is true once an earlier run of this panel printed, so a
/// "Print again" is a reprint.
typedef PrintJob =
    Future<PrintResult> Function(
      PrinterService printer,
      Location location, {
      required bool printedBefore,
    });

/// Runs a print job and shows its outcome. What is being printed is already
/// saved, so a failure offers a retry, never an error (POS-6).
///
/// With [autoStart] it prints as soon as it appears (after Save); otherwise
/// it shows a [label] button first (Reprint).
class PrintPanel extends ConsumerStatefulWidget {
  const PrintPanel({
    required this.job,
    required this.label,
    this.autoStart = false,
    this.savedWhat = 'bill',
    super.key,
  });

  final PrintJob job;
  final String label;
  final bool autoStart;

  /// What the failure message says is saved: "bill" or "return".
  final String savedWhat;

  @override
  ConsumerState<PrintPanel> createState() => _PrintPanelState();
}

class _PrintPanelState extends ConsumerState<PrintPanel> {
  PrintResult? _result;
  bool _printing = false;
  bool _printedBefore = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) unawaited(_print());
  }

  Future<void> _print() async {
    // Guard before any await, so a double tap prints once.
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
        result = await widget.job(
          ref.read(printerServiceProvider),
          location,
          printedBefore: _printedBefore,
        );
      } catch (e) {
        result = PrintFailed('$e');
      }
    }
    if (!mounted) return;
    setState(() {
      _printing = false;
      _result = result;
      if (result is Printed) _printedBefore = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (_printing) {
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
      null => OutlinedButton.icon(
        key: const Key('print-button'),
        onPressed: _print,
        icon: const Icon(Icons.print),
        label: Text(widget.label),
      ),
      Printed() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Flexible(child: Text('Receipt printed.', key: Key('print-ok'))),
          TextButton(
            key: const Key('print-again'),
            onPressed: _print,
            child: const Text('Print again'),
          ),
        ],
      ),
      PrintFailed(:final reason) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "The ${widget.savedWhat} is saved, but the receipt didn't print: "
            '$reason',
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

/// The receipt text exactly as the printer would print it, in a monospace
/// view scaled to fit the screen width.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Text(
          text,
          key: const Key('receipt-text'),
          softWrap: false,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['RobotoMono', 'Courier'],
            fontSize: 13,
            height: 1.25,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// Opens [text] in a dialog, e.g. to check a past bill's receipt.
Future<void> showReceiptPreview(BuildContext context, String text) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt preview'),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SingleChildScrollView(child: ReceiptPreview(text)),
        actions: [
          TextButton(
            key: const Key('close-preview'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
