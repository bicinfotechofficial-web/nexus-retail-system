import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_services.dart';
import 'package:nexus_admin/locations/location_form.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

Future<void> _open(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await tester.tap(find.text('Locations'));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('location-save')));
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

Future<void> _fillNew(
  WidgetTester tester, {
  String code = 'KTM',
  String pin = '24681357',
  String confirm = '24681357',
}) async {
  await _enter(tester, 'location-code', code);
  await _enter(tester, 'location-name', 'Kottayam');
  await _enter(tester, 'location-address', 'MC Road, Kottayam');
  await _enter(tester, 'location-phone', '0481 000 0000');
  await _enter(tester, 'location-pin', pin);
  await _enter(tester, 'location-pin-confirm', confirm);
}

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  group('LocationRules', () {
    test('code: 2 to 4 capital letters, not taken', () {
      const bad = 'Use 2 to 4 capital letters, e.g. PTB';
      expect(LocationRules.code('KTM', ['PTB']), isNull);
      expect(LocationRules.code('KO', []), isNull);
      expect(LocationRules.code('KOTM', []), isNull);
      expect(LocationRules.code('K', []), bad);
      expect(LocationRules.code('KOTTA', []), bad);
      expect(LocationRules.code('ktm', []), bad);
      expect(LocationRules.code('K1M', []), bad);
      expect(LocationRules.code('PTB', ['PTB']), 'PTB is already used');
    });

    test('PIN: digits only, minimum length, required on create', () {
      expect(Limits.minOverridePinDigits, 8);
      expect(LocationRules.pin('', creating: true), 'Set an override PIN');
      expect(LocationRules.pin('', creating: false), isNull);
      expect(
        LocationRules.pin('1234567', creating: false),
        'Use at least 8 digits',
      );
      expect(LocationRules.pin('12345678', creating: true), isNull);
      expect(LocationRules.pin('1234abcd', creating: true), 'Use digits only');
      expect(LocationRules.pinConfirm('12345678', '12345678'), isNull);
      expect(
        LocationRules.pinConfirm('12345679', '12345678'),
        'The PINs do not match',
      );
    });

    test('discount cap: blank or 0 to 100', () {
      expect(LocationRules.discountCap(''), isNull);
      expect(LocationRules.discountCap('0'), isNull);
      expect(LocationRules.discountCap('100'), isNull);
      expect(
        LocationRules.discountCap('101'),
        'Enter 0 to 100, or leave blank',
      );
    });

    test('hours: whole hours in range', () {
      expect(LocationRules.hours('5', 1, 72), isNull);
      expect(LocationRules.hours('0', 1, 72), 'Enter whole hours from 1 to 72');
      expect(LocationRules.hours('', 1, 72), 'Enter whole hours from 1 to 72');
    });
  });

  testWidgets('lists locations with their settings', (tester) async {
    await _open(tester, backend);
    expect(find.byKey(const Key('code-PTB')), findsOneWidget);
    expect(find.byKey(const Key('code-MNJ')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('cap-PTB'))).data,
      'No cap',
    );
    // nextDeviceNo is never shown.
    expect(find.textContaining('evice'), findsNothing);
  });

  testWidgets('creates a location; the PIN goes only to save(newPin:)', (
    tester,
  ) async {
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('location-add')));
    await tester.pumpAndSettle();
    expect(_field(tester, 'location-offline-hours'), '5');
    expect(_field(tester, 'location-extension-hours'), '2');

    await _fillNew(tester, code: 'ktm');
    // Typed in lower case, stored in upper case.
    expect(_field(tester, 'location-code'), 'KTM');
    await _enter(tester, 'location-discount-cap', '15');
    await _save(tester);

    final saved = backend.locations.byCode('KTM')!;
    expect(saved.name, 'Kottayam');
    expect(saved.maxDiscountPct, 15);
    expect(saved.offlineLimitHours, 5);
    expect(saved.nextDeviceNo, 0);
    expect(saved.overridePinHash, FakeLocationService.fakeHash('24681357'));
    // The console passed no hash of its own and a zero device counter.
    expect(backend.locationService.lastSaved!.overridePinHash, isEmpty);
    expect(backend.locationService.lastSaved!.nextDeviceNo, 0);
    expect(backend.audit.actions, [AuditAction.locationUpdate]);
    expect(find.byKey(const Key('code-KTM')), findsOneWidget);
    expect(find.text('24681357'), findsNothing);
  });

  testWidgets('new location: PIN required, 8+ digits, entered twice', (
    tester,
  ) async {
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('location-add')));
    await tester.pumpAndSettle();

    await _fillNew(tester, pin: '', confirm: '');
    await _save(tester);
    expect(find.text('Set an override PIN'), findsOneWidget);

    await _enter(tester, 'location-pin', '1234567');
    await _enter(tester, 'location-pin-confirm', '1234567');
    await _save(tester);
    expect(find.text('Use at least 8 digits'), findsOneWidget);

    await _enter(tester, 'location-pin', '12345678');
    await _enter(tester, 'location-pin-confirm', '12345670');
    await _save(tester);
    expect(find.text('The PINs do not match'), findsOneWidget);

    // Letters are filtered out as they are typed.
    await _enter(tester, 'location-pin', '12ab34');
    expect(_field(tester, 'location-pin'), '1234');

    expect(backend.locations.byCode('KTM'), isNull);
    expect(backend.locationService.lastSaved, isNull);
  });

  testWidgets('new location: bad or taken code, and a cap above 100', (
    tester,
  ) async {
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('location-add')));
    await tester.pumpAndSettle();

    await _fillNew(tester, code: 'K');
    await _enter(tester, 'location-discount-cap', '150');
    await _save(tester);
    expect(find.text('Use 2 to 4 capital letters, e.g. PTB'), findsOneWidget);
    expect(find.text('Enter 0 to 100, or leave blank'), findsOneWidget);

    await _enter(tester, 'location-code', 'PTB');
    await _save(tester);
    expect(find.text('PTB is already used'), findsOneWidget);

    // Five letters are cut to four.
    await _enter(tester, 'location-code', 'KOTTA');
    expect(_field(tester, 'location-code'), 'KOTT');
    expect(backend.locationService.lastSaved, isNull);
  });

  testWidgets('edit: code locked, blank PIN keeps it, nextDeviceNo untouched', (
    tester,
  ) async {
    final before = backend.locations.byCode('PTB')!;
    await _open(tester, backend);
    await _tapVisible(tester, 'edit-location-PTB');

    final code = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('location-code')),
        matching: find.byType(TextField),
      ),
    );
    expect(code.enabled, isFalse);
    expect(_field(tester, 'location-pin'), isEmpty);

    await _enter(tester, 'location-offline-hours', '8');
    await _enter(tester, 'location-discount-cap', '10');
    await _save(tester);

    final after = backend.locations.byCode('PTB')!;
    expect(after.offlineLimitHours, 8);
    expect(after.maxDiscountPct, 10);
    expect(after.overridePinHash, before.overridePinHash);
    expect(after.nextDeviceNo, before.nextDeviceNo);
    expect(
      backend.locationService.lastSaved!.nextDeviceNo,
      before.nextDeviceNo,
    );
    expect(tester.widget<Text>(find.byKey(const Key('cap-PTB'))).data, '10%');
  });

  testWidgets('edit: a new PIN must be 8+ digits and replaces the hash', (
    tester,
  ) async {
    await _open(tester, backend);
    await _tapVisible(tester, 'edit-location-MNJ');

    await _enter(tester, 'location-pin', '4321');
    await _enter(tester, 'location-pin-confirm', '4321');
    await _save(tester);
    expect(find.text('Use at least 8 digits'), findsOneWidget);

    await _enter(tester, 'location-pin', '87654321');
    await _enter(tester, 'location-pin-confirm', '87654321');
    await _save(tester);
    expect(
      backend.locations.byCode('MNJ')!.overridePinHash,
      FakeLocationService.fakeHash('87654321'),
    );
  });

  testWidgets('edit: clearing the cap removes it', (tester) async {
    await _open(tester, backend);
    await _tapVisible(tester, 'edit-location-MNJ');
    await _enter(tester, 'location-discount-cap', '20');
    await _save(tester);
    expect(backend.locations.byCode('MNJ')!.maxDiscountPct, 20);

    await _tapVisible(tester, 'edit-location-MNJ');
    await _enter(tester, 'location-discount-cap', '');
    await _save(tester);
    expect(backend.locations.byCode('MNJ')!.maxDiscountPct, isNull);
  });

  testWidgets('a Store Manager cannot open locations', (tester) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Locations'), findsNothing);
    await goTo(tester, '/locations');
    expect(find.byType(NotPermitted), findsOneWidget);
  });
}
