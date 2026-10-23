import 'business_date.dart';
import 'enums.dart';
import 'limits.dart';
import 'money.dart';

/// How soon a pre-order is due, for the lists and the banner (D-043).
enum OrderDue { overdue, today, tomorrow, later }

/// Validation and date helpers for pre-orders (D-043). Pure, so the POS
/// form, the services and the tests agree.
abstract final class OrderValidator {
  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  /// Trims and collapses runs of spaces, keeping line breaks.
  static String cleanDescription(String raw) => raw
      .split('\n')
      .map((l) => l.trim().replaceAll(RegExp(r'[ \t]+'), ' '))
      .join('\n')
      .trim();

  static String? descriptionError(String raw) {
    final d = cleanDescription(raw);
    if (d.isEmpty) return 'Describe the cake.';
    if (d.length > Limits.orderDescriptionMax) {
      return 'At most ${Limits.orderDescriptionMax} characters.';
    }
    return null;
  }

  /// [dueDate] must be a real business date and not before [today].
  static String? dueDateError(String dueDate, String today) {
    if (!BusinessDate.isValid(dueDate)) return 'Pick the delivery date.';
    if (dueDate.compareTo(today) < 0) return 'That date has passed.';
    return null;
  }

  /// `HH:mm` or null (no time agreed).
  static String? dueTimeError(String? time) {
    if (time == null) return null;
    return _time.hasMatch(time) ? null : 'Use a time like 16:30.';
  }

  /// A price: more than zero, in whole rupees.
  static String? priceError(Money price) {
    if (!price.isPositive) return 'Enter the price.';
    if (price.paise % 100 != 0) return 'Use whole rupees.';
    return null;
  }

  /// An advance: 0 up to the [price], in whole rupees, with a payment mode
  /// the counter offers when it is more than zero.
  static String? advanceError(Money advance, Money price, PaymentMode? mode) {
    if (advance.isNegative) return 'The advance cannot be negative.';
    if (advance.paise % 100 != 0) return 'Use whole rupees.';
    if (advance > price) return 'The advance is more than the price.';
    if (advance.isPositive &&
        (mode == null || !PaymentMode.selectable.contains(mode))) {
      return 'Choose how the advance was paid.';
    }
    if (advance.isZero && mode != null) return 'No mode without an advance.';
    return null;
  }

  /// How much of the [advance] is handed back on a cancellation: 0 up to the
  /// advance, in whole rupees.
  static String? refundError(Money refunded, Money advance) {
    if (refunded.isNegative) return 'The refund cannot be negative.';
    if (refunded.paise % 100 != 0) return 'Use whole rupees.';
    if (refunded > advance) return 'More than the advance.';
    return null;
  }

  /// [dueDate] against [today], both business dates.
  static OrderDue dueState(String dueDate, String today) {
    final c = dueDate.compareTo(today);
    if (c < 0) return OrderDue.overdue;
    if (c == 0) return OrderDue.today;
    final tomorrow = BusinessDate.addDays(today, 1);
    return dueDate == tomorrow ? OrderDue.tomorrow : OrderDue.later;
  }
}
