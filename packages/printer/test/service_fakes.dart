import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/transport/printer_settings.dart';
import 'package:nexus_printer/src/transport/printer_transport.dart';

final class FakePermissions implements BluetoothPermissions {
  bool granted = true;
  int asked = 0;

  @override
  Future<bool> ensureGranted() async {
    asked++;
    return granted;
  }
}

final class MemorySettings implements PrinterSettingsStore {
  MemorySettings({this.printer, this.width});

  PairedPrinter? printer;
  PaperWidth? width;

  @override
  Future<PairedPrinter?> loadPrinter() async => printer;

  @override
  Future<void> savePrinter(PairedPrinter p) async => printer = p;

  @override
  Future<PaperWidth?> loadPaperWidth() async => width;

  @override
  Future<void> savePaperWidth(PaperWidth w) async => width = w;
}

const PairedPrinter counterPrinter = PairedPrinter(
  name: 'BT-80 Counter',
  address: '66:02:BD:06:18:7B',
);

const PairedPrinter backPrinter = PairedPrinter(
  name: 'BT-58 Back',
  address: 'AA:BB:CC:DD:EE:FF',
);
