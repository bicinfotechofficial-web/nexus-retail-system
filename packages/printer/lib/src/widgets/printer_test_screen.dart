import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';

/// Choose the paired printer and paper width, then print a test page
/// (PR-5). Bicy runs it on the real printer in the device pilot (B-6,
/// pilot checklist step 3); POS device setup (POS-3) can reuse it.
///
/// Talks only to [PrinterService], so any implementation works.
class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({required this.printer, super.key});

  final PrinterService printer;

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  late PaperWidth _width = widget.printer.paperWidth;

  /// Subscribed once: `status` returns a new stream on each call.
  late final Stream<PrinterStatus> _status = widget.printer.status;
  List<PairedPrinter>? _paired;
  bool _busy = false;
  String? _message;

  PrinterService get _service => widget.printer;

  Future<void> _findPrinters() => _run(() async {
    final found = await _service.pairedPrinters();
    setState(() {
      _paired = found;
      _message = found.isEmpty
          ? 'No paired printers. Pair the printer in Android Bluetooth '
                'settings first.'
          : null;
    });
  });

  Future<void> _choose(PairedPrinter p) => _run(() => _service.select(p));

  Future<void> _setWidth(PaperWidth w) => _run(() async {
    await _service.setPaperWidth(w);
    setState(() => _width = w);
  });

  Future<void> _testPrint() => _run(() async {
    final result = await _service.testPrint();
    setState(
      () => _message = switch (result) {
        Printed() => 'Test page sent. Check the slip.',
        PrintFailed(:final reason) => 'Test print failed: $reason',
      },
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _message = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printer')),
      body: StreamBuilder<PrinterStatus>(
        stream: _status,
        builder: (context, snap) {
          final status = snap.data;
          final chosen = switch (status) {
            Disconnected(:final printer) ||
            Connecting(:final printer) ||
            Ready(:final printer) => printer,
            _ => null,
          };
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusTile(status: status),
              const SizedBox(height: 16),
              Text(
                'Paper width',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<PaperWidth>(
                segments: const [
                  ButtonSegment(value: PaperWidth.mm80, label: Text('80 mm')),
                  ButtonSegment(value: PaperWidth.mm58, label: Text('58 mm')),
                ],
                selected: {_width},
                onSelectionChanged: _busy
                    ? null
                    : (s) => unawaited(_setWidth(s.single)),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('findPrinters'),
                onPressed: _busy ? null : () => unawaited(_findPrinters()),
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Show paired printers'),
              ),
              for (final p in _paired ?? const <PairedPrinter>[])
                ListTile(
                  key: Key('printer-${p.address}'),
                  leading: const Icon(Icons.print),
                  title: Text(p.name),
                  subtitle: Text(p.address),
                  trailing: p.address == chosen?.address
                      ? const Icon(Icons.check)
                      : null,
                  onTap: _busy ? null : () => unawaited(_choose(p)),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('testPrint'),
                onPressed: _busy || chosen == null
                    ? null
                    : () => unawaited(_testPrint()),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Print test page'),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_message case final m?) ...[
                const SizedBox(height: 16),
                Text(m, key: const Key('message')),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status});

  final PrinterStatus? status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text) = switch (status) {
      null => (Icons.hourglass_empty, 'Checking the printer…'),
      NoPrinter() => (Icons.print_disabled, 'No printer chosen'),
      Disconnected(:final printer) => (
        Icons.link_off,
        '${printer.name}: not connected',
      ),
      Connecting(:final printer) => (
        Icons.sync,
        '${printer.name}: connecting…',
      ),
      Ready(:final printer) => (Icons.check_circle, '${printer.name}: ready'),
      Unavailable(:final reason) => (Icons.bluetooth_disabled, reason),
    };
    return ListTile(
      key: const Key('status'),
      leading: Icon(icon),
      title: Text(text),
    );
  }
}
