import 'dart:async';

import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

/// An in-memory [PrinterService] that records what it was asked to print.
final class FakePrinterService implements PrinterService {
  FakePrinterService();

  static const PairedPrinter counterPrinter = PairedPrinter(
    name: 'Counter Printer',
    address: '00:11:22:33:44:55',
  );

  final StreamController<PrinterStatus> _status =
      StreamController<PrinterStatus>.broadcast();
  PrinterStatus _current = const Ready(counterPrinter);

  /// Every bill passed to [printBill], in order.
  final List<Bill> printedBills = [];

  /// Results to return from the next print calls, in order. When empty,
  /// prints succeed.
  final List<PrintResult> nextResults = [];

  PaperWidth _width = PaperWidth.mm80;

  @override
  Stream<PrinterStatus> get status async* {
    yield _current;
    yield* _status.stream;
  }

  @override
  PaperWidth get paperWidth => _width;

  @override
  Future<void> setPaperWidth(PaperWidth width) async => _width = width;

  @override
  Future<List<PairedPrinter>> pairedPrinters() async => const [counterPrinter];

  @override
  Future<void> select(PairedPrinter printer) async {
    _current = Ready(printer);
    _status.add(_current);
  }

  PrintResult _next() =>
      nextResults.isEmpty ? const Printed() : nextResults.removeAt(0);

  @override
  Future<PrintResult> printBill(
    Bill bill,
    Location location, {
    bool reprint = false,
  }) async {
    printedBills.add(bill);
    return _next();
  }

  @override
  Future<PrintResult> printReturn(
    SaleReturn ret,
    Bill bill,
    Location location,
  ) async => _next();

  @override
  Future<PrintResult> testPrint() async => _next();

  @override
  String previewBill(Bill bill, Location location, {bool reprint = false}) {
    final b = StringBuffer()
      ..writeln(location.name)
      ..writeln(bill.billNo);
    if (reprint) b.writeln('REPRINT');
    for (final l in bill.lines) {
      b.writeln('${l.name} x${l.qty}  ${l.lineTotal.format()}');
    }
    b.writeln('TOTAL ${bill.total.format()}');
    return b.toString();
  }

  @override
  String previewReturn(SaleReturn ret, Bill bill, Location location) =>
      '${location.name}\nRETURN ${ret.id}\n${ret.refundTotal.format()}';
}
