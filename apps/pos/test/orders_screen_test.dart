import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_pos/features/orders/due_counts.dart';

import 'helpers.dart';

/// POS-21: the Orders screen, the home banner and the count badges (D-043).
/// "Today" in these tests is 2026-09-26 (10:30 IST).
const _overdue = '2026-09-25';
const _today = '2026-09-26';
const _tomorrow = '2026-09-27';
const _later = '2026-09-30';

PreOrder _order(
  FakeOrders orders,
  String due, {
  String? time,
  String customer = 'Test Customer',
  String description = 'Black Forest, 1 kg',
  int price = 1200,
  int advance = 500,
}) => orders.add(
  dueDate: due,
  dueTime: time,
  customer: customer,
  description: description,
  price: price,
  advance: advance,
);

Future<PreorderFakes> openOrders(
  WidgetTester tester,
  void Function(FakeOrders) seed, {
  TestClock? clock,
  SessionContext? session,
}) async {
  final b = fakeBackend(clock: clock, session: session);
  final f = PreorderFakes(b, now: clock?.call);
  seed(f.orders);
  await pumpPos(tester, backend: b, fakes: f);
  await openNav(tester, 'Orders');
  expect(find.widgetWithText(AppBar, 'Orders'), findsOneWidget);
  return f;
}

