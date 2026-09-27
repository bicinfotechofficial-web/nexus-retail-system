import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../api.dart';
import 'printer_transport.dart';

/// [PrinterTransport] on `print_bluetooth_thermal` 1.2.4, which opens an
/// RFCOMM socket with the standard SPP UUID.
///
/// Two quirks of its `writeBytes` (QA-032): the Android side reads the
/// argument `as? List<Int>`, which is null for a `Uint8List` (sent as a
/// Java `byte[]`), so [write] always passes a plain list; and it adds a
/// `'\n'` in front of every call, so [PrinterLink] makes one call per job.
///
/// We never call the plugin's `connectionStatus`: it probes by writing a
/// space to the printer. [PrinterLink] tracks the socket itself and
/// reconnects when a write fails.
final class ThermalPluginTransport implements PrinterTransport {
  const ThermalPluginTransport();

  @override
  Future<bool> isBluetoothOn() => PrintBluetoothThermal.bluetoothEnabled;

  @override
  Future<List<PairedPrinter>> pairedPrinters() async => [
    for (final d in await PrintBluetoothThermal.pairedBluetooths)
      PairedPrinter(name: d.name, address: d.macAdress),
  ];

  @override
  Future<bool> connect(String address) =>
      PrintBluetoothThermal.connect(macPrinterAddress: address);

  @override
  Future<bool> write(List<int> bytes) =>
      PrintBluetoothThermal.writeBytes(List<int>.of(bytes, growable: false));

  @override
  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }
}

/// Android 12+ needs `BLUETOOTH_CONNECT` (and `BLUETOOTH_SCAN`, which the
/// plugin uses to stop discovery before connecting) at runtime. On Android
/// 11 and older, `BLUETOOTH` and `BLUETOOTH_ADMIN` are install-time
/// permissions, and permission_handler reports these two as granted. The
/// plugin's manifest declares all four, so the POS app adds nothing.
final class RuntimeBluetoothPermissions implements BluetoothPermissions {
  const RuntimeBluetoothPermissions();

  static const List<Permission> _needed = [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ];

  @override
  Future<bool> ensureGranted() async {
    final statuses = await _needed.request();
    return _needed.every((p) => statuses[p]?.isGranted ?? false);
  }
}
