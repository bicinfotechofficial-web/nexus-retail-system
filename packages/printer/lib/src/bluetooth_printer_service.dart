import 'dart:async';

import 'package:nexus_core/nexus_core.dart';

import 'api.dart';
import 'escpos/code_page.dart';
import 'escpos/escpos_encoder.dart';
import 'layout/line_builder.dart';
import 'layout/print_line.dart';
import 'layout/receipt_layout.dart';
import 'receipt/receipt_document.dart';
import 'transport/printer_link.dart';
import 'transport/printer_settings.dart';
import 'transport/printer_transport.dart';
import 'transport/thermal_plugin_transport.dart';

/// The [PrinterService] the POS app uses: receipt documents (PR-1), text
/// layout (PR-2), ESC/POS (PR-3) and the Bluetooth link (PR-4) behind the
/// contract. Never throws from a print call; a failure is a [PrintFailed]
/// and the status stream says why.
final class BluetoothPrinterService implements PrinterService {
  BluetoothPrinterService._({
    required PrinterTransport transport,
    required BluetoothPermissions permissions,
    required PrinterSettingsStore settings,
    required this.codePage,
    required PrinterLink link,
    required PairedPrinter? printer,
    required PaperWidth paperWidth,
  }) : _transport = transport,
       _permissions = permissions,
       _settings = settings,
       _link = link,
       _printer = printer,
       _paperWidth = paperWidth,
       _current = printer == null ? const NoPrinter() : Disconnected(printer);

  /// Loads the printer and paper width remembered on this device. The
  /// defaults are the real Bluetooth plugin, runtime permissions and
  /// `shared_preferences`; tests pass fakes.
  static Future<BluetoothPrinterService> create({
    PrinterTransport transport = const ThermalPluginTransport(),
    BluetoothPermissions permissions = const RuntimeBluetoothPermissions(),
    PrinterSettingsStore? settings,
    CodePage codePage = CodePage.pc437,
    PrinterLink? link,
  }) async {
    final store = settings ?? SharedPrefsPrinterSettings();
    return BluetoothPrinterService._(
      transport: transport,
      permissions: permissions,
      settings: store,
      codePage: codePage,
      link: link ?? PrinterLink(transport),
      printer: await store.loadPrinter(),
      paperWidth: await store.loadPaperWidth() ?? PaperWidth.mm80,
    );
  }

  final PrinterTransport _transport;
  final BluetoothPermissions _permissions;
  final PrinterSettingsStore _settings;
  final PrinterLink _link;

  /// The printer's character table. Decides ₹ or `Rs.` (PR-3).
  final CodePage codePage;

  PairedPrinter? _printer;
  PaperWidth _paperWidth;
  PrinterStatus _current;
  final StreamController<PrinterStatus> _changes =
      StreamController<PrinterStatus>.broadcast();

  static const String noPrinterChosen = 'No printer chosen';
  static const String permissionRefused = 'Bluetooth permission refused';

  /// The current status first, then every change.
  @override
  Stream<PrinterStatus> get status => Stream.multi((out) {
    out.add(_current);
    final sub = _changes.stream.listen(out.add, onDone: out.close);
    out.onCancel = sub.cancel;
  });

  /// The printer chosen on this device, if any.
  PairedPrinter? get printer => _printer;

  @override
  PaperWidth get paperWidth => _paperWidth;

  @override
  Future<void> setPaperWidth(PaperWidth width) async {
    _paperWidth = width;
    await _guarded(() => _settings.savePaperWidth(width));
  }

  @override
  Future<List<PairedPrinter>> pairedPrinters() async {
    if (!await _ready()) return const [];
    return await _guarded(_transport.pairedPrinters) ?? const [];
  }

  @override
  Future<void> select(PairedPrinter printer) async {
    _printer = printer;
    await _guarded(() => _settings.savePrinter(printer));
    if (!await _ready()) return;
    _emit(Connecting(printer));
    final ok = await _link.open(printer.address);
    // A newer select() may have run while this one was connecting.
    if (_printer?.address != printer.address) return;
    _emit(ok ? Ready(printer) : Disconnected(printer));
  }

  @override
  Future<PrintResult> printBill(
    Bill bill,
    Location location, {
    bool reprint = false,
  }) => _print(
    () => _layout.bill(
      ReceiptDocument.fromBill(bill, location, reprint: reprint),
    ),
  );

  @override
  Future<PrintResult> printReturn(
    SaleReturn ret,
    Bill bill,
    Location location,
  ) => _print(
    () =>
        _layout.returnSlip(ReturnSlipDocument.fromReturn(ret, bill, location)),
  );

  @override
  Future<PrintResult> testPrint() => _print(
    () => testPage(
      width: _paperWidth,
      codePage: codePage,
      printerName: _printer?.name ?? '',
    ),
  );

