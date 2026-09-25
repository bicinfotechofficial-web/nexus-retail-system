import '../enums.dart';
import '../map_reader.dart';

/// `roles/{roleId}`. Written only by the seed script.
final class Role {
  const Role({
    required this.id,
    required this.name,
    required this.permissions,
    required this.allLocations,
  });

  factory Role.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'role $id');
    return Role(
      id: id,
      name: r.string('name'),
      permissions: r.stringList('permissions'),
      allLocations: r.booleanOr('allLocations', false),
    );
  }

  final String id;
  final String name;
  final List<String> permissions;

  /// True means not scoped to one location (Admin).
  final bool allLocations;

  bool can(String permission) => permissions.contains(permission);

  Map<String, Object?> toMap() => {
    'name': name,
    'permissions': permissions,
    'allLocations': allLocations,
  };
}

/// `users/{uid}`.
final class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.roleId,
    required this.locationId,
    required this.active,
    required this.createdBy,
    this.createdAt,
  });

  factory AppUser.fromMap(String uid, Map<String, Object?> map) {
    final r = MapReader(map, 'user $uid');
    return AppUser(
      uid: uid,
      name: r.string('name'),
      email: r.string('email'),
      roleId: r.string('roleId'),
      locationId: r.stringOrNull('locationId'),
      active: r.boolean('active'),
      createdBy: r.string('createdBy'),
      createdAt: r.dateTimeOrNull('createdAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'createdAt'};

  final String uid;
  final String name;
  final String email;
  final String roleId;

  /// Null only when the role has `allLocations`.
  final String? locationId;

  /// False means every operation is denied (D-018).
  final bool active;
  final String createdBy;
  final DateTime? createdAt;

  Map<String, Object?> toMap() => {
    'name': name,
    'email': email,
    'roleId': roleId,
    'locationId': locationId,
    'active': active,
    'createdBy': createdBy,
  };
}

/// `locations/{loc}`.
final class Location {
  const Location({
    required this.code,
    required this.name,
    required this.address,
    required this.phone,
    required this.overridePinHash,
    required this.receiptFooter,
    required this.nextDeviceNo,
    required this.active,
    this.gstin,
    this.offlineLimitHours = defaultOfflineLimitHours,
    this.overrideExtensionHours = defaultOverrideExtensionHours,
    this.maxDiscountPct,
  });

  factory Location.fromMap(String code, Map<String, Object?> map) {
    final r = MapReader(map, 'location $code');
    return Location(
      code: r.string('code'),
      name: r.string('name'),
      address: r.string('address'),
      phone: r.string('phone'),
      gstin: r.stringOrNull('gstin'),
      offlineLimitHours: r.integerOr(
        'offlineLimitHours',
        defaultOfflineLimitHours,
      ),
      overridePinHash: r.string('overridePinHash'),
      overrideExtensionHours: r.integerOr(
        'overrideExtensionHours',
        defaultOverrideExtensionHours,
      ),
      maxDiscountPct: r.integerOrNull('maxDiscountPct'),
      receiptFooter: r.string('receiptFooter'),
      nextDeviceNo: r.integer('nextDeviceNo'),
      active: r.boolean('active'),
    );
  }

  static const int defaultOfflineLimitHours = 5;
  static const int defaultOverrideExtensionHours = 2;

  final String code;
  final String name;
  final String address;
  final String phone;
  final String? gstin;
  final int offlineLimitHours;

  /// PBKDF2-SHA256, 100k iterations, `salt$hash` in base64.
  final String overridePinHash;
  final int overrideExtensionHours;

  /// Null means no cap (D-011).
  final int? maxDiscountPct;
  final String receiptFooter;
  final int nextDeviceNo;
  final bool active;

  Map<String, Object?> toMap() => {
    'code': code,
    'name': name,
    'address': address,
    'phone': phone,
    'gstin': gstin,
    'offlineLimitHours': offlineLimitHours,
    'overridePinHash': overridePinHash,
    'overrideExtensionHours': overrideExtensionHours,
    'maxDiscountPct': maxDiscountPct,
    'receiptFooter': receiptFooter,
    'nextDeviceNo': nextDeviceNo,
    'active': active,
  };
}

/// `locations/{loc}/devices/{deviceId}`.
final class Device {
  const Device({
    required this.code,
    required this.label,
    required this.registeredBy,
    required this.lastBillSeq,
    required this.retired,
    this.registeredAt,
    this.lastSeenAt,
  });

  factory Device.fromMap(String code, Map<String, Object?> map) {
    final r = MapReader(map, 'device $code');
    return Device(
      code: r.string('code'),
      label: r.string('label'),
      registeredBy: r.string('registeredBy'),
      registeredAt: r.dateTimeOrNull('registeredAt'),
      lastSeenAt: r.dateTimeOrNull('lastSeenAt'),
      lastBillSeq: r.integerOr('lastBillSeq', 0),
      retired: r.booleanOr('retired', false),
    );
  }

  static const Set<String> serverTimestampFields = {
    'registeredAt',
    'lastSeenAt',
  };

  final String code;
  final String label;
  final String registeredBy;
  final DateTime? registeredAt;
  final DateTime? lastSeenAt;

  /// Recovers the local bill counter after data loss (03-SYNC §3.4).
  final int lastBillSeq;
  final bool retired;

  Map<String, Object?> toMap() => {
    'code': code,
    'label': label,
    'registeredBy': registeredBy,
    'lastBillSeq': lastBillSeq,
    'retired': retired,
  };
}

/// `rawMaterials/{materialId}`.
final class RawMaterial {
  const RawMaterial({
    required this.id,
    required this.name,
    required this.unit,
    required this.active,
    required this.createdBy,
  });

  factory RawMaterial.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'rawMaterial $id');
    return RawMaterial(
      id: id,
      name: r.string('name'),
      unit: r.enumValue('unit', StockUnit.fromWire),
      active: r.boolean('active'),
      createdBy: r.string('createdBy'),
    );
  }

  final String id;
  final String name;
  final StockUnit unit;
  final bool active;
  final String createdBy;

  Map<String, Object?> toMap() => {
    'name': name,
    'unit': unit.wire,
    'active': active,
    'createdBy': createdBy,
  };
}
