import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/nexus_printer.dart';
import 'package:nexus_printer/src/bluetooth_printer_service.dart';
import 'package:nexus_printer/src/escpos/escpos_encoder.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';
import 'package:nexus_printer/src/receipt/receipt_document.dart';
import 'package:nexus_printer/src/transport/printer_link.dart';
import 'package:nexus_printer/src/transport/printer_transport.dart';

import 'fake_transport.dart';
import 'fixtures.dart';
import 'golden_text.dart';
import 'service_fakes.dart';

void main() {
  late FakeTransport transport;
  late FakePermissions permissions;
  late MemorySettings settings;

  setUp(() {
    transport = FakeTransport(paired: [counterPrinter, backPrinter]);
    permissions = FakePermissions();
    settings = MemorySettings();
  });

  Future<BluetoothPrinterService> service() => BluetoothPrinterService.create(
    transport: transport,
    permissions: permissions,
    settings: settings,
  );

  /// Every status the service emits from now on, current one first.
  List<PrinterStatus> record(BluetoothPrinterService s) {
    final seen = <PrinterStatus>[];
    addTearDown(s.status.listen(seen.add).cancel);
    return seen;
  }

  group('startup', () {
    test('no printer remembered: NoPrinter, 80 mm', () async {
      final s = await service();
      expect(await s.status.first, isA<NoPrinter>());
      expect(s.paperWidth, PaperWidth.mm80);
      expect(transport.calls, isEmpty, reason: 'no Bluetooth at startup');
    });

    test(
      'restores the remembered printer and width, not connected yet',
      () async {
        settings
          ..printer = counterPrinter
          ..width = PaperWidth.mm58;
        final s = await service();
        final status = await s.status.first;
        expect(
          (status as Disconnected).printer.address,
          counterPrinter.address,
        );
        expect(s.paperWidth, PaperWidth.mm58);
      },
    );
  });

  group('choosing a printer', () {
    test('lists paired printers', () async {
      final s = await service();
      expect((await s.pairedPrinters()).map((p) => p.name), [
        'BT-80 Counter',
        'BT-58 Back',
      ]);
      expect(permissions.asked, 1);
    });

    test('permission refused: no printers, Unavailable', () async {
      permissions.granted = false;
      final s = await service();
      expect(await s.pairedPrinters(), isEmpty);
      final status = await s.status.first;
      expect(
        (status as Unavailable).reason,
        BluetoothPrinterService.permissionRefused,
      );
      expect(transport.calls, isEmpty);
    });

    test('Bluetooth off: no printers, Unavailable', () async {
      transport.bluetoothOn = false;
      final s = await service();
      expect(await s.pairedPrinters(), isEmpty);
      expect(
        (await s.status.first as Unavailable).reason,
        PrinterLink.bluetoothOff,
      );
    });

    test('select remembers, connects and reports Ready', () async {
      final s = await service();
      final seen = record(s);
      await s.select(counterPrinter);
      await pumpEventQueue();
      expect(settings.printer!.address, counterPrinter.address);
      expect(transport.calls, ['connect ${counterPrinter.address}']);
      expect(seen.map((x) => x.runtimeType), [
        NoPrinter,
        Disconnected,
        Connecting,
        Ready,
      ]);
    });

    test('select still remembers the printer when it cannot connect', () async {
      transport.connectResults.addAll([false, false]);
      final s = await service();
      final seen = record(s);
      await s.select(counterPrinter);
      await pumpEventQueue();
      expect(settings.printer, isNotNull);
      expect(seen.last, isA<Disconnected>());
    });

    test('remembers the paper width', () async {
      final s = await service();
      await s.setPaperWidth(PaperWidth.mm58);
      expect(s.paperWidth, PaperWidth.mm58);
      expect(settings.width, PaperWidth.mm58);
    });
  });

  group('printing', () {
    test('a bill prints the same bytes as layout + encoder', () async {
      settings.printer = counterPrinter;
      final s = await service();
      final r = await s.printBill(normalBill(), pilotLocation);
      expect(r, isA<Printed>());
      final expected = const EscPosEncoder().encode(
        const ReceiptLayout(
          PaperWidth.mm80,
          currencySymbol: 'Rs.',
        ).bill(ReceiptDocument.fromBill(normalBill(), pilotLocation)),
      );
      expect(transport.printed, expected);
      expect(await s.status.first, isA<Ready>());
    });

    test('a reprint and a return slip go through', () async {
      settings.printer = counterPrinter;
      final s = await service();
      final bill = discountedSplitBill();
      expect(
        await s.printBill(bill, pilotLocation, reprint: true),
        isA<Printed>(),
      );
      expect(
        await s.printReturn(partialReturn(bill), bill, pilotLocation),
        isA<Printed>(),
      );
      expect(transport.connects, 1);
    });

    test('previews match what prints, with the printer symbol', () async {
      settings
        ..printer = counterPrinter
        ..width = PaperWidth.mm58;
      final s = await service();
      final text = s.previewBill(cancelledBill(), pilotLocation, reprint: true);
      expect(text, contains('CANCELLED'));
      expect(text, contains('REPRINT'));
      expect(text, contains('Rs.1,149.00'));
      expect(text.split('\n').every((l) => textWidth(l) == 32), isTrue);

      final bill = discountedSplitBill();
      final slip = s.previewReturn(partialReturn(bill), bill, pilotLocation);
      expect(slip, contains('RETURN SLIP'));
      expect(slip, contains(bill.billNo));
    });

    test('a table with the ₹ glyph prints ₹', () async {
      settings.printer = counterPrinter;
      final s = await BluetoothPrinterService.create(
        transport: transport,
        permissions: permissions,
        settings: settings,
        codePage: const CodePage(
          name: 'Test table with ₹',
          escPosNumber: 0x20,
          extra: {'₹': 0xB9},
        ),
      );
      expect(s.previewBill(normalBill(), pilotLocation), contains('₹1,149.00'));
      await s.printBill(normalBill(), pilotLocation);
      expect(transport.printed, contains(0xB9));
    });

    test('no printer chosen: PrintFailed, nothing sent', () async {
      final s = await service();
      final r = await s.printBill(normalBill(), pilotLocation);
      expect(
        (r as PrintFailed).reason,
        BluetoothPrinterService.noPrinterChosen,
      );
      expect(transport.calls, isEmpty);
    });

    test('permission refused: PrintFailed with the reason', () async {
      settings.printer = counterPrinter;
      permissions.granted = false;
      final s = await service();
      final r = await s.testPrint();
      expect(
        (r as PrintFailed).reason,
        BluetoothPrinterService.permissionRefused,
      );
    });

    test('Bluetooth off: PrintFailed and Unavailable', () async {
      settings.printer = counterPrinter;
      transport.bluetoothOn = false;
      final s = await service();
      final r = await s.printBill(normalBill(), pilotLocation);
      expect((r as PrintFailed).reason, PrinterLink.bluetoothOff);
      expect(await s.status.first, isA<Unavailable>());
    });

    test('Bluetooth back on: the next print recovers', () async {
      settings.printer = counterPrinter;
      transport.bluetoothOn = false;
      final s = await service();
      await s.printBill(normalBill(), pilotLocation);
      transport.bluetoothOn = true;
      expect(await s.printBill(normalBill(), pilotLocation), isA<Printed>());
      expect(await s.status.first, isA<Ready>());
    });

    test(
      'a dead printer: PrintFailed and Disconnected, never a throw',
      () async {
        settings.printer = counterPrinter;
        transport.writeOutcomes.addAll([
          WriteOutcome.fail,
          WriteOutcome.throws,
        ]);
        final s = await service();
        final r = await s.printBill(normalBill(), pilotLocation);
        expect((r as PrintFailed).reason, PrinterLink.stoppedResponding);
        expect(await s.status.first, isA<Disconnected>());
      },
    );

    test('a broken permission plugin is a PrintFailed, not a throw', () async {
      settings.printer = counterPrinter;
      final s = await BluetoothPrinterService.create(
        transport: transport,
        permissions: _ThrowingPermissions(),
        settings: settings,
      );
      expect(await s.testPrint(), isA<PrintFailed>());
    });

    test('status goes Connecting then Ready on the first print', () async {
      settings.printer = counterPrinter;
      final s = await service();
      final seen = record(s);
      await s.printBill(normalBill(), pilotLocation);
      await pumpEventQueue();
      expect(seen.map((x) => x.runtimeType), [Disconnected, Connecting, Ready]);
    });
  });

  group('test page', () {
    for (final width in PaperWidth.values) {
      for (final table in [
        CodePage.pc437,
        const CodePage(
          name: 'Test table with ₹',
          escPosNumber: 0x20,
          extra: {'₹': 0xB9},
        ),
      ]) {
        final name =
            'test_page_${width.name}_${table.hasRupee ? 'rupee' : 'rs'}';
        test(name, () {
          final lines = testPage(
            width: width,
            codePage: table,
            printerName: counterPrinter.name,
          );
          for (final l in lines) {
            expect(textWidth(l.text), width.columns);
          }
          expectTextGolden(renderText(lines), name);
        });
      }
    }

    test('testPrint sends the test page for the current width', () async {
      settings
        ..printer = counterPrinter
        ..width = PaperWidth.mm58;
      final s = await service();
      expect(await s.testPrint(), isA<Printed>());
      final expected = const EscPosEncoder().encode(
        testPage(
          width: PaperWidth.mm58,
          codePage: CodePage.pc437,
          printerName: counterPrinter.name,
        ),
      );
      expect(transport.printed, expected);
    });
  });

  test('dispose closes the socket and the status stream', () async {
    settings.printer = counterPrinter;
    final s = await service();
    await s.printBill(normalBill(), pilotLocation);
    final done = s.status.toList();
    await s.dispose();
    expect(transport.calls.last, 'disconnect');
    expect(await done, hasLength(1));
  });
}

final class _ThrowingPermissions implements BluetoothPermissions {
  @override
  Future<bool> ensureGranted() => Future.error(StateError('plugin missing'));
}
