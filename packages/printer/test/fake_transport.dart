import 'dart:async';

import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/transport/printer_transport.dart';

/// A scripted [PrinterTransport] that records every call.
final class FakeTransport implements PrinterTransport {
  FakeTransport({this.bluetoothOn = true, List<PairedPrinter>? paired})
    : paired = paired ?? const [];

  bool bluetoothOn;
  List<PairedPrinter> paired;

  /// Results for successive connect calls; true once it runs out.
  final List<bool> connectResults = [];

  /// Behaviour of successive write calls; [WriteOutcome.ok] once it runs
  /// out.
  final List<WriteOutcome> writeOutcomes = [];

  final List<String> calls = [];

  /// Every byte a successful write delivered, in order.
  final List<int> printed = [];

  int get connects => calls.where((c) => c.startsWith('connect')).length;

  @override
  Future<bool> isBluetoothOn() async => bluetoothOn;

  @override
  Future<List<PairedPrinter>> pairedPrinters() async {
    calls.add('paired');
    return paired;
  }

  @override
  Future<bool> connect(String address) async {
    calls.add('connect $address');
    return connectResults.isEmpty || connectResults.removeAt(0);
  }

  @override
  Future<bool> write(List<int> bytes) {
    calls.add('write ${bytes.length}');
    final outcome = writeOutcomes.isEmpty
        ? WriteOutcome.ok
        : writeOutcomes.removeAt(0);
    switch (outcome) {
      case WriteOutcome.ok:
        printed.addAll(bytes);
        return Future.value(true);
      case WriteOutcome.fail:
        return Future.value(false);
      case WriteOutcome.throws:
        return Future.error(StateError('socket closed'));
      case WriteOutcome.hang:
        return Completer<bool>().future;
    }
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
  }
}

enum WriteOutcome { ok, fail, throws, hang }
