import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_pos/app/messages.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_pos/features/billing/billing_screen.dart';
import 'package:nexus_pos/features/billing/cart.dart';

import 'helpers.dart';

void main() {
  testWidgets('shows only products sellable at this location', (tester) async {
    await pumpPos(tester);
    expect(find.byKey(const Key('product-bf-500')), findsOneWidget);
    // A pending suggestion and another store's special are not sellable.
    expect(find.text('Jackfruit Cake 500 g'), findsNothing);
    expect(find.text('Manjeri Special 500 g'), findsNothing);
  });

  testWidgets('filters by category and by search', (tester) async {
    await pumpPos(tester);
    await tapKey(tester, 'category-Snacks');
    expect(find.text('Veg Puff'), findsOneWidget);
    expect(find.text('Black Forest 500 g'), findsNothing);

    await tapKey(tester, 'category-All');
    await enterKey(tester, 'search', 'red velvet');
    expect(find.text('Red Velvet 500 g'), findsOneWidget);
    expect(find.text('Red Velvet Pastry'), findsOneWidget);
    expect(find.text('Veg Puff'), findsNothing);

    await enterKey(tester, 'search', 'no such cake');
    expect(find.text('No items match.'), findsOneWidget);
  });

  testWidgets('cart: add, qty ±, remove, with totals from BillCalculator', (
    tester,
  ) async {
    await pumpPos(tester);
    expect(isEnabled(tester, 'charge'), isFalse);

    await tapKey(tester, 'product-brownie');
    await tapKey(tester, 'product-rv-pastry');
    await tapKey(tester, 'product-rv-pastry');
    expect(textOf(tester, 'qty-rv-pastry'), '2');

    // 72.50 + 2 × 80.00 = 232.50, rounded to 233.00 (D-010).
    final expected = BillCalculator.compute(const [
      CartLine(
        productId: 'brownie',
        name: 'Walnut Brownie',
        qty: 1,
        unitPrice: Money(7250),
      ),
      CartLine(
        productId: 'rv-pastry',
        name: 'Red Velvet Pastry',
        qty: 2,
        unitPrice: Money(8000),
      ),
    ]);
    expect(expected.total, const Money(23300));
    expect(textOf(tester, 'cart-total'), contains('₹233.00'));
    expect(find.text('₹0.50'), findsOneWidget); // round-off line
    expect(textOf(tester, 'line-total-rv-pastry'), '₹160.00');
    expect(isEnabled(tester, 'charge'), isTrue);

    await tapKey(tester, 'inc-brownie');
    expect(textOf(tester, 'qty-brownie'), '2');
    expect(textOf(tester, 'cart-total'), contains('₹305.00'));

    await tapKey(tester, 'dec-rv-pastry');
    await tapKey(tester, 'dec-rv-pastry');
    expect(find.byKey(const Key('cart-line-rv-pastry')), findsNothing);

    await tapKey(tester, 'remove-brownie');
    expect(find.byKey(const Key('cart')), findsNothing);
    expect(isEnabled(tester, 'charge'), isFalse);
  });

  testWidgets('Charge opens the payment screen', (tester) async {
    await pumpPos(tester);
    await tapKey(tester, 'product-bf-500');
    await tapKey(tester, 'charge');
    expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
  });

  testWidgets('a product beyond the line limit is refused with a message, and '
      'the cart stays usable (QA-027)', (tester) async {
    await pumpPos(tester);
    List<CartLine> cart() => ProviderScope.containerOf(
      tester.element(find.byType(CartPanel)),
    ).read(cartProvider);
    final sellable = Seed.products
        .where((p) => p.isSellableAt(Seed.locationId))
        .toList();
    expect(sellable.length, greaterThan(Limits.maxBillLines));

    // The grid builds lazily: bring a tile into view from the top.
    Future<void> tapProduct(String id) async {
      final tile = find.byKey(Key('product-$id'));
      if (tile.evaluate().isEmpty) {
        await tester.fling(find.byType(GridView), const Offset(0, 3000), 3000);
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          tile,
          find.byType(GridView),
          const Offset(0, -150),
        );
      }
      await tapKey(tester, 'product-$id');
    }

    for (final p in sellable.take(Limits.maxBillLines)) {
      await tapProduct(p.id);
    }
    expect(cart(), hasLength(Limits.maxBillLines));
    expect(find.byKey(const Key('cart-limit')), findsNothing);

    final extra = sellable[Limits.maxBillLines];
    await tapProduct(extra.id);
    expect(cart(), hasLength(Limits.maxBillLines));
    expect(cart().any((l) => l.productId == extra.id), isFalse);
    expect(
      find.text(Messages.billError(BillError.tooManyLines)),
      findsOneWidget,
    );

    // More of a product already in the cart is still fine.
    final first = sellable.first.id;
    await tapProduct(first);
    expect(cart().first.qty, 2);

    // The panel still works: totals, remove, then the new product fits.
    expect(find.byKey(const Key('cart-error')), findsNothing);
    expect(textOf(tester, 'cart-total'), contains('₹'));
    await tapKey(tester, 'remove-$first');
    expect(cart(), hasLength(Limits.maxBillLines - 1));
    await tapProduct(extra.id);
    expect(cart(), hasLength(Limits.maxBillLines));
    expect(cart().last.productId, extra.id);

    expect(isEnabled(tester, 'charge'), isTrue);
    await tapKey(tester, 'charge');
    expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
    expect(isEnabled(tester, 'save'), isTrue);
  });

  test('cartTotalsProvider reports an invalid cart instead of throwing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final products = [
      for (var i = 0; i <= Limits.maxBillLines; i++)
        Product(
          id: 'p$i',
          name: 'Item $i',
          category: 'Cakes',
          price: const Money(1000),
          scope: Product.globalScope,
          status: ProductStatus.active,
          sortOrder: i,
          createdBy: 'seed',
        ),
    ];
    final notifier = container.read(cartProvider.notifier);
    for (final p in products.take(Limits.maxBillLines)) {
      expect(notifier.add(p), isNull);
    }
    expect(notifier.add(products.last), BillError.tooManyLines);
    expect(container.read(cartTotalsProvider)?.totals, isNotNull);

    // Even a cart built around the notifier can't make the provider throw.
    notifier.state = [
      for (final p in products)
        CartLine(productId: p.id, name: p.name, qty: 1, unitPrice: p.price!),
    ];
    final result = container.read(cartTotalsProvider);
    expect(result?.totals, isNull);
    expect(result?.error, BillError.tooManyLines);
  });
}
