import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'fake_transport.dart';
import 'service_fakes.dart';

void main() {
  late FakeTransport transport;
  late FakePermissions permissions;
  late MemorySettings settings;
  late BluetoothPrinterService service;

  Future<void> open(WidgetTester tester) async {
    service = await BluetoothPrinterService.create(
      transport: transport,
      permissions: permissions,
      settings: settings,
    );
    await tester.pumpWidget(
      MaterialApp(home: PrinterTestScreen(printer: service)),
    );
    await tester.pumpAndSettle();
  }

  String statusText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const Key('status')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  FilledButton testButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('testPrint')));

  setUp(() {
    transport = FakeTransport(paired: [counterPrinter, backPrinter]);
    permissions = FakePermissions();
    settings = MemorySettings();
  });

  testWidgets('choose a printer and print a test page', (tester) async {
    await open(tester);
    expect(statusText(tester), 'No printer chosen');
    expect(testButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('findPrinters')));
    await tester.pumpAndSettle();
    expect(find.text('BT-80 Counter'), findsOneWidget);
    expect(find.text('BT-58 Back'), findsOneWidget);

    await tester.tap(find.byKey(Key('printer-${counterPrinter.address}')));
    await tester.pumpAndSettle();
    expect(statusText(tester), 'BT-80 Counter: ready');
    expect(settings.printer!.address, counterPrinter.address);
    expect(
      find.descendant(
        of: find.byKey(Key('printer-${counterPrinter.address}')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('testPrint')));
    await tester.pumpAndSettle();
    expect(find.text('Test page sent. Check the slip.'), findsOneWidget);
    expect(transport.printed, isNotEmpty);
  });

  testWidgets('switching to 58 mm is remembered and used', (tester) async {
    settings.printer = counterPrinter;
    await open(tester);
    await tester.tap(find.text('58 mm'));
    await tester.pumpAndSettle();
    expect(settings.width, PaperWidth.mm58);
    expect(service.paperWidth, PaperWidth.mm58);
  });

  testWidgets('a remembered printer can test-print straight away', (
    tester,
  ) async {
    settings.printer = counterPrinter;
    await open(tester);
    expect(statusText(tester), 'BT-80 Counter: not connected');
    await tester.tap(find.byKey(const Key('testPrint')));
    await tester.pumpAndSettle();
    expect(statusText(tester), 'BT-80 Counter: ready');
  });

  testWidgets('a failed test print shows the reason', (tester) async {
    settings.printer = counterPrinter;
    transport.connectResults.addAll([false, false]);
    await open(tester);
    await tester.tap(find.byKey(const Key('testPrint')));
    await tester.pumpAndSettle();
    expect(
      find.text('Test print failed: Could not connect to the printer'),
      findsOneWidget,
    );
    expect(statusText(tester), 'BT-80 Counter: not connected');
  });

  testWidgets('permission refused is explained', (tester) async {
    permissions.granted = false;
    await open(tester);
    await tester.tap(find.byKey(const Key('findPrinters')));
    await tester.pumpAndSettle();
    expect(statusText(tester), 'Bluetooth permission refused');
    expect(find.textContaining('No paired printers'), findsOneWidget);
  });

  testWidgets('Bluetooth off is explained', (tester) async {
    transport.bluetoothOn = false;
    await open(tester);
    await tester.tap(find.byKey(const Key('findPrinters')));
    await tester.pumpAndSettle();
    expect(statusText(tester), 'Bluetooth is off');
  });
}
