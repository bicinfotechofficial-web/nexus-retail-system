import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

/// The cart: one line per product (D-024 e), in the order items were added.
/// Holds only products and quantities; every total comes from
/// `BillCalculator`.
class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  int qtyOf(String productId) {
    for (final l in state) {
      if (l.productId == productId) return l.qty;
    }
    return 0;
  }

  /// Adds one of [product], or one more if it's already in the cart.
  void add(Product product) {
    final price = product.price;
    if (price == null) return;
    if (qtyOf(product.id) > 0) {
      increment(product.id);
      return;
    }
    state = [
      ...state,
      CartLine(
        productId: product.id,
        name: product.name,
        qty: 1,
        unitPrice: price,
      ),
    ];
  }

  void increment(String productId) => _setQty(productId, qtyOf(productId) + 1);

  /// One fewer; the line goes when it reaches zero.
  void decrement(String productId) => _setQty(productId, qtyOf(productId) - 1);

  void remove(String productId) =>
      state = [...state.where((l) => l.productId != productId)];

  void clear() => state = const [];

  void _setQty(String productId, int qty) {
    if (qty <= 0) {
      remove(productId);
      return;
    }
    state = [
      for (final l in state)
        if (l.productId == productId)
          CartLine(
            productId: l.productId,
            name: l.name,
            qty: qty,
            unitPrice: l.unitPrice,
          )
        else
          l,
    ];
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(
  CartNotifier.new,
);

/// Totals of the cart without a discount, or null when it's empty.
final cartTotalsProvider = Provider<BillTotals?>((ref) {
  final cart = ref.watch(cartProvider);
  if (cart.isEmpty) return null;
  return BillCalculator.compute(cart);
});
