import 'package:nexus_core/nexus_core.dart';

/// Soonest due first: by `dueDate`, then `dueTime`, with orders that have no
/// time after those that have, then by ID. Sorts [list] in place and returns
/// it. Shared by the Firestore repository and the in-memory fake, so both
/// order the lists the same way.
List<PreOrder> soonestDueFirst(List<PreOrder> list) => list
  ..sort((a, b) {
    final byDate = a.dueDate.compareTo(b.dueDate);
    if (byDate != 0) return byDate;
    final at = a.dueTime;
    final bt = b.dueTime;
    if (at != bt) {
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
    }
    return a.id.compareTo(b.id);
  });

/// Newest first by the day the order was taken, then by ID. Sorts in place.
List<PreOrder> newestFirst(List<PreOrder> list) => list
  ..sort((a, b) {
    final c = b.clientCreatedAt.compareTo(a.clientCreatedAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
