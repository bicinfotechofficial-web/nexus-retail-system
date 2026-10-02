import '../map_reader.dart';
import '../money.dart';
import 'sales.dart';

/// `locations/{loc}/customers/{customerId}` (D-037). Written in the batch
/// of each bill. A device can't know offline whether it exists, so every
/// bill writes it with `set(merge)`: only values that stay the same
/// (`name`, `phone`) or can be incremented or overwritten are stored, which
/// is why there is no `createdBy` or first-bill date.
final class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.billCount,
    required this.totalSpend,
    required this.lastWriteRef,
    this.whatsapp,
    this.lastBillAt,
  });

  factory Customer.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'customer $id');
    return Customer(
      id: id,
      name: r.string('name'),
      phone: r.string('phone'),
      whatsapp: r.stringOrNull('whatsapp'),
      lastBillAt: r.dateTimeOrNull('lastBillAt'),
      billCount: r.integer('billCount'),
      totalSpend: Money(r.integer('totalSpend')),
      lastWriteRef: r.string('lastWriteRef'),
    );
  }

  /// A customer's first bill: the document the batch creates.
  factory Customer.first({
    required BillCustomer customer,
    required Money total,
    required String billId,
  }) => Customer(
    id: customer.id,
    name: customer.name,
    phone: customer.phone,
    whatsapp: customer.whatsapp,
    billCount: 1,
    totalSpend: total,
    lastWriteRef: billId,
  );

  static const Set<String> serverTimestampFields = {'lastBillAt'};

  final String id;
  final String name;
  final String phone;

  /// The latest number used for WhatsApp, or null.
  final String? whatsapp;
  final DateTime? lastBillAt;

  /// Bills made, as billed (a cancellation doesn't reverse it).
  final int billCount;
  final Money totalSpend;

  /// The bill that last changed this document.
  final String lastWriteRef;

  Map<String, Object?> toMap() => {
    'name': name,
    'phone': phone,
    'whatsapp': whatsapp,
    'billCount': billCount,
    'totalSpend': totalSpend.paise,
    'lastWriteRef': lastWriteRef,
  };
}
