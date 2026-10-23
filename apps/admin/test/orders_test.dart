import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';
import 'support/fake_orders.dart';
import 'support/overrides.dart';

const _longDescription =
    'Three-layer chocolate truffle cake, 2 kg, with fresh strawberries.\n'
    'Message on the cake: Happy Anniversary.\nNo nuts, please.';

/// Today is 26 Sep. Six orders across two stores and all three statuses.
FakeOrderRepository _repo() => FakeOrderRepository([
  // Due today at 4:30 PM, open.
  order('PTB', 'D01-O000001', dueDate: '2026-09-26', dueTime: '16:30'),
  // Two days overdue, open.
  order(
    'PTB',
    'D01-O000002',
    dueDate: '2026-09-24',
    customer: 'Another Customer',
    phone: '9123456780',
  ),
  // A week-end order, open, with a long description.
  order(
    'MNJ',
    'D02-O000001',
    dueDate: '2026-09-28',
    description: _longDescription,
    price: 3000,
    advance: 1000,
  ),
  // Due tomorrow, no time agreed.
  order('MNJ', 'D02-O000002', dueDate: '2026-09-27', advance: 0),
  // Past its due date but already delivered: not highlighted.
  order(
    'PTB',
    'D01-O000003',
    dueDate: '2026-09-25',
    status: OrderStatus.delivered,
  ),
  // Cancelled, due today: not highlighted.
  order(
    'MNJ',
    'D02-O000003',
    dueDate: '2026-09-26',
    advance: 500,
    status: OrderStatus.cancelled,
    cancel: cancelled(reason: 'Customer changed the date', refunded: 200),
  ),
]);

