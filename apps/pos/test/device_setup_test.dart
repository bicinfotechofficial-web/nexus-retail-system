import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'helpers.dart';

FakeBackend firstRun({SessionContext? session, TestClock? clock}) =>
    FakeBackend(
      session: session,
      registered: false,
      now: clock?.call ?? () => testNow,
    );

void main() {
  testWidgets('an unregistered install opens on setup, not billing', (
    tester,
  ) async {
    await pumpPos(tester, backend: firstRun());
    expect(find.widgetWithText(AppBar, 'Set up this device'), findsOneWidget);
    expect(find.byKey(const Key('product-bf-500')), findsNothing);
    expect(isEnabled(tester, 'register'), isFalse); // needs a label
  });

  testWidgets('registering offline shows a friendly message', (tester) async {
    final b = firstRun();
    b.device.online = false;
    await pumpPos(tester, backend: b);
    await enterKey(tester, 'device-label', 'Counter 1');
    await tapKey(tester, 'register');
    expect(
      textOf(tester, 'setup-error'),
      contains('needs an internet connection'),
    );
    expect(b.device.deviceId, isNull);
    expect(find.byKey(const Key('device-label')), findsOneWidget);

    // Back online, the same tap works.
    b.device.online = true;
    await tapKey(tester, 'register');
    expect(b.device.deviceId, Seed.deviceId);
    expect(find.byKey(const Key('registered-as')), findsOneWidget);
  });

  testWidgets('register with a label, pick a printer and paper width', (
    tester,
  ) async {
    final clock = TestClock();
    final b = firstRun(clock: clock);
    b.sync.lastSyncAt = null;
    await pumpPos(tester, backend: b);

    await enterKey(tester, 'device-label', 'Counter 1');
    clock.advance(const Duration(minutes: 3));
    await tapKey(tester, 'register');
    expect(b.device.registerCalls, [(Seed.locationId, 'Counter 1')]);
    expect(textOf(tester, 'registered-as'), 'Registered as D01.');
    // Registration counts as a sync for the offline limit (03-SYNC §6).
    expect(b.sync.lastSyncAt, clock.now);

    expect(isEnabled(tester, 'finish'), isFalse); // no printer chosen yet
    await tapKey(
      tester,
      'printer-${FakePrinterService.kitchenPrinter.address}',
    );
    await tapKey(tester, 'paper-58');
    await tapKey(tester, 'finish');

    expect(b.printer.selected, FakePrinterService.kitchenPrinter);
    expect(b.printer.paperWidth, PaperWidth.mm58);
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
  });

  testWidgets('the printer can be skipped', (tester) async {
    final b = firstRun();
    await pumpPos(tester, backend: b);
    await enterKey(tester, 'device-label', 'Counter 2');
    await tapKey(tester, 'register');
    await tapKey(tester, 'skip-printer');
    expect(b.printer.selected, isNull);
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
  });

  testWidgets('no paired printers: says how to pair', (tester) async {
    final b = firstRun();
    b.printer.paired = const [];
    await pumpPos(tester, backend: b);
    await enterKey(tester, 'device-label', 'Counter 1');
    await tapKey(tester, 'register');
    expect(find.byKey(const Key('no-printers')), findsOneWidget);

    b.printer.paired = const [FakePrinterService.counterPrinter];
    await tapKey(tester, 'refresh-printers');
    expect(
      find.byKey(Key('printer-${FakePrinterService.counterPrinter.address}')),
      findsOneWidget,
    );
  });

  testWidgets('a login without device.register is told so', (tester) async {
    await pumpPos(
      tester,
      backend: firstRun(session: sessionWith([Permission.billCreate])),
    );
    expect(find.byKey(const Key('setup-not-permitted')), findsOneWidget);
    expect(find.byKey(const Key('register')), findsNothing);
  });

  testWidgets('a registered install skips setup', (tester) async {
    final b = await pumpPos(tester);
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
    expect(b.device.registerCalls, isEmpty);
  });

  test('Routes.redirect sends an unregistered install to setup', () {
    const s = AsyncData<SessionContext?>(
      SessionContext(
        user: Seed.storeManager,
        role: Seed.storeManagerRole,
        location: Seed.location,
      ),
    );
    expect(Routes.redirect(s, '/', deviceRegistered: false), Routes.setup);
    expect(Routes.redirect(s, '/stock', deviceRegistered: false), Routes.setup);
    expect(Routes.redirect(s, Routes.setup, deviceRegistered: false), isNull);
    expect(Routes.redirect(s, Routes.setup), isNull);
    // Signed out, or no POS screens at all, comes first.
    expect(
      Routes.redirect(
        const AsyncData(null),
        Routes.setup,
        deviceRegistered: false,
      ),
      Routes.signedOut,
    );
  });
}
