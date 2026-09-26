import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/section_card.dart';

/// First run on this install (POS-3): register the device at the user's
/// location with a label (online only, D-004), then pick the receipt
/// printer and paper width. The router sends an unregistered install here
/// and skips it once registered.
class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen> {
  final _label = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<List<PairedPrinter>>? _printers;
  PairedPrinter? _printer;
  PaperWidth? _width;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _register(String locationId) async {
    final label = _label.text.trim();
    if (_busy || label.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Device device;
    try {
      device = await ref
          .read(deviceServiceProvider)
          .register(locationId: locationId, label: label);
    } on DataFailure catch (e) {
      _failed(
        e.reason == FailureReason.offline
            ? 'Registering this device needs an internet connection. '
                  'Connect to Wi-Fi or mobile data and try again.'
            : Messages.failure(e),
      );
      return;
    } catch (_) {
      _failed(Messages.failure(const DataFailure(FailureReason.unknown)));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ref.read(deviceIdProvider.notifier).registered(device.code);
  }

  void _failed(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  void _loadPrinters() {
    setState(() {
      _error = null;
      _printers = ref.read(printerServiceProvider).pairedPrinters();
    });
  }

  Future<void> _finish() async {
    if (_busy) return;
    final printer = _printer;
    final service = ref.read(printerServiceProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await service.setPaperWidth(_width ?? service.paperWidth);
      if (printer != null) await service.select(printer);
    } catch (e) {
      _failed("Couldn't set up the printer: $e");
      return;
    }
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final deviceId = ref.watch(deviceIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this device')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (deviceId == null)
              ..._registerStep(session)
            else
              ..._printerStep(deviceId),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const Key('setup-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _registerStep(SessionContext? session) {
    final location = session?.location;
    if (session == null ||
        location == null ||
        !session.canAt(Permission.deviceRegister, location.code)) {
      return const [
        Text(
          "This device isn't registered yet, and this login can't register "
          'it. Sign in with a store login that may register devices, or ask '
          'the Admin.',
          key: Key('setup-not-permitted'),
        ),
      ];
    }
    return [
      Text(
        'Register this phone at ${location.name}. Every bill it makes '
        'carries its device code. Registering needs the internet once.',
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('device-label'),
        controller: _label,
        textCapitalization: TextCapitalization.words,
        maxLength: 40,
        decoration: const InputDecoration(
          labelText: 'Device name',
          hintText: 'For example, Counter 1',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('register'),
        onPressed: _busy || _label.text.trim().isEmpty
            ? null
            : () => _register(location.code),
        icon: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.app_registration),
        label: const Text('Register'),
      ),
    ];
  }

  List<Widget> _printerStep(String deviceId) {
    final theme = Theme.of(context);
    final service = ref.read(printerServiceProvider);
    final width = _width ?? service.paperWidth;
    // First build of this step: list the paired printers once.
    _printers ??= service.pairedPrinters();
    return [
      Text(
        'Registered as $deviceId.',
        key: const Key('registered-as'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Receipt printer',
        children: [
          FutureBuilder<List<PairedPrinter>>(
            future: _printers,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final printers = snap.data ?? const <PairedPrinter>[];
              if (snap.hasError || printers.isEmpty) {
                return Text(
                  snap.hasError
                      ? "Couldn't list printers: ${snap.error}"
                      : 'No paired printers. Pair the printer in Android '
                            'Bluetooth settings, then refresh.',
                  key: const Key('no-printers'),
                );
              }
              return RadioGroup<String>(
                groupValue: _printer?.address,
                onChanged: (address) => setState(
                  () => _printer = printers
                      .where((p) => p.address == address)
                      .firstOrNull,
                ),
                child: Column(
                  children: [
                    for (final p in printers)
                      RadioListTile<String>(
                        key: Key('printer-${p.address}'),
                        value: p.address,
                        title: Text(p.name),
                        subtitle: Text(p.address),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('refresh-printers'),
              onPressed: _loadPrinters,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
      SectionCard(
        title: 'Paper width',
        children: [
          SegmentedButton<PaperWidth>(
            segments: const [
              ButtonSegment(
                value: PaperWidth.mm80,
                label: Text('80 mm', key: Key('paper-80')),
              ),
              ButtonSegment(
                value: PaperWidth.mm58,
                label: Text('58 mm', key: Key('paper-58')),
              ),
            ],
            selected: {width},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _width = s.single),
          ),
        ],
      ),
      FilledButton(
        key: const Key('finish'),
        onPressed: _busy || _printer == null ? null : _finish,
        child: const Text('Finish'),
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('skip-printer'),
        onPressed: _busy ? null : _finish,
        child: const Text('Skip, set up the printer later'),
      ),
    ];
  }
}