Future<void> _open(WidgetTester tester, FakeOrderRepository repo) async {
  await pumpAdmin(
    tester,
    FakeBackend.seeded(today: testToday),
    // Tall, so every card is built.
    size: const Size(1400, 3200),
    overrides: newInterfaceOverrides(orders: repo),
  );
  await signIn(tester);
  await goTo(tester, '/orders');
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

List<double> _tops(WidgetTester tester, List<String> ids) => [
  for (final id in ids) tester.getTopLeft(find.byKey(Key('order-$id'))).dy,
];

Future<void> _pickStatus(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('orders-status')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every store soonest due first with the money columns', (
    tester,
  ) async {
    await _open(tester, _repo());

    expect(find.text('6 orders'), findsOneWidget);
    // Overdue 24th, delivered 25th, today 4:30 PM, today (no time), then the
    // 27th and the 28th.
    final tops = _tops(tester, [
      'PTB-D01-O000002',
      'PTB-D01-O000003',
      'PTB-D01-O000001',
      'MNJ-D02-O000003',
      'MNJ-D02-O000002',
      'MNJ-D02-O000001',
    ]);
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet(), hasLength(6));

    const id = 'PTB-D01-O000001';
    expect(find.text('PTB-D01-O000001'), findsOneWidget);
    expect(find.text('Test Customer'), findsWidgets);
    expect(find.text('9876543210'), findsWidgets);
    expect(_text(tester, 'order-due-$id'), '26 Sep 2026, 4:30 PM');
    expect(_text(tester, 'order-price-$id'), '₹1,500.00');
    expect(_text(tester, 'order-advance-$id'), '₹500.00');
    expect(_text(tester, 'order-balance-$id'), '₹1,000.00');
    expect(_text(tester, 'order-desc-$id'), 'Chocolate cake, 1 kg');
    expect(
      find.descendant(
        of: find.byKey(const Key('order-status-$id')),
        matching: find.text('Open'),
      ),
      findsOneWidget,
    );
    // No time agreed: the date alone.
    expect(_text(tester, 'order-due-MNJ-D02-O000002'), '27 Sep 2026');
    expect(_text(tester, 'order-balance-MNJ-D02-O000002'), '₹1,500.00');
    expect(find.text('Another Customer'), findsOneWidget);
    expect(find.text('9123456780'), findsOneWidget);
  });

  testWidgets('open orders due today or overdue are highlighted', (
    tester,
  ) async {
    await _open(tester, _repo());

    expect(find.byKey(const Key('order-flag-PTB-D01-O000001')), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.byKey(const Key('order-flag-PTB-D01-O000002')), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    // Tomorrow, later, delivered and cancelled orders are not flagged.
    for (final id in [
      'MNJ-D02-O000001',
      'MNJ-D02-O000002',
      'PTB-D01-O000003',
      'MNJ-D02-O000003',
    ]) {
      expect(find.byKey(Key('order-flag-$id')), findsNothing, reason: id);
    }
    // The highlighted card differs from a plain one.
    Color? colorOf(String id) =>
        tester.widget<Card>(find.byKey(Key('order-$id'))).color;
    expect(colorOf('PTB-D01-O000001'), isNotNull);
    expect(colorOf('PTB-D01-O000002'), colorOf('PTB-D01-O000001'));
    expect(colorOf('MNJ-D02-O000001'), isNull);
    expect(colorOf('MNJ-D02-O000003'), isNull);
  });

  testWidgets('a cancelled order shows its reason and refund', (tester) async {
    await _open(tester, _repo());

    expect(
      _text(tester, 'order-reason-MNJ-D02-O000003'),
      'Cancelled: Customer changed the date',
    );
    expect(
      _text(tester, 'order-refund-MNJ-D02-O000003'),
      'Refunded ₹200.00 of the ₹500.00 advance',
    );
    // Open orders have neither.
    expect(find.byKey(const Key('order-reason-PTB-D01-O000001')), findsNothing);
  });

  testWidgets('a long description expands to be read in full', (tester) async {
    await _open(tester, _repo());
    const id = 'MNJ-D02-O000001';

    final collapsed = tester.widget<Text>(
      find.byKey(const Key('order-desc-$id')),
    );
    expect(collapsed.maxLines, 2);
    expect(collapsed.data, isNot(contains('\n')));
    // A short description has no toggle.
    expect(find.byKey(const Key('order-expand-PTB-D01-O000001')), findsNothing);

    await tester.tap(find.byKey(const Key('order-expand-$id')));
    await tester.pumpAndSettle();
    final open = tester.widget<Text>(find.byKey(const Key('order-desc-$id')));
    expect(open.maxLines, isNull);
    expect(open.data, _longDescription);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.byKey(const Key('order-expand-$id')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('order-desc-$id'))).maxLines,
      2,
    );
  });

  testWidgets('filters by store', (tester) async {
    await _open(tester, _repo());

    await tester.tap(find.byKey(const Key('orders-store')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manjeri (MNJ)').last);
    await tester.pumpAndSettle();
    expect(find.text('3 orders'), findsOneWidget);
    expect(find.byKey(const Key('order-MNJ-D02-O000001')), findsOneWidget);
    expect(find.byKey(const Key('order-PTB-D01-O000001')), findsNothing);

    await tester.tap(find.byKey(const Key('orders-store')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All stores').last);
    await tester.pumpAndSettle();
    expect(find.text('6 orders'), findsOneWidget);
  });

  testWidgets('filters by status', (tester) async {
    final repo = _repo();
    await _open(tester, repo);

    await _pickStatus(tester, 'Open');
    expect(find.text('4 orders'), findsOneWidget);
    expect(repo.queries.last, 'OPEN null null');

    await _pickStatus(tester, 'Delivered');
    expect(find.text('1 order'), findsOneWidget);
    expect(find.byKey(const Key('order-PTB-D01-O000003')), findsOneWidget);

    await _pickStatus(tester, 'Cancelled');
    expect(find.text('1 order'), findsOneWidget);
    expect(find.byKey(const Key('order-MNJ-D02-O000003')), findsOneWidget);
    expect(repo.queries.last, 'CANCELLED null null');
  });

  testWidgets('filters by a due-date range and combines the filters', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, repo);

    // From the 26th: today (2), tomorrow, the 28th.
    await tester.tap(find.byKey(const Key('orders-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('26'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('From 26 Sep 2026'), findsOneWidget);
    expect(find.text('4 orders'), findsOneWidget);
    expect(repo.queries.last, 'null 2026-09-26 null');

    // To the 27th: today (2) and tomorrow.
    await tester.tap(find.byKey(const Key('orders-to')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('3 orders'), findsOneWidget);
    expect(repo.queries.last, 'null 2026-09-26 2026-09-27');
    expect(find.byKey(const Key('order-MNJ-D02-O000001')), findsNothing);

    // Together with the status.
    await _pickStatus(tester, 'Open');
    expect(find.text('2 orders'), findsOneWidget);

    await tester.tap(find.byKey(const Key('orders-clear-dates')));
    await tester.pumpAndSettle();
    expect(find.text('4 orders'), findsOneWidget);
    expect(find.byKey(const Key('orders-clear-dates')), findsNothing);
  });

  testWidgets('says so when no order matches', (tester) async {
    await _open(
      tester,
      FakeOrderRepository([order('PTB', 'D01-O000001', dueDate: '2026-09-26')]),
    );
    await _pickStatus(tester, 'Cancelled');
    expect(find.byKey(const Key('orders-empty')), findsOneWidget);
    expect(find.text('0 orders'), findsOneWidget);
  });

  testWidgets('a Store Manager has no Orders entry and is refused', (
    tester,
  ) async {
    await pumpAdmin(
      tester,
      FakeBackend.seeded(today: testToday),
      overrides: newInterfaceOverrides(orders: _repo()),
    );
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Orders'),
      ),
      findsNothing,
    );
    await goTo(tester, '/orders');
    expect(
      find.text('You do not have permission to view this page.'),
      findsOneWidget,
    );
  });

  testWidgets('the list reads on a phone', (tester) async {
    await pumpAdmin(
      tester,
      FakeBackend.seeded(today: testToday),
      size: const Size(390, 3200),
      overrides: newInterfaceOverrides(orders: _repo()),
    );
    await signIn(tester);
    await goTo(tester, '/orders');
    expect(tester.takeException(), isNull);
    expect(find.text('6 orders'), findsOneWidget);
  });
}
