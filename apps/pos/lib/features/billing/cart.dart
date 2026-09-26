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
  /// Returns [BillError.tooManyLines], and leaves the cart as it is, when the
  /// product is new and the cart already has `Limits.maxBillLines` lines
  /// (D-030, QA-027). Returns null otherwise.
  BillError? add(Product product) {
    final price = product.price;
    if (price == null) return null;
    if (qtyOf(product.id) > 0) {
      increment(product.id);
      return null;
    }
    if (state.length >= Limits.maxBillLines) return BillError.tooManyLines;
    state = [
      ...state,
      CartLine(
        productId: product.id,
        name: product.name,
        qty: 1,
        unitPrice: price,
      ),
    ];
    return null;
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

/// The cart's totals without a discount, or why they can't be computed.
final class CartTotals {
  const CartTotals.ok(BillTotals this.totals) : error = null;
  const CartTotals.invalid(BillError this.error) : totals = null;

  final BillTotals? totals;
  final BillError? error;
}

/// Totals of the cart, or null when it's empty. Never throws: a cart the
/// calculator refuses comes back as [CartTotals.invalid], so the panel can
/// still show its lines and their remove buttons (QA-027).
final cartTotalsProvider = Provider<CartTotals?>((ref) {
  final cart = ref.watch(cartProvider);
  if (cart.isEmpty) return null;
  try {
    return CartTotals.ok(BillCalculator.compute(cart));
  } on BillValidationException catch (e) {
    return CartTotals.invalid(e.error);
  }
});
