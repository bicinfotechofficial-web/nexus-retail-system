import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

/// The printer and paper width chosen on this device (D-020). Per device,
/// never synced.
abstract interface class PrinterSettingsStore {
  Future<PairedPrinter?> loadPrinter();
  Future<void> savePrinter(PairedPrinter printer);

  /// Null until someone picks a width; the service then uses 80 mm.
  Future<PaperWidth?> loadPaperWidth();
  Future<void> savePaperWidth(PaperWidth width);
}

/// [PrinterSettingsStore] on `shared_preferences`.
final class SharedPrefsPrinterSettings implements PrinterSettingsStore {
  SharedPrefsPrinterSettings([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const String addressKey = 'nexus_printer.address';
  static const String nameKey = 'nexus_printer.name';
  static const String paperWidthKey = 'nexus_printer.paper_width';

  @override
  Future<PairedPrinter?> loadPrinter() async {
    final address = await _prefs.getString(addressKey);
    if (address == null || address.isEmpty) return null;
    final name = await _prefs.getString(nameKey);
    return PairedPrinter(name: name ?? address, address: address);
  }

  @override
  Future<void> savePrinter(PairedPrinter printer) async {
    await _prefs.setString(addressKey, printer.address);
    await _prefs.setString(nameKey, printer.name);
  }

  @override
  Future<PaperWidth?> loadPaperWidth() async {
    final name = await _prefs.getString(paperWidthKey);
    for (final w in PaperWidth.values) {
      if (w.name == name) return w;
    }
    return null;
  }

  @override
  Future<void> savePaperWidth(PaperWidth width) =>
      _prefs.setString(paperWidthKey, width.name);
}
