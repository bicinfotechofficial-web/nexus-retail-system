/// Receipt documents, the text layout engine, the ESC/POS encoder and the
/// Bluetooth Classic transport.
///
/// `src/api.dart` is the contract the POS app builds against; the central
/// agent owns it, and changes go through docs/CHANGE-REQUESTS.md. The
/// printer agent implements it (PR-1 to PR-6).
///
/// Besides the contract, the POS app needs only two things from here:
/// `BluetoothPrinterService.create` to build the real service at startup,
/// and `PrinterTestScreen` for choosing the printer and printing a test
/// page. Layout, encoding and transport stay internal.
library;

export 'src/api.dart';
export 'src/bluetooth_printer_service.dart' show BluetoothPrinterService;
export 'src/escpos/code_page.dart' show CodePage;
export 'src/widgets/printer_test_screen.dart' show PrinterTestScreen;