  @override
  String previewBill(Bill bill, Location location, {bool reprint = false}) =>
      renderText(
        _layout.bill(
          ReceiptDocument.fromBill(bill, location, reprint: reprint),
        ),
      );

  @override
  String previewReturn(SaleReturn ret, Bill bill, Location location) =>
      renderText(
        _layout.returnSlip(ReturnSlipDocument.fromReturn(ret, bill, location)),
      );

  /// Closes the socket and the status stream.
  Future<void> dispose() async {
    await _link.close();
    // Not awaited: close() only completes once every listener has seen the
    // done event, which a paused or unmounted listener may never do.
    unawaited(_changes.close());
  }

  ReceiptLayout get _layout =>
      ReceiptLayout(_paperWidth, currencySymbol: codePage.currencySymbol);

  Future<PrintResult> _print(List<PrintLine> Function() layOut) async {
    final printer = _printer;
    if (printer == null) {
      _emit(const NoPrinter());
      return const PrintFailed(noPrinterChosen);
    }
    try {
      if (!await _ready()) {
        return PrintFailed(switch (_current) {
          Unavailable(:final reason) => reason,
          _ => permissionRefused,
        });
      }
      final bytes = EscPosEncoder(codePage: codePage).encode(layOut());
      if (!_link.isConnectedTo(printer.address)) _emit(Connecting(printer));
      final result = await _link.send(printer.address, bytes);
      if (_printer?.address == printer.address) {
        _emit(switch (result) {
          Printed() => Ready(printer),
          PrintFailed(reason: PrinterLink.bluetoothOff) => const Unavailable(
            PrinterLink.bluetoothOff,
          ),
          PrintFailed() => Disconnected(printer),
        });
      }
      return result;
    } on Object catch (e) {
      return PrintFailed('Could not print: $e');
    }
  }

  /// True when the permission is granted and Bluetooth is on; otherwise
  /// emits [Unavailable] and returns false.
  Future<bool> _ready() async {
    if (!(await _guarded(_permissions.ensureGranted) ?? false)) {
      _emit(const Unavailable(permissionRefused));
      return false;
    }
    if (!(await _guarded(_transport.isBluetoothOn) ?? false)) {
      _emit(const Unavailable(PrinterLink.bluetoothOff));
      return false;
    }
    if (_current is Unavailable || _current is NoPrinter) {
      final p = _printer;
      _emit(p == null ? const NoPrinter() : Disconnected(p));
    }
    return true;
  }

  void _emit(PrinterStatus s) {
    if (_same(s, _current)) return;
    _current = s;
    if (!_changes.isClosed) _changes.add(s);
  }

  static bool _same(PrinterStatus a, PrinterStatus b) => switch ((a, b)) {
    (NoPrinter(), NoPrinter()) => true,
    (Unavailable(reason: final x), Unavailable(reason: final y)) => x == y,
    (Disconnected(printer: final x), Disconnected(printer: final y)) ||
    (Connecting(printer: final x), Connecting(printer: final y)) ||
    (
      Ready(printer: final x),
      Ready(printer: final y),
    ) => x.address == y.address,
    _ => false,
  };

  /// [call]'s result, or null when it throws.
  static Future<T?> _guarded<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Object {
      return null;
    }
  }
}

/// The test page (PR-5, pilot checklist 3.2): the ₹ or `Rs.` symbol,
/// bold and double-height text, a column ruler and edge marks, so one
/// look shows whether the width setting and character table are right.
List<PrintLine> testPage({
  required PaperWidth width,
  required CodePage codePage,
  String printerName = '',
}) {
  final c = width.columns;
  final money = const Money(12345678).format(symbol: codePage.currencySymbol);
  final b = LineBuilder(c)
    ..center('TEST PRINT', bold: true)
    ..rule();
  if (printerName.isNotEmpty) b.left('Printer: $printerName');
  b
    ..left('Paper: ${width == PaperWidth.mm80 ? 80 : 58} mm, $c columns')
    ..left('Character set: ${codePage.name}')
    ..left(
      codePage.hasRupee
          ? 'Rupee sign: ${CodePage.rupee}'
          : 'Rupee sign: not on this printer, using ${CodePage.rupeeFallback}',
    )
    ..rule()
    ..raw(List.generate(c, (i) => '${(i + 1) % 10}').join())
    ..raw('<${' ' * (c - 2)}>')
    ..row('Amount', money)
    ..left('Bold text', bold: true)
    ..row('TOTAL', money, bold: true, doubleHeight: true)
    ..rule()
    ..center(
      'Both < and > must show on one line. If not, change the paper width.',
    );
  return b.build();
}
