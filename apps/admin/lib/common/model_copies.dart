import 'package:nexus_core/nexus_core.dart';

/// Copies of the core models with some fields changed. The models are
/// immutable and have no `copyWith` of their own.
extension ProductCopy on Product {
  Product copyWith({
    String? name,
    String? category,
    String? scope,
    ProductStatus? status,
    int? sortOrder,
    Money? price,
    DateTime? updatedAt,
  }) => Product(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    scope: scope ?? this.scope,
    status: status ?? this.status,
    sortOrder: sortOrder ?? this.sortOrder,
    createdBy: createdBy,
    price: price ?? this.price,
    proposedPrice: proposedPrice,
    unit: unit,
    gstRate: gstRate,
    recipe: recipe,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

extension AppUserCopy on AppUser {
  AppUser copyWith({bool? active}) => AppUser(
    uid: uid,
    name: name,
    email: email,
    roleId: roleId,
    locationId: locationId,
    active: active ?? this.active,
    createdBy: createdBy,
    createdAt: createdAt,
  );
}

extension DeviceCopy on Device {
  Device copyWith({bool? retired}) => Device(
    code: code,
    label: label,
    registeredBy: registeredBy,
    lastBillSeq: lastBillSeq,
    retired: retired ?? this.retired,
    lastMovementSeq: lastMovementSeq,
    lastReturnSeq: lastReturnSeq,
    registeredAt: registeredAt,
    lastSeenAt: lastSeenAt,
  );
}
