import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_pos/widgets/offline_banner.dart';

import 'helpers.dart';

/// Pumps the app on [clock], then moves the clock by [after] and lets the
/// guard re-check the limit.
Future<FakeBackend> pumpAt(
  WidgetTester tester,
  TestClock clock, {
  Duration after = Duration.zero,
}) async {
  final b = await pumpPos(tester, backend: fakeBackend(clock: clock));
  await moveClock(tester, b, clock, after);
  return b;
}

Future<void> moveClock(
  WidgetTester tester,
  FakeBackend b,
  TestClock clock,
  Duration by,
) async {
  clock.advance(by);
  b.offline.evaluate();
  await tester.pumpAndSettle();
}

const _limit = Duration(hours: Location.defaultOfflineLimitHours);

void main() {
  group('offline banner', () {
    testWidgets('hidden within the limit', (tester) async {
      await pumpAt(tester, TestClock(), after: const Duration(hours: 3));
      expect(find.byKey(const Key('offline-banner')), findsNothing);
    });

    testWidgets('amber at 80% of the limit, counting down with the clock', (
      tester,
    ) async {
      final clock = TestClock();
      final b = await pumpAt(tester, clock, after: _limit * 0.8);
      expect(b.offline.current, isA<NearLimit>());
      expect(
        textOf(tester, 'offline-banner-text'),
        'Connect to internet — billing will stop in 1 h',
      );
      final banner = tester.widget<Material>(
        find.byKey(const Key('offline-banner')),
      );
      expect(banner.color, OfflineBanner.amber);

      // No new emission: the banner counts down from the device clock.
      clock.advance(const Duration(minutes: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(textOf(tester, 'offline-banner-text'), endsWith('45 min'));

      // Every screen shows it, with the same time.
      await openNav(tester, 'Stock');
      expect(textOf(tester, 'offline-banner-text'), endsWith('45 min'));

      await moveClock(tester, b, clock, const Duration(minutes: 45));
      expect(b.offline.current, isA<BillingBlocked>());
      expect(find.byKey(const Key('offline-banner')), findsNothing);
    });

    test('formatCountdown rounds up to whole minutes', () {
      expect(
        formatCountdown(const Duration(minutes: 44, seconds: 1)),
        '45 min',
      );
      expect(formatCountdown(const Duration(minutes: 90)), '1 h 30 min');
      expect(formatCountdown(const Duration(hours: 2)), '2 h');
      expect(formatCountdown(const Duration(seconds: -5)), '0 min');
    });
  });

  group('billing block', () {
    testWidgets('blocks billing only; stock and bills keep working', (
      tester,
    ) async {
      final b = await pumpAt(tester, TestClock(), after: _limit);
      expect(find.byKey(const Key('billing-blocked')), findsOneWidget);
      expect(find.text('Billing is paused'), findsOneWidget);
      expect(find.byKey(const Key('product-bf-500')), findsNothing);
      expect(find.byKey(const Key('charge')), findsNothing);

      await tapKey(tester, 'open-stock');
      expect(find.widgetWithText(AppBar, 'Stock'), findsOneWidget);
      await tapKey(tester, 'op-in');
      await pick(tester, 'line-item-0', 'Butter');
      await enterKey(tester, 'line-qty-0', '500');
      await tapKey(tester, 'save');
      expect(b.stock.movements, hasLength(1));

      await addBill(b, {'bf-500': 1});
      await openNav(tester, 'Bills');
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('Retry sync: stays blocked offline, unblocks once synced', (
      tester,
    ) async {
      final clock = TestClock();
      final b = await pumpAt(tester, clock, after: _limit);
      b.sync.online = false;
      await tapKey(tester, 'retry-sync');
      expect(b.sync.syncNowCalls, 1);
      expect(find.byKey(const Key('billing-blocked')), findsOneWidget);
      expect(find.byKey(const Key('retry-result')), findsOneWidget);

      b.sync.online = true;
      await tapKey(tester, 'retry-sync');
      expect(b.sync.syncNowCalls, 2);
      expect(b.sync.lastSyncAt, clock.now);
      expect(find.byKey(const Key('billing-blocked')), findsNothing);
      expect(find.byKey(const Key('product-bf-500')), findsOneWidget);
    });

    testWidgets('PIN override: short and wrong PINs fail, the right one '
        'allows billing until the extension ends', (tester) async {
      final clock = TestClock();
      final b = await pumpAt(tester, clock, after: const Duration(hours: 9));

      await enterKey(tester, 'override-pin', '2468');
      await tapKey(tester, 'override-submit');
      expect(find.textContaining('at least 8 digits'), findsOneWidget);
      expect(b.offline.overrideCalls, isEmpty);

      await enterKey(tester, 'override-pin', '11112222');
      await tapKey(tester, 'override-submit');
      expect(find.text('Wrong PIN. Billing stays paused.'), findsOneWidget);
      expect(find.byKey(const Key('billing-blocked')), findsOneWidget);
      expect(b.offline.auditIds, isEmpty);

      await enterKey(tester, 'override-pin', FakeOfflineGuard.defaultPin);
      await tapKey(tester, 'override-submit');
      expect(find.byKey(const Key('billing-blocked')), findsNothing);
      expect(find.byKey(const Key('product-bf-500')), findsOneWidget);
      expect(find.byKey(const Key('override-ok')), findsOneWidget);
      expect(b.offline.auditIds, [
        Ids.overrideAuditId(Seed.locationId, Seed.deviceId, clock.now),
      ]);
      // However long it was offline, the override runs its full 2 hours,
      // and the banner counts down to its end.
      expect(
        textOf(tester, 'offline-banner-text'),
        endsWith('billing will stop in 2 h'),
      );

      await moveClock(tester, b, clock, const Duration(hours: 1, minutes: 50));
      expect(textOf(tester, 'offline-banner-text'), endsWith('10 min'));
      await moveClock(tester, b, clock, const Duration(minutes: 10));
      expect(find.byKey(const Key('billing-blocked')), findsOneWidget);
    });

    testWidgets('the payment page blocks too, and keeps the cart', (
      tester,
    ) async {
      final clock = TestClock();
      final b = await pumpAt(tester, clock);
      await tapKey(tester, 'product-bf-500');
      await tapKey(tester, 'charge');
      expect(isEnabled(tester, 'save'), isTrue);

      await moveClock(tester, b, clock, _limit);
      expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
      expect(find.byKey(const Key('billing-blocked')), findsOneWidget);
      expect(find.byKey(const Key('save')), findsNothing);

      await enterKey(tester, 'override-pin', FakeOfflineGuard.defaultPin);
      await tapKey(tester, 'override-submit');
      expect(isEnabled(tester, 'save'), isTrue);
      await tapKey(tester, 'save');
      expect(b.sales.createCalls, hasLength(1));
    });
  });

  group('sync health', () {
    testWidgets('lists sync errors, opened from the sync chip', (tester) async {
      final b = await pumpPos(tester);
      b.sync
        ..addError(
          SyncError(
            path: 'locations/PTB/bills/D01-000007',
            detail: 'PERMISSION_DENIED: user disabled',
            at: testNow,
          ),
        )
        ..addError(
          SyncError(
            path: 'locations/PTB/movements/D01-000003',
            detail: 'PERMISSION_DENIED',
            at: testNow,
          ),
        );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync-chip')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Sync health'), findsOneWidget);
      expect(find.text('Sync errors (2)'), findsOneWidget);
      expect(textOf(tester, 'sync-error-0'), contains('D01-000007'));
      expect(textOf(tester, 'sync-error-0'), contains('user disabled'));
      expect(textOf(tester, 'sync-error-1'), contains('movements/D01-000003'));

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sync-errors-badge'), '2');
    });

    testWidgets('no errors, last sync, and Sync now', (tester) async {
      final clock = TestClock();
      final b = await pumpAt(tester, clock);
      b.sync.lastSyncAt = null;
      await openNav(tester, 'Sync health');
      expect(find.byKey(const Key('no-sync-errors')), findsOneWidget);
      expect(textOf(tester, 'last-sync'), contains('Not yet'));
      expect(textOf(tester, 'limit'), contains('Billing allowed'));

      clock.advance(const Duration(minutes: 5));
      await tapKey(tester, 'sync-now');
      expect(b.sync.syncNowCalls, 1);
      expect(b.sync.lastSyncAt, clock.now);
      expect(
        textOf(tester, 'last-sync'),
        contains(DateFormat('HH:mm').format(clock.now.toLocal())),
      );
    });
  });

  test('the fake guard follows the location limit and the last sync', () {
    final clock = TestClock();
    DateTime? last = clock.now;
    const location = Location(
      code: 'PTB',
      name: 'Test',
      address: '',
      phone: '',
      overridePinHash: '',
      receiptFooter: '',
      nextDeviceNo: 1,
      active: true,
      offlineLimitHours: 10,
    );
    final guard = FakeOfflineGuard(
      now: clock.call,
      lastSyncAt: () => last,
      location: () => location,
    );
    clock.advance(const Duration(hours: 7, minutes: 59));
    expect(guard.evaluate(), isA<WithinLimit>());
    clock.advance(const Duration(minutes: 1));
    expect(
      (guard.evaluate() as NearLimit).billingStopsIn,
      const Duration(hours: 2),
    );
    clock.advance(const Duration(hours: 2));
    expect(guard.evaluate(), isA<BillingBlocked>());
    last = clock.now;
    guard.synced();
    expect(guard.current, isA<WithinLimit>());
  });
}
