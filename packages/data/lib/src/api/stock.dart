import 'package:nexus_core/nexus_core.dart';

/// One item and a positive quantity in base units (D-006).
final class StockLineInput {
  const StockLineInput({required this.itemKey, required this.qty});

  /// `RM_{materialId}` or `FG_{productId}`.
  final String itemKey;
  final int qty;
}

abstract interface class StockRepository {
  /// Every stock doc at [locationId]. Quantities may be negative.
  Stream<List<StockItem>> watchStock(String locationId);

  /// Items at or below their threshold (D-015), computed in the app.
  Stream<List<StockItem>> watchLowStock(String locationId);
}

/// Stock operations at the signed-in user's location. Each is one movement
/// plus increments, and an audit entry where 04-PERMISSIONS #10 requires it.
abstract interface class StockService {
  /// Raw materials received.
  Future<Movement> stockIn(List<StockLineInput> lines, {String? note});

  /// Raw materials taken out for a reason other than wastage.
  Future<Movement> stockOutRaw(
    List<StockLineInput> lines, {
    required String reason,
  });

  /// WASTAGE_RAW or WASTAGE_FG, chosen by [kind].
  Future<Movement> wastage(
    StockKind kind,
    List<StockLineInput> lines, {
    required String reason,
  });

  /// Raw materials consumed and finished goods made, in one movement.
  Future<Movement> produce({
    required List<StockLineInput> consumed,
    required List<StockLineInput> produced,
  });

  /// A physical count: records `counted − localQty` as the delta (03-SYNC §5).
  Future<Movement> adjust({
    required String itemKey,
    required int countedQty,
    required String reason,
  });

  /// Null clears the threshold (`stock.threshold`).
  Future<void> setThreshold(String itemKey, int? threshold);
}
