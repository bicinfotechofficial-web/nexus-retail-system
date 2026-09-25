import '../enums.dart';
import '../map_reader.dart';
import '../money.dart';

/// `expenses/{expenseId}`.
final class Expense {
  const Expense({
    required this.id,
    required this.locationId,
    required this.category,
    required this.amount,
    required this.date,
    required this.note,
    required this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Expense.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'expense $id');
    return Expense(
      id: id,
      locationId: r.string('locationId'),
      category: r.enumValue('category', ExpenseCategory.fromWire),
      amount: Money(r.integer('amount')),
      date: r.string('date'),
      note: r.string('note'),
      createdBy: r.string('createdBy'),
      createdAt: r.dateTimeOrNull('createdAt'),
      updatedAt: r.dateTimeOrNull('updatedAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'createdAt', 'updatedAt'};

  final String id;
  final String locationId;
  final ExpenseCategory category;
  final Money amount;

  /// `YYYY-MM-DD`.
  final String date;
  final String note;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
    'locationId': locationId,
    'category': category.wire,
    'amount': amount.paise,
    'date': date,
    'note': note,
    'createdBy': createdBy,
  };
}

/// `auditLog/{auditId}`. Create-only, written in the same batch as the
/// change it records (D-019).
final class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.entityPath,
    required this.by,
    required this.clientAt,
    this.locationId,
    this.before,
    this.after,
    this.reason,
    this.deviceId,
    this.at,
  });

  factory AuditEntry.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'audit $id');
    return AuditEntry(
      id: id,
      action: r.enumValue('action', AuditAction.fromWire),
      entityPath: r.string('entityPath'),
      locationId: r.stringOrNull('locationId'),
      before: r.mapOrNull('before'),
      after: r.mapOrNull('after'),
      reason: r.stringOrNull('reason'),
      by: r.string('by'),
      deviceId: r.stringOrNull('deviceId'),
      at: r.dateTimeOrNull('at'),
      clientAt: r.dateTime('clientAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'at'};

  final String id;
  final AuditAction action;
  final String entityPath;
  final String? locationId;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
  final String? reason;
  final String by;
  final String? deviceId;
  final DateTime? at;
  final DateTime clientAt;

  Map<String, Object?> toMap() => {
    'action': action.wire,
    'entityPath': entityPath,
    'locationId': locationId,
    'before': before,
    'after': after,
    'reason': reason,
    'by': by,
    'deviceId': deviceId,
    'clientAt': clientAt,
  };
}