void main() {
  group('the open list', () {
    testWidgets('groups orders Overdue, Due today, Due tomorrow and Later', (
      tester,
    ) async {
      late PreOrder over, noon, evening, tom, later;
      await openOrders(tester, (o) {
        later = _order(o, _later, time: '10:00', customer: 'Lata');
        tom = _order(o, _tomorrow, time: '09:00', customer: 'Tara');
        evening = _order(o, _today, time: '18:00', customer: 'Evan');
        noon = _order(o, _today, time: '12:00', customer: 'Noor');
        over = _order(o, _overdue, time: '17:00', customer: 'Omar');
      });
      expect(textOf(tester, 'group-overdue'), 'Overdue (1)');
      expect(textOf(tester, 'group-today'), 'Due today (2)');
      expect(textOf(tester, 'group-tomorrow'), 'Due tomorrow (1)');
      expect(textOf(tester, 'group-later'), 'Later (1)');

      // Top to bottom: the groups in order, and noon before evening.
      double y(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      final order = [
        y('group-overdue'),
        y('order-${over.id}'),
        y('group-today'),
        y('order-${noon.id}'),
        y('order-${evening.id}'),
        y('group-tomorrow'),
        y('order-${tom.id}'),
        y('group-later'),
        y('order-${later.id}'),
      ];
      expect(order, orderedEquals([...order]..sort()));
    });

    testWidgets('a card shows the due time, customer, first line of the '
        'description and the balance', (tester) async {
      late PreOrder o;
      await openOrders(tester, (f) {
        o = _order(
          f,
          _today,
          time: '16:30',
          customer: 'Meera',
          description: 'Red Velvet 2 kg\nWrite "Happy Birthday Ammu"',
          price: 2400,
          advance: 1000,
        );
      });
      expect(textOf(tester, 'order-due-${o.id}'), 'Today, 16:30');
      final card = find.byKey(Key('order-${o.id}'));
      expect(
        find.descendant(of: card, matching: find.textContaining('Meera')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Red Velvet 2 kg'),
        ),
        findsOneWidget,
      );
      // Only the first line of the description.
      expect(find.textContaining('Happy Birthday'), findsNothing);
      expect(textOf(tester, 'order-balance-${o.id}'), '₹1,400.00');
    });

    testWidgets('an order with no time says so, and a later one shows its '
        'date', (tester) async {
      late PreOrder a, b;
      await openOrders(tester, (f) {
        a = _order(f, _today);
        b = _order(f, _later, time: '08:15');
      });
      expect(textOf(tester, 'order-due-${a.id}'), 'Today, no time set');
      expect(textOf(tester, 'order-due-${b.id}'), 'Wed, 30 Sep, 08:15');
    });

    testWidgets('groups with no orders are not shown', (tester) async {
      await openOrders(tester, (f) => _order(f, _later));
      expect(find.byKey(const Key('group-overdue')), findsNothing);
      expect(find.byKey(const Key('group-today')), findsNothing);
      expect(find.byKey(const Key('group-tomorrow')), findsNothing);
      expect(find.byKey(const Key('group-later')), findsOneWidget);
    });

    testWidgets('says so when nothing is open', (tester) async {
      await openOrders(tester, (_) {});
      expect(textOf(tester, 'orders-empty'), 'No open orders.');
    });

    testWidgets('moves an order from Due tomorrow to Due today across '
        'midnight IST, and today\'s to Overdue', (tester) async {
      // 23:59 IST on the 26th.
      final clock = TestClock(DateTime.utc(2026, 9, 26, 18, 29));
      late PreOrder dueToday, dueTomorrow;
      await openOrders(tester, (f) {
        dueToday = _order(f, _today);
        dueTomorrow = _order(f, _tomorrow);
      }, clock: clock);
      expect(textOf(tester, 'group-today'), 'Due today (1)');
      expect(textOf(tester, 'group-tomorrow'), 'Due tomorrow (1)');
      expect(find.byKey(const Key('group-overdue')), findsNothing);

      // One minute later it is 00:00 IST on the 27th: a new business day.
      clock.advance(const Duration(minutes: 1));
      await openNav(tester, 'Billing');
      await openNav(tester, 'Orders');
      expect(textOf(tester, 'group-overdue'), 'Overdue (1)');
      expect(textOf(tester, 'group-today'), 'Due today (1)');
      expect(find.byKey(const Key('group-tomorrow')), findsNothing);
      // The same two orders, in their new groups.
      double y(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(y('order-${dueToday.id}'), lessThan(y('group-today')));
      expect(y('order-${dueTomorrow.id}'), greaterThan(y('group-today')));
    });

    testWidgets('a new order appears as it is saved', (tester) async {
      late FakeOrders orders;
      await openOrders(tester, (o) => orders = o);
      expect(find.byKey(const Key('orders-empty')), findsOneWidget);
      final o = _order(orders, _tomorrow, customer: 'Zoya');
      await tester.pumpAndSettle();
      expect(find.byKey(Key('order-${o.id}')), findsOneWidget);
      expect(find.byKey(const Key('orders-empty')), findsNothing);
    });

    testWidgets('a card opens the order', (tester) async {
      late PreOrder o;
      await openOrders(tester, (f) => o = _order(f, _today, customer: 'Meera'));
      await tapKey(tester, 'order-${o.id}');
      expect(find.widgetWithText(AppBar, 'Order'), findsOneWidget);
      expect(textOf(tester, 'order-no'), o.orderNo);
    });
  });

  group('Recent', () {
    testWidgets('lists delivered and cancelled orders, newest first', (
      tester,
    ) async {
      late FakeOrders orders;
      late PreOrder delivered, cancelled, open;
      final f = await openOrders(tester, (o) {
        orders = o;
        delivered = _order(o, _today, customer: 'Dina');
        cancelled = _order(o, _tomorrow, customer: 'Cathy');
        open = _order(o, _later, customer: 'Olga');
      });
      await orders.deliver(
        orderId: delivered.id,
        payments: [Payment(mode: PaymentMode.cash, amount: delivered.balance)],
      );
      await orders.cancel(
        orderId: cancelled.id,
        reason: 'Changed plans',
        refund: Money.zero,
      );
      await tester.pumpAndSettle();
      expect(f.orders.orders, hasLength(3));
      // Open shows only the open one.
      expect(find.byKey(Key('order-${open.id}')), findsOneWidget);
      expect(find.byKey(Key('order-${delivered.id}')), findsNothing);

      await tapKey(tester, 'tab-recent');
      expect(textOf(tester, 'recent-status-${delivered.id}'), 'Delivered');
      expect(textOf(tester, 'recent-status-${cancelled.id}'), 'Cancelled');
      expect(find.byKey(Key('recent-${open.id}')), findsNothing);
      double y(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(
        y('recent-${cancelled.id}'),
        lessThan(y('recent-${delivered.id}')),
      );
    });

    testWidgets('says so when nothing is closed', (tester) async {
      await openOrders(tester, (_) {});
      await tapKey(tester, 'tab-recent');
      expect(find.byKey(const Key('recent-empty')), findsOneWidget);
    });
  });

  group('the home banner', () {
    Future<PreorderFakes> home(
      WidgetTester tester,
      void Function(FakeOrders) seed, {
      SessionContext? session,
    }) async {
      final b = fakeBackend(session: session);
      final f = PreorderFakes(b);
      seed(f.orders);
      await pumpPos(tester, backend: b, fakes: f);
      return f;
    }

    testWidgets('counts today, tomorrow and overdue when the app opens', (
      tester,
    ) async {
      await home(tester, (o) {
        _order(o, _today);
        _order(o, _today, time: '09:00');
        _order(o, _tomorrow);
        _order(o, _overdue);
        _order(o, _later);
      });
      expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
      expect(
        textOf(tester, 'order-banner-text'),
        '2 orders due today, 1 tomorrow, 1 overdue',
      );
    });

    testWidgets('has no banner when nothing is due soon', (tester) async {
      await home(tester, (o) => _order(o, _later));
      expect(find.byKey(const Key('order-banner')), findsNothing);
    });

    testWidgets('has no banner without open orders', (tester) async {
      await home(tester, (_) {});
      expect(find.byKey(const Key('order-banner')), findsNothing);
    });

    testWidgets('has no banner without order.manage', (tester) async {
      await home(
        tester,
        (o) => _order(o, _today),
        session: sessionWith([Permission.billCreate, Permission.reportOwn]),
      );
      expect(find.byKey(const Key('order-banner')), findsNothing);
      expect(find.byKey(const Key('orders-entry')), findsNothing);
    });

    testWidgets('tapping it opens the Orders screen', (tester) async {
      await home(tester, (o) => _order(o, _tomorrow));
      expect(textOf(tester, 'order-banner-text'), '1 order due tomorrow');
      await tapKey(tester, 'order-banner');
      expect(find.widgetWithText(AppBar, 'Orders'), findsOneWidget);
      expect(find.byKey(const Key('group-tomorrow')), findsOneWidget);
    });

    testWidgets('can be dismissed for the session', (tester) async {
      await home(tester, (o) => _order(o, _overdue));
      expect(textOf(tester, 'order-banner-text'), '1 order overdue');
      await tapKey(tester, 'order-banner-dismiss');
      expect(find.byKey(const Key('order-banner')), findsNothing);
      // Still gone after leaving the screen and coming back.
      await openNav(tester, 'Orders');
      await openNav(tester, 'Billing');
      expect(find.byKey(const Key('order-banner')), findsNothing);
    });

    testWidgets('a dismissed banner stays hidden when more orders arrive', (
      tester,
    ) async {
      final f = await home(tester, (o) => _order(o, _today));
      await tapKey(tester, 'order-banner-dismiss');
      _order(f.orders, _today);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-banner')), findsNothing);
    });

    testWidgets('updates live as orders change', (tester) async {
      late PreOrder o;
      final f = await home(tester, (f) => o = _order(f, _today));
      expect(textOf(tester, 'order-banner-text'), '1 order due today');
      await f.orders.cancel(
        orderId: o.id,
        reason: 'No longer wanted',
        refund: Money.zero,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-banner')), findsNothing);
    });
  });

  group('the count badges', () {
    testWidgets('the Orders entry on the home screen and the menu show '
        'overdue, today and tomorrow, not later', (tester) async {
      final b = fakeBackend();
      final f = PreorderFakes(b);
      _order(f.orders, _overdue);
      _order(f.orders, _today);
      _order(f.orders, _today);
      _order(f.orders, _tomorrow);
      _order(f.orders, _later);
      await pumpPos(tester, backend: b, fakes: f);
      expect(
        tester.widget<Badge>(find.byKey(const Key('orders-entry-badge'))).label,
        isA<Text>().having((t) => t.data, 'count', '4'),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Badge>(find.byKey(const Key('orders-badge'))).label,
        isA<Text>().having((t) => t.data, 'count', '4'),
      );
    });

    testWidgets('no badge when nothing is due soon, and the entry opens '
        'Orders', (tester) async {
      final b = fakeBackend();
      final f = PreorderFakes(b);
      _order(f.orders, _later);
      await pumpPos(tester, backend: b, fakes: f);
      expect(
        tester
            .widget<Badge>(find.byKey(const Key('orders-entry-badge')))
            .isLabelVisible,
        isFalse,
      );
      await tapKey(tester, 'orders-entry');
      expect(find.widgetWithText(AppBar, 'Orders'), findsOneWidget);
    });
  });

  group('DueCounts', () {
    test('words the banner', () {
      String? msg({int o = 0, int t = 0, int m = 0}) =>
          DueCounts(overdue: o, today: t, tomorrow: m).message;
      expect(msg(), isNull);
      expect(msg(t: 1), '1 order due today');
      expect(
        msg(t: 2, m: 1, o: 1),
        '2 orders due today, 1 tomorrow, 1 overdue',
      );
      expect(msg(m: 3, o: 2), '3 orders due tomorrow, 2 overdue');
      expect(msg(o: 1), '1 order overdue');
      expect(msg(t: 1, o: 4), '1 order due today, 4 overdue');
    });

    test('counts by business date', () {
      final orders = FakeOrders(
        auth: FakeAuthService(),
        bills: FakeSalesRepository(),
        now: () => testNow,
      );
      final list = [
        _order(orders, '2026-09-24'),
        _order(orders, _overdue),
        _order(orders, _today),
        _order(orders, _tomorrow),
        _order(orders, '2026-09-28'),
      ];
      final c = countDue(list, _today);
      expect((c.overdue, c.today, c.tomorrow, c.later), (2, 1, 1, 1));
      expect(c.attention, 4);
      // At 00:00 IST the next day the same orders shift one step.
      final next = countDue(list, _tomorrow);
      expect(
        (next.overdue, next.today, next.tomorrow, next.later),
        (3, 1, 1, 0),
      );
    });
  });

  group('permission', () {
    test('the order routes need order.manage', () {
      final withIt = AsyncData<SessionContext?>(
        sessionWith([Permission.billCreate, Permission.orderManage]),
      );
      final without = AsyncData<SessionContext?>(
        sessionWith([Permission.billCreate]),
      );
      for (final path in [
        '/orders',
        Routes.newOrder,
        Routes.orderSaved,
        Routes.order('D01-O000001'),
        Routes.deliver('D01-O000001'),
        Routes.deliverReview('D01-O000001'),
      ]) {
        expect(Routes.redirect(withIt, path), isNull, reason: path);
        expect(Routes.redirect(without, path), '/', reason: path);
      }
    });

    testWidgets('the menu has no Orders entry without order.manage', (
      tester,
    ) async {
      await pumpPos(
        tester,
        backend: fakeBackend(
          session: sessionWith([Permission.billCreate, Permission.reportOwn]),
        ),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-Orders')), findsNothing);
    });
  });
}
