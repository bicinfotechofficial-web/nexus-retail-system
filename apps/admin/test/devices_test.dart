import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/common/format.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

Future<void> _open(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await tester.tap(find.text('Devices'));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('lists a location\'s devices with last seen and status', (
    tester,
  ) async {
    await _open(tester, backend);
    // MNJ sorts first.
    expect(find.byKey(const Key('device-D01')), findsOneWidget);
    expect(find.text('Back office'), findsOneWidget);
    // Seeded as seen at 11:00 IST; the tests run at 11:30 IST.
    expect(_text(tester, 'seen-D01'), '30 min ago');
    expect(_text(tester, 'seen-D02'), '3 days ago');
    expect(_text(tester, 'seen-D03'), 'Never');
    expect(find.text('MNJ-D01-001322'), findsOneWidget);

    await tester.tap(find.byKey(const Key('devices-location')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pattambi (PTB)').last);
    await tester.pumpAndSettle();
    expect(find.text('Old counter tablet'), findsOneWidget);
    expect(_text(tester, 'device-status-D03'), 'Retired');
    expect(find.byKey(const Key('retire-D03')), findsNothing);
    expect(_text(tester, 'seen-D02'), '1 h ago');
  });

  testWidgets('retiring asks first, then marks the device retired', (
    tester,
  ) async {
    await _open(tester, backend);

    await _tapVisible(tester, 'retire-D02');
    expect(find.text('Retire D02 (Back office)?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'device-status-D02'), 'Active');

    await _tapVisible(tester, 'retire-D02');
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'device-status-D02'), 'Retired');
    expect(find.byKey(const Key('retire-D02')), findsNothing);
    expect(find.text('MNJ D02 is retired.'), findsOneWidget);

    final mnj = backend.devices.store.value['MNJ']!;
    expect(mnj.singleWhere((d) => d.code == 'D02').retired, isTrue);
    // Retiring touches only that device, never the location's counter.
    expect(mnj.where((d) => d.retired), hasLength(1));
    expect(backend.locations.byCode('MNJ')!.nextDeviceNo, 3);
  });

  testWidgets('follows the top-bar location switcher', (tester) async {
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pattambi (PTB)').last);
    await tester.pumpAndSettle();
    expect(find.text('Old counter tablet'), findsOneWidget);
  });

  testWidgets('a Store Manager cannot open devices', (tester) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Devices'), findsNothing);
    await goTo(tester, '/devices');
    expect(find.byType(NotPermitted), findsOneWidget);
  });

  test('formatAgo and formatInstantIst', () {
    final now = DateTime.utc(2026, 9, 26, 6);
    expect(formatAgo(now, now), 'just now');
    expect(
      formatAgo(now.subtract(const Duration(minutes: 5)), now),
      '5 min ago',
    );
    expect(formatAgo(now.subtract(const Duration(hours: 5)), now), '5 h ago');
    expect(formatAgo(now.subtract(const Duration(days: 1)), now), '1 day ago');
    expect(formatInstantIst(now), '26 Sep 2026, 11:30 AM');
    expect(BusinessDate.of(now), testToday);
  });
}
