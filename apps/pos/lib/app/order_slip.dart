import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

/// What the POS does with an order's advance slip (D-043): print it, or
/// share it as an image through the share sheet. A thin seam over the
/// printer package's order slip, so the screens don't depend on its names
/// and tests use a fake.
abstract interface class OrderSlipActions {
  /// Prints the slip for [order] on the paired printer. A printer fault is a
  /// [PrintFailed] result, never an exception: the order is already saved.
  Future<PrintResult> print(PreOrder order, Location location);

  /// Renders the slip at the printer's paper width and opens the share
  /// sheet. Throws when the image can't be made or shared.
  Future<void> shareImage(PreOrder order, Location location);
}
