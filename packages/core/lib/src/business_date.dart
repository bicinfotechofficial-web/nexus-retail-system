/// The business day in IST (`Asia/Kolkata`, UTC+05:30, no DST), stored as
/// `YYYY-MM-DD` (D-022). Monthly summaries use `YYYY-MM`.
abstract final class BusinessDate {
  static const Duration istOffset = Duration(hours: 5, minutes: 30);
  static final RegExp _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _month = RegExp(r'^(\d{4})-(\d{2})$');

  /// The IST calendar date of an instant, e.g. 2026-09-25T20:00Z →
  /// `2026-09-26`. Works the same whatever the device's own time zone is.
  static String of(DateTime instant) {
    final ist = instant.toUtc().add(istOffset);
    return '${_pad(ist.year, 4)}-${_pad(ist.month, 2)}-${_pad(ist.day, 2)}';
  }

  /// `2026-09-26` → `2026-09`.
  static String monthOf(String businessDate) {
    _check(businessDate);
    return businessDate.substring(0, 7);
  }

  /// `2026-09-26` → `2026`.
  static String yearOf(String businessDate) {
    _check(businessDate);
    return businessDate.substring(0, 4);
  }

  /// True for a real calendar date in `YYYY-MM-DD` form.
  static bool isValid(String s) {
    final m = _date.firstMatch(s);
    if (m == null) return false;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final dt = DateTime.utc(y, mo, d);
    return dt.year == y && dt.month == mo && dt.day == d;
  }

  /// True for `YYYY-MM` with a month from 01 to 12.
  static bool isValidMonth(String s) {
    final m = _month.firstMatch(s);
    if (m == null) return false;
    final mo = int.parse(m.group(2)!);
    return mo >= 1 && mo <= 12;
  }

  /// The IST midnight that starts [businessDate], as a UTC instant.
  static DateTime startOf(String businessDate) {
    _check(businessDate);
    final p = businessDate.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]).subtract(istOffset);
  }

  /// The date [days] after [businessDate] (negative for earlier).
  static String addDays(String businessDate, int days) {
    _check(businessDate);
    final p = businessDate.split('-').map(int.parse).toList();
    return of(DateTime.utc(p[0], p[1], p[2] + days).subtract(istOffset));
  }

  static void _check(String s) {
    if (!isValid(s)) throw FormatException('Not a YYYY-MM-DD date', s);
  }

  static String _pad(int v, int w) => v.toString().padLeft(w, '0');
}
