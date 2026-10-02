import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';

/// The outcome of one `createBill` call: the saved bill, or a message.
/// [lock] is true when it's unclear whether the bill was written, so
/// another try could make a second bill.
final class SubmitResult {
  const SubmitResult.saved(Bill this.bill) : error = null, lock = false;
  const SubmitResult.failed(String this.error, {this.lock = false})
    : bill = null;

  final Bill? bill;
  final String? error;
  final bool lock;

  /// The failure text, with the warning that goes with a [lock].
  String? get message => error == null
      ? null
      : lock
      ? "$error\nThe bill may have been saved. Check today's bills before "
            'billing these items again.'
      : error;
}

/// Calls `SalesService.createBill` once and turns every failure into a
/// message. Both the payment page (review off) and the review page use it,
/// so the failures read the same.
Future<SubmitResult> submitBill(
  WidgetRef ref,
  NewBill bill, {
  int? maxDiscountPct,
}) async {
  try {
    return SubmitResult.saved(
      await ref.read(salesServiceProvider).createBill(bill),
    );
  } on BillValidationException catch (e) {
    return SubmitResult.failed(
      Messages.billError(e.error, maxDiscountPct: maxDiscountPct),
    );
  } on DataFailure catch (e) {
    return SubmitResult.failed(
      Messages.failure(e),
      lock: e.reason == FailureReason.unknown,
    );
  } catch (_) {
    return SubmitResult.failed(
      Messages.failure(const DataFailure(FailureReason.unknown)),
      lock: true,
    );
  }
}
