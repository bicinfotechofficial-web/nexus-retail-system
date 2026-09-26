import 'dart:convert';

import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';

/// How a field differs between an audit entry's `before` and `after`.
enum DiffKind { added, removed, changed, unchanged }

/// One field of an audit entry, flattened to a dotted path such as
/// `byMode.CASH`.
final class DiffRow {
  const DiffRow({
    required this.path,
    required this.kind,
    this.before,
    this.after,
  });

  final String path;
  final DiffKind kind;

  /// The value before, null when the field was absent (or null).
  final Object? before;
  final Object? after;
}

/// The field-by-field difference of an audit entry, in path order. A null
/// [before] (a create) makes every field added; a null [after] makes
/// every field removed. Nested maps are flattened; lists compare whole.
List<DiffRow> auditDiff(
  Map<String, Object?>? before,
  Map<String, Object?>? after,
) {
  final b = _flatten(before);
  final a = _flatten(after);
  final paths = {...b.keys, ...a.keys}.toList()..sort();
  return [
    for (final p in paths)
      DiffRow(
        path: p,
        before: b[p],
        after: a[p],
        kind: !b.containsKey(p)
            ? DiffKind.added
            : !a.containsKey(p)
            ? DiffKind.removed
            : _equal(b[p], a[p])
            ? DiffKind.unchanged
            : DiffKind.changed,
      ),
  ];
}

Map<String, Object?> _flatten(Map<String, Object?>? map, [String prefix = '']) {
  final out = <String, Object?>{};
  if (map == null) return out;
  for (final e in map.entries) {
    final path = prefix.isEmpty ? e.key : '$prefix.${e.key}';
    final v = e.value;
    if (v is Map && v.isNotEmpty) {
      out.addAll(_flatten(v.cast<String, Object?>(), path));
    } else {
      out[path] = v;
    }
  }
  return out;
}

bool _equal(Object? x, Object? y) {
  if (x is List && y is List) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (!_equal(x[i], y[i])) return false;
    }
    return true;
  }
  if (x is Map && y is Map) {
    if (x.length != y.length) return false;
    return x.keys.every((k) => y.containsKey(k) && _equal(x[k], y[k]));
  }
  return x == y;
}

/// Fields whose integer values are paise (02-DATA-MODEL), shown as money.
const Set<String> moneyFields = {
  'amount',
  'price',
  'proposedPrice',
  'total',
  'subtotal',
  'refundTotal',
  'expenses',
};

/// A diff value for display. Money fields (by the last path segment) are
/// formatted as rupees; `—` means absent or null.
String formatDiffValue(String path, Object? value) {
  if (value == null) return '—';
  final field = path.split('.').last;
  if (value is int && moneyFields.contains(field)) {
    return Money(value).format();
  }
  if (value is DateTime) return formatInstantIst(value);
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  try {
    return jsonEncode(value);
  } on Object {
    return '$value';
  }
}

String auditActionLabel(AuditAction a) => switch (a) {
  AuditAction.stockAdjust => 'Stock adjust',
  AuditAction.wastage => 'Wastage',
  AuditAction.billCancel => 'Bill cancelled',
  AuditAction.returned => 'Return',
  AuditAction.expenseCreate => 'Expense added',
  AuditAction.expenseUpdate => 'Expense edited',
  AuditAction.priceChange => 'Price change',
  AuditAction.productApprove => 'Product approved',
  AuditAction.userCreate => 'User created',
  AuditAction.userDisable => 'User disabled',
  AuditAction.offlineOverride => 'Offline override',
  AuditAction.thresholdChange => 'Threshold change',
  AuditAction.locationUpdate => 'Location update',
};
