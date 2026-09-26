import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

const _flour = 'RM_flour';
const _sugar = 'RM_sugar';
const _eggs = 'RM_eggs';
const _cocoa = 'RM_cocoa';
const _vegPuff = 'FG_veg-puff';
const _brownie = 'FG_brownie';
const _bf500 = 'FG_bf-500';

Future<FakeBackend> openStock(WidgetTester tester, {FakeBackend? b}) async {
  final backend = await pumpPos(tester, backend: b);
  await openNav(tester, 'Stock');
  return backend;
}

/// Scrolls the stock list until the row of [itemKey] is built.
Future<void> showRow(WidgetTester tester, String itemKey) async {
  await tester.dragUntilVisible(
    find.byKey(Key('stock-$itemKey')),
    find.byKey(const Key('stock-list')),
    const Offset(0, -100),
  );
  await tester.pumpAndSettle();
}

int qtyAt(FakeBackend b, String itemKey) =>
    b.stock.item(Seed.locationId, itemKey)!.qty;

void main() {
  group('stock hub', () {
    testWidgets('lists current stock with negatives in red', (tester) async {
      await openStock(tester);
      expect(find.widgetWithText(AppBar, 'Stock'), findsOneWidget);
      await showRow(tester, _flour);
      expect(textOf(tester, 'qty-$_flour'), '12,000 g');
      final flourColor = tester
          .widget<Text>(find.byKey(const Key('qty-$_flour')))
          .style
          ?.color;
      await showRow(tester, _vegPuff);
      expect(textOf(tester, 'qty-$_vegPuff'), '-2 pcs');

      final context = tester.element(find.byKey(const Key('stock-list')));
      final error = Theme.of(context).colorScheme.error;
      Color? colorOf(String key) =>
          tester.widget<Text>(find.byKey(Key(key))).style?.color;
      expect(colorOf('qty-$_vegPuff'), error);
      expect(flourColor, isNot(error));
    });

    testWidgets('the low-stock list and the nav badge', (tester) async {
      final b = await openStock(tester);
      final low = Seed.stock.where((i) => i.isLow).map((i) => i.itemKey);
      expect(low, unorderedEquals([_sugar, _eggs, _vegPuff, _brownie]));

      expect(textOf(tester, 'tab-low'), 'Low stock (4)');
      await tapKey(tester, 'tab-low');
      for (final k in low) {
        await showRow(tester, k);
        expect(find.byKey(Key('stock-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('stock-$_flour')), findsNothing);
      expect(
        tester.widgetList(find.byKey(const Key('stock-list'))),
        hasLength(1),
      );

      // The badge is on the menu button and on Stock in the drawer.
      expect(textOf(tester, 'menu-badge'), '4');
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'low-stock-badge'), '4');
      await tester.tapAt(const Offset(350, 400)); // close the drawer
      await tester.pumpAndSettle();

      // Receiving eggs lifts them above the threshold; the badge follows.
      await b.stock.stockIn(const [StockLineInput(itemKey: _eggs, qty: 12)]);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'menu-badge'), '3');
      expect(find.byKey(const Key('stock-$_eggs')), findsNothing);
    });

    testWidgets('no badge for a role that cannot open Stock', (tester) async {
      await pumpPos(
        tester,
        backend: fakeBackend(session: sessionWith([Permission.billCreate])),
      );
      final badge = tester.widget<Badge>(find.byKey(const Key('menu-badge')));
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('shows only the operations the role is permitted', (
      tester,
    ) async {
      await openStock(
        tester,
        b: fakeBackend(session: sessionWith([Permission.stockAdjust])),
      );
      expect(find.byKey(const Key('op-adjust')), findsOneWidget);
      for (final k in ['op-in', 'op-out', 'op-wastage', 'op-produce']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      // No stock.threshold: rows don't open the threshold editor.
      await tester.tap(find.byKey(const Key('stock-$_flour')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Stock'), findsOneWidget);
    });

    test('routes are gated by stock.move, stock.adjust, stock.threshold', () {
      AsyncData<SessionContext?> only(String p) => AsyncData(sessionWith([p]));
      final move = only(Permission.stockMove);
      final adjust = only(Permission.stockAdjust);
      final threshold = only(Permission.stockThreshold);
      for (final path in [
        Routes.stockIn,
        Routes.stockOut,
        Routes.stockWastage,
        Routes.stockProduce,
      ]) {
        expect(Routes.redirect(move, path), isNull, reason: path);
        expect(Routes.redirect(adjust, path), '/stock', reason: path);
      }
      expect(Routes.redirect(adjust, Routes.stockAdjust), isNull);
      expect(Routes.redirect(move, Routes.stockAdjust), '/stock');
      final t = Routes.stockThreshold(_flour);
      expect(Routes.redirect(threshold, t), isNull);
      expect(Routes.redirect(move, t), '/stock');
    });
  });

  group('stock operations', () {
    testWidgets('Stock In: raw materials with an optional note', (
      tester,
    ) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-in');
      expect(find.widgetWithText(AppBar, 'Stock In'), findsOneWidget);
      expect(isEnabled(tester, 'save'), isFalse);

      await pick(tester, 'line-item-0', 'Maida flour');
      await enterKey(tester, 'line-qty-0', '5000');
      await tapKey(tester, 'line-add');
      // Cocoa has no stock doc yet; Stock In creates it.
      await pick(tester, 'line-item-1', 'Cocoa powder');
      await enterKey(tester, 'line-qty-1', '750');
      expect(isEnabled(tester, 'save'), isTrue); // the note is optional
      await enterKey(tester, 'note', 'Supplier invoice 42');
      await tapKey(tester, 'save');

      final m = b.stock.movements.single;
      expect(m.type, MovementType.stockIn);
      expect(m.note, 'Supplier invoice 42');
      expect(m.lines.map((l) => (l.itemKey, l.delta)), [
        (_flour, 5000),
        (_cocoa, 750),
      ]);
      expect(qtyAt(b, _flour), 17000);
      expect(qtyAt(b, _cocoa), 750);
      expect(find.text('Stock In saved.'), findsOneWidget);
      await showRow(tester, _flour);
      expect(textOf(tester, 'qty-$_flour'), '17,000 g');
    });

    testWidgets('Stock In lists raw materials only', (tester) async {
      await openStock(tester);
      await tapKey(tester, 'op-in');
      await tapKey(tester, 'line-item-0');
      expect(find.text('Sugar').hitTestable(), findsWidgets);
      expect(find.text('Veg Puff').hitTestable(), findsNothing);
    });

    testWidgets('Stock Out: needs a reason', (tester) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-out');
      await pick(tester, 'line-item-0', 'Sugar');
      await enterKey(tester, 'line-qty-0', '500');
      expect(isEnabled(tester, 'save'), isFalse);
      expect(textOf(tester, 'form-problem'), 'Enter a reason.');

      await enterKey(tester, 'reason', 'Sent to Manjeri');
      await tapKey(tester, 'save');
      final m = b.stock.movements.single;
      expect(m.type, MovementType.stockOutRaw);
      expect(m.reason, 'Sent to Manjeri');
      expect(m.lines.single.delta, -500);
      expect(qtyAt(b, _sugar), 2500);
    });

    testWidgets('Wastage of finished goods, with a reason', (tester) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-wastage');
      await pick(tester, 'line-item-0', 'Walnut Brownie');
      await enterKey(tester, 'line-qty-0', '1');
      await enterKey(tester, 'reason', 'Dropped');
      await tapKey(tester, 'save');
      final m = b.stock.movements.single;
      expect(m.type, MovementType.wastageFg);
      expect(m.lines.single.itemKey, _brownie);
      expect(qtyAt(b, _brownie), 0);
    });

    testWidgets('Wastage of raw materials', (tester) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-wastage');
      await tapKey(tester, 'kind-raw');
      await pick(tester, 'line-item-0', 'Fresh cream');
      await enterKey(tester, 'line-qty-0', '250');
      await enterKey(tester, 'reason', 'Expired');
      await tapKey(tester, 'save');
      final m = b.stock.movements.single;
      expect(m.type, MovementType.wastageRaw);
      expect(m.lines.single.delta, -250);
    });

    testWidgets('Produce: several raw materials used, goods made', (
      tester,
    ) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-produce');
      await pick(tester, 'used-item-0', 'Maida flour');
      await enterKey(tester, 'used-qty-0', '1000');
      await tapKey(tester, 'used-add');
      await pick(tester, 'used-item-1', 'Sugar');
      await enterKey(tester, 'used-qty-1', '400');
      expect(isEnabled(tester, 'save'), isFalse); // nothing made yet
      await pick(tester, 'made-item-0', 'Black Forest 500 g');
      await enterKey(tester, 'made-qty-0', '2');
      await tapKey(tester, 'save');

      final m = b.stock.movements.single;
      expect(m.type, MovementType.produce);
      expect(m.lines.map((l) => (l.itemKey, l.delta)), [
        (_flour, -1000),
        (_sugar, -400),
        (_bf500, 2),
      ]);
      expect(qtyAt(b, _bf500), 5);
      expect(find.text('Production saved.'), findsOneWidget);
    });

    testWidgets('Produce: the same item twice is refused', (tester) async {
      await openStock(tester);
      await tapKey(tester, 'op-produce');
      await pick(tester, 'used-item-0', 'Sugar');
      await enterKey(tester, 'used-qty-0', '100');
      await tapKey(tester, 'used-add');
      await pick(tester, 'used-item-1', 'Sugar');
      await enterKey(tester, 'used-qty-1', '100');
      await pick(tester, 'made-item-0', 'Veg Puff');
      await enterKey(tester, 'made-qty-0', '10');
      expect(isEnabled(tester, 'save'), isFalse);
      expect(textOf(tester, 'form-problem'), contains('only one line'));
    });

    testWidgets('a movement stops at Limits.maxMovementLines lines', (
      tester,
    ) async {
      await openStock(tester);
      await tapKey(tester, 'op-produce');
      // Used and made share the limit.
      for (var i = 1; i < Limits.maxMovementLines - 1; i++) {
        await tapKey(tester, 'used-add');
      }
      expect(
        find.byKey(Key('used-item-${Limits.maxMovementLines - 2}')),
        findsOneWidget,
      );
      expect(isEnabled(tester, 'used-add'), isFalse);
      expect(isEnabled(tester, 'made-add'), isFalse);
      expect(find.byKey(const Key('used-limit')), findsOneWidget);

      await tapKey(tester, 'used-remove-0');
      expect(isEnabled(tester, 'made-add'), isTrue);
    });

    testWidgets('Adjust: records the physical count', (tester) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-adjust');
      await pick(tester, 'adjust-item', 'Eggs');
      expect(textOf(tester, 'adjust-current'), 'On this device: 30 pcs');
      await enterKey(tester, 'counted', '40');
      expect(textOf(tester, 'adjust-delta'), 'Change: +10 pcs');
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'reason', 'Weekly count');
      await tapKey(tester, 'save');

      final m = b.stock.movements.single;
      expect(m.type, MovementType.adjust);
      expect(m.reason, 'Weekly count');
      final line = m.lines.single;
      expect(
        (line.itemKey, line.delta, line.before, line.after),
        (_eggs, 10, 30, 40),
      );
      expect(qtyAt(b, _eggs), 40);
    });

    testWidgets('Adjust brings a negative item back to the count', (
      tester,
    ) async {
      final b = await openStock(tester);
      await tapKey(tester, 'op-adjust');
      await pick(tester, 'adjust-item', 'Veg Puff');
      await enterKey(tester, 'counted', '0');
      expect(textOf(tester, 'adjust-delta'), 'Change: +2 pcs');
      await enterKey(tester, 'reason', 'Count');
      await tapKey(tester, 'save');
      expect(qtyAt(b, _vegPuff), 0);
    });

    testWidgets('threshold editing: set, then clear', (tester) async {
      final b = await openStock(tester);
      expect(textOf(tester, 'tab-low'), 'Low stock (4)');
      await showRow(tester, _sugar);
      await tapKey(tester, 'stock-$_sugar');
      expect(find.widgetWithText(AppBar, 'Low-stock alert'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('threshold')),
      );
      expect(field.controller!.text, '4000');

      await enterKey(tester, 'threshold', '2000');
      await tapKey(tester, 'save');
      expect(b.stock.thresholdCalls.last, (_sugar, 2000));
      expect(textOf(tester, 'tab-low'), 'Low stock (3)');

      await showRow(tester, _sugar);
      await tapKey(tester, 'stock-$_sugar');
      await tapKey(tester, 'threshold-clear');
      await tapKey(tester, 'save');
      expect(b.stock.thresholdCalls.last, (_sugar, null));
      expect(b.stock.item(Seed.locationId, _sugar)!.lowThreshold, isNull);
    });

    testWidgets('a failed save shows a friendly message', (tester) async {
      final b = await openStock(tester);
      b.stock.failNext = const DataFailure(FailureReason.notPermitted);
      await tapKey(tester, 'op-in');
      await pick(tester, 'line-item-0', 'Butter');
      await enterKey(tester, 'line-qty-0', '500');
      await tapKey(tester, 'save');
      expect(
        textOf(tester, 'save-error'),
        "You don't have permission to do this.",
      );
      expect(find.widgetWithText(AppBar, 'Stock In'), findsOneWidget);
      expect(isEnabled(tester, 'save'), isTrue); // nothing was written

      await tapKey(tester, 'save');
      expect(b.stock.movements, hasLength(1));
    });
  });
}
