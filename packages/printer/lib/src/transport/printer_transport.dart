import '../api.dart';

/// The raw Bluetooth Classic (SPP) link to a thermal printer. The only
/// piece that touches a plugin, so everything above it runs against a fake
/// in tests.
///
/// Implementations report failure through their return values and never
/// throw for an ordinary Bluetooth failure; [PrinterLink] still guards
/// against throws and hangs.
abstract interface class PrinterTransport {
  Future<bool> isBluetoothOn();

  /// Printers already paired in Android settings.
  Future<List<PairedPrinter>> pairedPrinters();

  /// Opens the SPP socket to [address]. True when connected.
  Future<bool> connect(String address);

  /// Sends [bytes] on the open socket. True when every byte was written.
  Future<bool> write(List<int> bytes);

  Future<void> disconnect();
}

/// Runtime Bluetooth permission.
abstract interface class BluetoothPermissions {
  /// Asks for whatever this Android version needs and returns true when it
  /// is all granted.
  Future<bool> ensureGranted();
}
