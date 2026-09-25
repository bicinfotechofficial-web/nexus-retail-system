import 'package:nexus_core/nexus_core.dart';

/// Paper width (D-020). 80 mm is the default; 58 mm is set per device.
enum PaperWidth {
  mm80(48),
  mm58(32);

  const PaperWidth(this.columns);

  /// Characters per line in the printer's standard font.
  final int columns;
}

/// A Bluetooth printer already paired in Android settings.
final class PairedPrinter {
  const PairedPrinter({required this.name, required this.address});

  final String name;

  /// The Bluetooth MAC address, which identifies the printer.
  final String address;
}

sealed class PrinterStatus {
  const PrinterStatus();
}

/// No printer chosen on this device yet.
final class NoPrinter extends PrinterStatus {
  const NoPrinter();
}

final class Disconnected extends PrinterStatus {
  const Disconnected(this.printer);
  final PairedPrinter printer;
}

final class Connecting extends PrinterStatus {
  const Connecting(this.printer);
  final PairedPrinter printer;
}

final class Ready extends PrinterStatus {
  const Ready(this.printer);
  final PairedPrinter printer;
}

/// Bluetooth is off, or the permission was refused.
final class Unavailable extends PrinterStatus {
  const Unavailable(this.reason);
  final String reason;
}

/// The outcome of one print job. A failed print never affects the saved
/// bill; the POS offers a retry (POS-6).
sealed class PrintResult {
  const PrintResult();
}

final class Printed extends PrintResult {
  const Printed();
}

final class PrintFailed extends PrintResult {
  const PrintFailed(this.reason);
  final String reason;
}

/// Everything the POS app needs from the printer package. Receipt layout
/// (BRD §4.1, D-010, D-013) is internal to the package.
abstract interface class PrinterService {
  Stream<PrinterStatus> get status;

  PaperWidth get paperWidth;

  /// Remembered for this device.
  Future<void> setPaperWidth(PaperWidth width);

  /// Asks for Bluetooth permission if needed.
  Future<List<PairedPrinter>> pairedPrinters();

  /// Chooses and remembers the printer for this device, then connects.
  Future<void> select(PairedPrinter printer);

  /// A bill receipt. [reprint] adds a "REPRINT" line; a cancelled bill
  /// always prints a "CANCELLED" banner.
  Future<PrintResult> printBill(
    Bill bill,
    Location location, {
    bool reprint = false,
  });

  Future<PrintResult> printReturn(SaleReturn ret, Bill bill, Location location);

  /// A short page to check alignment, width and the ₹ glyph (PR-5).
  Future<PrintResult> testPrint();

  /// The receipt as plain text, exactly as it would print. Used by the
  /// preview screen and golden tests.
  String previewBill(Bill bill, Location location, {bool reprint = false});

  String previewReturn(SaleReturn ret, Bill bill, Location location);
}
