import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';

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
}
