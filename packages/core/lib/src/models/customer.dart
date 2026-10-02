import '../map_reader.dart';
import '../money.dart';
import 'sales.dart';

/// `locations/{loc}/customers/{customerId}` (D-037). Written in the batch
/// of each bill: created on the first bill, then only incremented.
final class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.billCount,
    required this.totalSpend,
    required this.lastWriteRef,
    required this.createdBy,
    this.whatsapp,
    this.firstBillAt,
    this.lastBillAt,
  });

  factory Customer.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'customer $id');
    return Customer(
      id: id,
      name: r.string('name'),
      phone: r.string('phone'),
      whatsapp: r.stringOrNull('whatsapp'),
      firstBillAt: r.dateTimeOrNull('firstBillAt'),
      lastBillAt: r.dateTimeOrNull('lastBillAt'),
      billCount: r.integer('billCount'),
      totalSpend: Money(r.integer('totalSpend')),
      lastWriteRef: r.string('lastWriteRef'),
      createdBy: r.string('createdBy'),
    );
  }

  /// A customer's first bill: the document the batch creates.
  factory Customer.first({
    required BillCustomer customer,
    required Money total,
    required String billId,
    required String createdBy,
  }) => Customer(
    id: customer.id,
    name: customer.name,
    phone: customer.phone,
    whatsapp: customer.whatsapp,
    billCount: 1,
    totalSpend: total,
    lastWriteRef: billId,
    createdBy: createdBy,
  );

  static const Set<String> serverTimestampFields = {
    'firstBillAt',
    'lastBillAt',
  };

  final String id;
  final String name;
  final String phone;

  /// The latest number used for WhatsApp, or null.
  final String? whatsapp;
  final DateTime? firstBillAt;
  final DateTime? lastBillAt;

  /// Bills made, as billed (a cancellation doesn't reverse it).
  final int billCount;
  final Money totalSpend;

  /// The bill that last changed this document.
  final String lastWriteRef;
  final String createdBy;

  Map<String, Object?> toMap() => {
    'name': name,
    'phone': phone,
    'whatsapp': whatsapp,
    'billCount': billCount,
    'totalSpend': totalSpend.paise,
    'lastWriteRef': lastWriteRef,
    'createdBy': createdBy,
  };
}
