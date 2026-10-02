import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_pos/features/stock/stock_history_screen.dart';
import 'package:nexus_pos/features/stock/stock_screen.dart';

import 'helpers.dart';

/// POS-18: the Finished / Raw filter, the Stock history screen and New raw
/// material (D-039).
const _flour = 'RM_flour';
const _sugar = 'RM_sugar';
const _eggs = 'RM_eggs';
const _butter = 'RM_butter';
const _vegPuff = 'FG_veg-puff';
const _brownie = 'FG_brownie';
const _bf500 = 'FG_bf-500';

Future<FakeBackend> openStock(WidgetTester tester, {FakeBackend? b}) async {
  final backend = await pumpPos(tester, backend: b);
  await openNav(tester, 'Stock');
  return backend;
}

/// The stock rows now built.
Set<String> rows(WidgetTester tester) => {
  for (final e in find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> &&
        k.value.startsWith('stock-') &&
        k.value != 'stock-list';
  }).evaluate())
    (e.widget.key! as ValueKey<String>).value.substring(6),
};

Future<void> openHistory(WidgetTester tester) async {
  await tapKey(tester, 'op-history');
  expect(find.widgetWithText(AppBar, 'Stock history'), findsOneWidget);
}

void main() {
  group('Finished / Raw filter', () {
    testWidgets('filters the stock list, and keeps Low stock working', (
      tester,
    ) async {
      await openStock(tester);
      // A tall screen, so every row is built and can be counted.
      tester.view.physicalSize = const Size(1080, 4000);
      await tester.pumpAndSettle();
      expect(rows(tester), containsAll([_flour, _sugar, _eggs, _bf500]));

      await tapKey(tester, 'kind-raw');
      expect(rows(tester), isNotEmpty);
      expect(rows(tester).every((k) => k.startsWith('RM_')), isTrue);
      expect(rows(tester), contains(_flour));
      expect(find.byKey(const Key('stock-$_vegPuff')), findsNothing);

      await tapKey(tester, 'kind-finished');
      expect(rows(tester).every((k) => k.startsWith('FG_')), isTrue);
      expect(rows(tester), contains(_bf500));
      expect(find.byKey(const Key('stock-$_flour')), findsNothing);

      await tapKey(tester, 'kind-all');
      expect(rows(tester), containsAll([_flour, _bf500]));

      // Low stock still shows the four low items, and combines with Raw.
      expect(textOf(tester, 'tab-low'), 'Low stock (4)');
      await tapKey(tester, 'tab-low');
      expect(rows(tester).toSet(), {_eggs, _sugar, _vegPuff, _brownie});
      await tapKey(tester, 'kind-raw');
      expect(rows(tester), {_eggs, _sugar});
      await tapKey(tester, 'kind-finished');
      expect(rows(tester), {_vegPuff, _brownie});
      expect(textOf(tester, 'tab-low'), 'Low stock (4)'); // not narrowed
    });

    testWidgets('says when a kind has nothing', (tester) async {
      final b = fakeBackend();
      b.stock.seed(Seed.locationId, [
        for (final i in Seed.stock)
          if (i.kind == StockKind.raw) i,
      ]);
      await openStock(tester, b: b);
      await tapKey(tester, 'kind-finished');
      expect(find.text('No finished goods here yet.'), findsOneWidget);
    });
  });

  testWidgets('a negative row explains what negative means', (tester) async {
    await openStock(tester);
    await tester.dragUntilVisible(
      find.byKey(const Key('stock-$_vegPuff')),
      find.byKey(const Key('stock-list')),
      const Offset(0, -100),
    );
    expect(
      textOf(tester, 'negative-note-$_vegPuff'),
      'Negative means cakes were sold before they were recorded as made. '
      'Record Produce or Adjust to correct it.',
    );
    expect(negativeStockNote, contains('Record Produce or Adjust'));
    // No note on a row that is not negative.
    expect(find.byKey(const Key('negative-note-$_brownie')), findsNothing);
    expect(find.byKey(const Key('negative-note-$_flour')), findsNothing);
  });

  group('Stock history', () {
    Future<FakeBackend> withMovements(TestClock clock) async {
      final b = fakeBackend(clock: clock);
      await b.stock.stockIn(const [
        StockLineInput(itemKey: _butter, qty: 500),
        StockLineInput(itemKey: _flour, qty: 2000),
      ], note: 'Weekly order');
      clock.advance(const Duration(minutes: 20));
      await b.stock.stockOutRaw(const [
        StockLineInput(itemKey: _sugar, qty: 300),
      ], reason: 'Sent to another store');
      clock.advance(const Duration(minutes: 20));
      await b.stock.wastage(StockKind.finished, const [
        StockLineInput(itemKey: _brownie, qty: 1),
      ], reason: 'Dropped');
      clock.advance(const Duration(minutes: 20));
      await b.stock.adjust(
        itemKey: _eggs,
        countedQty: 30, // the same as before: a zero delta
        reason: 'Recount',
      );
      return b;
    }

    testWidgets('lists the day with time, type, items and signed quantities, '
        'newest first', (tester) async {
      final clock = TestClock();
      final b = await withMovements(clock);
      await openStock(tester, b: b);
      await openHistory(tester);

      final ids = b.stock.movements.map((m) => m.id).toList();
      expect(ids, hasLength(4));
      final moveIn = ids[0];
      final moveOut = ids[1];
      final waste = ids[2];
      // Time is IST: the clock starts at 10:30.
      expect(textOf(tester, 'movement-time-$moveIn'), '10:30');
      expect(textOf(tester, 'movement-time-$moveOut'), '10:50');
      expect(textOf(tester, 'movement-type-$moveIn'), 'Stock In');
      expect(textOf(tester, 'movement-type-$moveOut'), 'Stock Out');
      expect(textOf(tester, 'movement-type-$waste'), 'Wastage (finished)');

      // Names and signed quantities, in the same row.
      final inRow = find.byKey(Key('movement-$moveIn'));
      expect(
        find.descendant(of: inRow, matching: find.text('Butter')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inRow, matching: find.text('+500 g')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inRow, matching: find.text('+2,000 g')),
        findsOneWidget,
      );
      expect(find.text('Weekly order'), findsOneWidget);
      final outRow = find.byKey(Key('movement-$moveOut'));
      expect(
        find.descendant(of: outRow, matching: find.text('-300 g')),
        findsOneWidget,
      );
      // Newest first: the recount is above the first receipt.
      final topY = tester.getTopLeft(find.byKey(Key('movement-${ids[3]}'))).dy;
      final bottomY = tester.getTopLeft(inRow).dy;
      expect(topY, lessThan(bottomY));
    });

    testWidgets('In shows what came in, Out what went out, All everything', (
      tester,
    ) async {
      final clock = TestClock();
      final b = await withMovements(clock);
      await openStock(tester, b: b);
      await openHistory(tester);
      final ids = b.stock.movements.map((m) => m.id).toList();
      Finder row(int i) => find.byKey(Key('movement-${ids[i]}'));

      // All: four movements, including the zero-delta recount.
      for (var i = 0; i < 4; i++) {
        expect(row(i), findsOneWidget, reason: 'all $i');
      }

      await tapKey(tester, 'history-in');
      expect(row(0), findsOneWidget); // Stock In
      expect(row(1), findsNothing);
      expect(row(2), findsNothing);
      expect(row(3), findsNothing); // sums to zero: neither In nor Out

      await tapKey(tester, 'history-out');
      expect(row(0), findsNothing);
      expect(row(1), findsOneWidget); // Stock Out
      expect(row(2), findsOneWidget); // Wastage
      expect(row(3), findsNothing);

      await tapKey(tester, 'history-all');
      expect(row(3), findsOneWidget);
    });

    testWidgets('a movement is In when its deltas sum above zero', (
      tester,
    ) async {
      MovementLine line(int d) => MovementLine(itemKey: _flour, delta: d);
      Movement move(List<MovementLine> lines) => Movement(
        id: 'D01-M000001',
        type: MovementType.produce,
        lines: lines,
        businessDate: '2026-09-26',
        clientCreatedAt: testNow,
        createdBy: 'u',
        deviceId: 'D01',
      );
      expect(directionOf(move([line(-500), line(2)])), isNotNull);
      expect(
        directionOf(move([line(-500), line(2)])),
        MovementDirection.outbound,
      );
      expect(
        directionOf(move([line(500), line(-2)])),
        MovementDirection.inbound,
      );
      expect(directionOf(move([line(5), line(-5)])), isNull);
    });

    testWidgets('the date defaults to today and can go back a day or be '
        'picked', (tester) async {
      final clock = TestClock(testNow.subtract(const Duration(days: 1)));
      final b = fakeBackend(clock: clock);
      await b.stock.stockIn(const [StockLineInput(itemKey: _butter, qty: 250)]);
      final yesterday = b.stock.movements.single;
      expect(yesterday.businessDate, '2026-09-25');
      clock.now = testNow;
      await b.stock.stockOutRaw(const [
        StockLineInput(itemKey: _sugar, qty: 100),
      ], reason: 'Staff tea');
      final today = b.stock.movements.last;
      expect(today.businessDate, '2026-09-26');

      await openStock(tester, b: b);
      await openHistory(tester);
      expect(textOf(tester, 'date-label'), contains('Today'));
      expect(find.byKey(Key('movement-${today.id}')), findsOneWidget);
      expect(find.byKey(Key('movement-${yesterday.id}')), findsNothing);

      await tapKey(tester, 'date-prev');
      expect(find.byKey(Key('movement-${yesterday.id}')), findsOneWidget);
      expect(find.byKey(Key('movement-${today.id}')), findsNothing);

      await tapKey(tester, 'date-next');
      expect(find.byKey(Key('movement-${today.id}')), findsOneWidget);

      // The calendar: pick the 25th.
      await tapKey(tester, 'date-pick');
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('movement-${yesterday.id}')), findsOneWidget);
    });

    testWidgets('an empty day says so, per filter', (tester) async {
      await openStock(tester);
      await openHistory(tester);
      expect(textOf(tester, 'no-movements'), 'No stock movements on this day.');
      await tapKey(tester, 'history-in');
      expect(textOf(tester, 'no-movements'), 'No stock came in on this day.');
      await tapKey(tester, 'history-out');
      expect(textOf(tester, 'no-movements'), 'No stock went out on this day.');
    });

    testWidgets('a new movement appears while the screen is open', (
      tester,
    ) async {
      final b = await openStock(tester);
      await openHistory(tester);
      await b.stock.stockIn(const [StockLineInput(itemKey: _butter, qty: 100)]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('movement-${b.stock.movements.single.id}')),
        findsOneWidget,
      );
    });

    testWidgets('the route needs a stock permission', (tester) async {
      final owner = sessionWith([Permission.billCreate]);
      expect(Routes.redirect(AsyncData(owner), Routes.stockHistory), '/');
      final stock = sessionWith([Permission.stockMove]);
      expect(Routes.redirect(AsyncData(stock), Routes.stockHistory), isNull);
    });
  });

  group('New raw material', () {
    testWidgets('adds the material and selects it on the Stock In line', (
      tester,
    ) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-in');
      await tapKey(tester, 'new-raw-material');
      expect(find.text('New raw material'), findsWidgets);
      // Add stays off until there is a name.
      expect(isEnabled(tester, 'new-material-save'), isFalse);
      await enterKey(tester, 'new-material-name', '  Cardamom ');
      await tapKey(tester, 'new-material-save');

      // It exists in the catalog, and is chosen on the first line.
      final made = b.catalog.rawMaterials.last;
      expect(made.name, 'Cardamom');
      expect(made.unit, StockUnit.g);
      expect(find.text('Cardamom'), findsWidgets);
      await enterKey(tester, 'line-qty-0', '250');
      expect(find.text('Has 0 g'), findsOneWidget);
      await tapKey(tester, 'save');

      final m = b.stock.movements.single;
      expect(m.type, MovementType.stockIn);
      expect(m.lines.single.itemKey, 'RM_${made.id}');
      expect(m.lines.single.delta, 250);
      expect(b.stock.item(Seed.locationId, 'RM_${made.id}')!.name, 'Cardamom');
    });

    testWidgets('takes the unit, and goes on a new line when the first is '
        'used', (tester) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-in');
      await pick(tester, 'line-item-0', 'Butter');
      await tapKey(tester, 'new-raw-material');
      await enterKey(tester, 'new-material-name', 'Vanilla essence');
      await tapKey(tester, 'new-material-ml');
      await tapKey(tester, 'new-material-save');

      expect(b.catalog.rawMaterials.last.unit, StockUnit.ml);
      // Butter stays on line 0, the new one is on line 1.
      expect(find.byKey(const Key('line-item-1')), findsOneWidget);
      await enterKey(tester, 'line-qty-0', '100');
      await enterKey(tester, 'line-qty-1', '50');
      await tapKey(tester, 'save');
      final m = b.stock.movements.single;
      expect(m.lines.map((l) => l.itemKey), [
        _butter,
        'RM_${b.catalog.rawMaterials.last.id}',
      ]);
    });

    testWidgets('a failure shows in the dialog and nothing is added', (
      tester,
    ) async {
      final b = await openStock(tester);
      final before = b.catalog.rawMaterials.length;
      b.catalogService.failNext = const DataFailure(FailureReason.notPermitted);
      await tapKey(tester, 'op-in');
      await tapKey(tester, 'new-raw-material');
      await enterKey(tester, 'new-material-name', 'Cardamom');
      await tapKey(tester, 'new-material-save');
      expect(
        textOf(tester, 'new-material-error'),
        "You don't have permission to do this.",
      );
      expect(b.catalog.rawMaterials, hasLength(before));
      await tapKey(tester, 'new-material-cancel');
      expect(find.byKey(const Key('new-material-name')), findsNothing);
    });

    testWidgets('the button needs rawMaterial.create', (tester) async {
      await pumpPos(
        tester,
        backend: fakeBackend(
          session: sessionWith([Permission.stockMove, Permission.billCreate]),
        ),
      );
      await openNav(tester, 'Stock');
      await tapKey(tester, 'op-in');
      expect(find.byKey(const Key('save')), findsOneWidget);
      expect(find.byKey(const Key('new-raw-material')), findsNothing);
    });
  });
}
