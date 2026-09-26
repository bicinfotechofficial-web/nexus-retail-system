import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/transport/printer_settings.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('nothing is remembered on a new device', () async {
    final s = SharedPrefsPrinterSettings();
    expect(await s.loadPrinter(), isNull);
    expect(await s.loadPaperWidth(), isNull);
  });

  test('remembers the printer across instances', () async {
    await SharedPrefsPrinterSettings().savePrinter(
      const PairedPrinter(name: 'BT-80', address: '66:02:BD:06:18:7B'),
    );
    final p = await SharedPrefsPrinterSettings().loadPrinter();
    expect(p!.name, 'BT-80');
    expect(p.address, '66:02:BD:06:18:7B');
  });

  test('remembers the paper width', () async {
    await SharedPrefsPrinterSettings().savePaperWidth(PaperWidth.mm58);
    expect(
      await SharedPrefsPrinterSettings().loadPaperWidth(),
      PaperWidth.mm58,
    );
  });

  test('ignores an unknown stored width', () async {
    final platform = InMemorySharedPreferencesAsync.withData({
      SharedPrefsPrinterSettings.paperWidthKey: 'mm110',
    });
    SharedPreferencesAsyncPlatform.instance = platform;
    expect(await SharedPrefsPrinterSettings().loadPaperWidth(), isNull);
  });
}
