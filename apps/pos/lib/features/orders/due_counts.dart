import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';

/// Open pre-orders by how soon they are due (D-043).
final class DueCounts {
  const DueCounts({
    this.overdue = 0,
    this.today = 0,
    this.tomorrow = 0,
    this.later = 0,
  });

  final int overdue;
  final int today;
  final int tomorrow;
  final int later;

  /// Orders that need the manager soon: overdue, today and tomorrow. This is
  /// the number on the Orders entry.
  int get attention => overdue + today + tomorrow;

  /// The banner text, such as "2 orders due today, 1 tomorrow, 1 overdue",
  /// or null when nothing is due soon.
  String? get message {
    if (attention == 0) return null;
    final parts = <String>[];
    var first = true;
    void add(int n, String lead, String rest) {
      if (n == 0) return;
      parts.add(first ? '$n ${n == 1 ? 'order' : 'orders'} $lead' : '$n $rest');
      first = false;
    }

    add(today, 'due today', 'today');
    add(tomorrow, 'due tomorrow', 'tomorrow');
    add(overdue, 'overdue', 'overdue');
    return parts.join(', ');
  }
}

/// Counts [open] orders against the business date [today].
DueCounts countDue(Iterable<PreOrder> open, String today) {
  var overdue = 0;
  var due = 0;
  var tomorrow = 0;
  var later = 0;
  for (final o in open) {
    switch (OrderValidator.dueState(o.dueDate, today)) {
      case OrderDue.overdue:
        overdue++;
      case OrderDue.today:
        due++;
      case OrderDue.tomorrow:
        tomorrow++;
      case OrderDue.later:
        later++;
    }
  }
  return DueCounts(
    overdue: overdue,
    today: due,
    tomorrow: tomorrow,
    later: later,
  );
}

/// The counts of the session's open orders against the business date now
/// (from the app's clock). Empty while loading or when orders can't load.
DueCounts watchDueCounts(WidgetRef ref) {
  final open = ref.watch(openOrdersProvider).value ?? const <PreOrder>[];
  return countDue(open, BusinessDate.of(ref.read(clockProvider)()));
}

/// Whether the banner was dismissed. It lasts until the app restarts or
/// another user signs in, so a new session sees the day's orders again.
class OrderBannerDismissed extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(uidProvider);
    return false;
  }

  void dismiss() => state = true;
}

final orderBannerDismissedProvider =
    NotifierProvider<OrderBannerDismissed, bool>(OrderBannerDismissed.new);

/// `Sat, 26 Sep` for a business date.
String shortDate(String businessDate) {
  final p = businessDate.split('-').map(int.parse).toList();
  return DateFormat('EEE, d MMM').format(DateTime(p[0], p[1], p[2]));
}

/// When an order is due, for cards and the detail: "16:30", "No time set",
/// with the date when it isn't today.
String dueLabel(PreOrder o, String today) {
  final time = o.dueTime ?? 'no time set';
  return OrderValidator.dueState(o.dueDate, today) == OrderDue.today
      ? 'Today, $time'
      : '${shortDate(o.dueDate)}, $time';
}
