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
export 'src/image/receipt_image.dart'
    show
        receiptGlyphWidth,
        receiptRowHeight,
        renderOrderSlipPng,
        renderReceiptPng,
        renderReturnSlipPng;
export 'src/image/receipt_sharer.dart'
    show ReceiptSharer, SharePlusReceiptSharer;
export 'src/logo/receipt_logo.dart'
    show AssetReceiptLogo, LogoBitmap, NoReceiptLogo, ReceiptLogo;
export 'src/receipt/order_slip.dart' show OrderSlipDocument;
export 'src/receipt/receipt_document.dart'
    show ReceiptDocument, ReturnSlipDocument;
export 'src/widgets/printer_test_screen.dart' show PrinterTestScreen;
