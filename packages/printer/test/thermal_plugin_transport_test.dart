import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/bluetooth_printer_service.dart';
import 'package:nexus_printer/src/escpos/code_page.dart';
import 'package:nexus_printer/src/escpos/escpos_encoder.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';
import 'package:nexus_printer/src/receipt/receipt_document.dart';
import 'package:nexus_printer/src/transport/printer_link.dart';
import 'package:nexus_printer/src/transport/printer_transport.dart';
import 'package:nexus_printer/src/transport/thermal_plugin_transport.dart';

import 'fixtures.dart';

/// Stands in for print_bluetooth_thermal 1.2.4's Android handler on the
/// `groons.web.app/print` channel, doing what `PrintBluetoothThermalPlugin.kt`
/// does (QA-032):
///
/// - `writebytes` reads `call.arguments as? List<Int>`. A `Uint8List`
///   arrives as a Java `byte[]`, the cast gives null and the call returns
///   false.
/// - Otherwise it writes `'\n'` followed by the bytes to the socket.
final class FakePlugin {
  static const MethodChannel channel = MethodChannel('groons.web.app/print');

  final List<MethodCall> calls = [];

  /// Everything written to the socket, in order.
  final List<int> socket = [];
  bool connected = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'connect':
        connected = true;
        return true;
      case 'disconnect':
        connected = false;
        return true;
      case 'writebytes':
        final args = call.arguments;
        if (!connected || args is Uint8List || args is! List) return false;
        socket
          ..add(0x0A)
          ..addAll(args.cast<int>());
        return true;
    }
    return null;
  }

  List<MethodCall> get writes =>
      calls.where((c) => c.method == 'writebytes').toList();
}

/// The real plugin transport, except that Bluetooth counts as on: the
/// plugin's `bluetoothEnabled` only asks the channel on Android.
final class _BluetoothOn implements PrinterTransport {
  const _BluetoothOn(this._inner);

  final ThermalPluginTransport _inner;

  @override
  Future<bool> isBluetoothOn() async => true;

  @override
  Future<List<PairedPrinter>> pairedPrinters() => _inner.pairedPrinters();

  @override
  Future<bool> connect(String address) => _inner.connect(address);

  @override
  Future<bool> write(List<int> bytes) => _inner.write(bytes);

  @override
  Future<void> disconnect() => _inner.disconnect();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlugin plugin;
  setUp(() => plugin = FakePlugin()..install());

  const mac = '66:02:BD:06:18:7B';

  test('write sends a plain List<int>, not a Uint8List', () async {
    const transport = ThermalPluginTransport();
    await transport.connect(mac);
    final bytes = Uint8List.fromList([0x1B, 0x40, 0x41, 0x0A]);
    expect(await transport.write(bytes), isTrue);

    final args = plugin.writes.single.arguments;
    expect(args, isNot(isA<Uint8List>()));
    expect(args, isA<List<Object?>>());
    expect(args, [0x1B, 0x40, 0x41, 0x0A]);
  });

  final jobs = <String, List<int> Function()>{
    'normal bill, 80 mm, ₹ table': () =>
        const EscPosEncoder(
          codePage: CodePage(
            name: 'Test',
            escPosNumber: 0x20,
            extra: {'₹': 0xB9},
          ),
        ).encode(
          const ReceiptLayout(
            PaperWidth.mm80,
          ).bill(ReceiptDocument.fromBill(normalBill(), pilotLocation)),
        ),
    'discount + split bill, 80 mm, PC437': () => const EscPosEncoder().encode(
      const ReceiptLayout(
        PaperWidth.mm80,
        currencySymbol: 'Rs.',
      ).bill(ReceiptDocument.fromBill(discountedSplitBill(), pilotLocation)),
    ),
    'test page, 58 mm': () => const EscPosEncoder().encode(
      testPage(width: PaperWidth.mm58, codePage: CodePage.pc437),
    ),
  };

  for (final MapEntry(key: name, value: encode) in jobs.entries) {
    test(
      '$name reaches the socket unchanged apart from one leading LF',
      () async {
        final bytes = encode();
        expect(bytes, isA<Uint8List>(), reason: 'the encoder output type');
        expect(
          bytes.length,
          greaterThan(512),
          reason: 'longer than old chunks',
        );

        final link = PrinterLink(const _BluetoothOn(ThermalPluginTransport()));
        expect(await link.send(mac, bytes), isA<Printed>());

        expect(plugin.writes, hasLength(1), reason: 'one writebytes per job');
        expect(plugin.writes.single.arguments, bytes);
        expect(plugin.socket, [0x0A, ...bytes]);
      },
    );
  }

  test('two jobs: each starts with the one LF, none inside a slip', () async {
    final link = PrinterLink(const _BluetoothOn(ThermalPluginTransport()));
    final a = jobs.values.first();
    final b = jobs.values.last();
    await link.send(mac, a);
    await link.send(mac, b);
    expect(plugin.socket, [0x0A, ...a, 0x0A, ...b]);
  });
}
