import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// Friendly text for every error the data layer and calculators can raise.
abstract final class Messages {
  static String billError(BillError error, {int? maxDiscountPct}) =>
      switch (error) {
        BillError.emptyCart => 'The cart is empty. Add an item first.',
        BillError.tooManyLines =>
          'A bill can have at most ${Limits.maxBillLines} items. '
              'Start a second bill for the rest.',
        BillError.nonPositiveQty => 'Every item needs a quantity of 1 or more.',
        BillError.negativePrice =>
          'An item has a negative price. Ask the Admin to check the catalog.',
        BillError.duplicateProduct =>
          'An item is in the cart twice. Remove one and change the quantity.',
        BillError.negativeDiscount => "The discount can't be negative.",
        BillError.percentOver100 => "A discount can't be more than 100%.",
        BillError.discountExceedsSubtotal =>
          "The discount can't be more than the bill amount.",
        BillError.discountOverCap =>
          maxDiscountPct == null
              ? "The discount is over this store's limit."
              : "The discount is over this store's limit of "
                    '$maxDiscountPct%.',
      };

  static String paymentError(PaymentError error) => switch (error) {
    PaymentError.noPayments => 'Add a payment.',
    PaymentError.tooManyPayments =>
      'Use at most ${BillCalculator.maxPayments} payments.',
    PaymentError.nonPositiveAmount => 'Enter an amount for every payment.',
    PaymentError.sumMismatch => "Payments don't add up to the bill total.",
    PaymentError.tenderedWithoutCash =>
      'Cash tendered needs a Cash payment. Clear it or add Cash.',
    PaymentError.tenderedTooLow =>
      'Cash tendered is less than the Cash payment.',
  };

  static String failure(DataFailure failure) => switch (failure.reason) {
    FailureReason.invalidCredentials => 'Wrong email or password.',
    FailureReason.userDisabled =>
      'This login has been disabled. Contact the Admin.',
    FailureReason.noProfile =>
      "This login isn't set up for a store yet. Contact the Admin.",
    FailureReason.notPermitted => "You don't have permission to do this.",
    FailureReason.deviceNotRegistered =>
      "This device isn't registered yet. Register it before billing.",
    FailureReason.billingBlocked =>
      'Billing is paused until this device syncs. Connect to the internet, '
          'or ask the Admin for the override PIN.',
    FailureReason.offline => 'This needs an internet connection.',
    FailureReason.notFound => "That record couldn't be found.",
    FailureReason.ruleViolation =>
      "This isn't allowed by the store rules."
          '${failure.detail.isEmpty ? '' : ' (${failure.detail})'}',
    FailureReason.unknown => 'Something went wrong. Please try again.',
  };

  /// Why Cancel is unavailable (D-009, D-025).
  static String cancelBlocker(CancelBlocker blocker) => switch (blocker) {
    CancelBlocker.notCompleted => 'This bill is already cancelled.',
    CancelBlocker.differentDay =>
      'Bills can be cancelled only on the day they were made. Use a return '
          'instead.',
    CancelBlocker.hasReturns =>
      "This bill has returns, so it can't be cancelled. The remaining items "
          'can still be returned.',
  };

  static String returnError(ReturnError error) => switch (error) {
    ReturnError.billNotCompleted =>
      "This bill is cancelled, so it can't take a return.",
    ReturnError.emptyReturn => 'Choose at least one item to return.',
    ReturnError.nonPositiveQty => 'Return quantities must be 1 or more.',
    ReturnError.productNotOnBill => "An item to return isn't on this bill.",
    ReturnError.exceedsReturnable =>
      'That is more than is left to return on this bill. It may have changed; '
          'go back and open it again.',
  };

  static String refundError(RefundError error) => switch (error) {
    RefundError.noRefunds => 'Add a refund.',
    RefundError.tooManyRefunds => 'Use at most ${Limits.maxRefunds} refunds.',
    RefundError.nonPositiveAmount => 'Enter an amount for every refund.',
    RefundError.sumMismatch => "Refunds don't add up to the refund total.",
  };

  static String paymentMode(PaymentMode mode) => switch (mode) {
    PaymentMode.cash => 'Cash',
    PaymentMode.upi => 'UPI',
    PaymentMode.card => 'Card',
    PaymentMode.wallet => 'Wallet',
    PaymentMode.other => 'Other',
  };
}
