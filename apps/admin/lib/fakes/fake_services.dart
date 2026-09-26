import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../common/model_copies.dart';
import 'fake_repositories.dart';

/// The audit entries the fakes would have written, oldest first. The real
/// data layer writes them in the same batch as the change (D-019).
final class FakeAuditTrail {
  final List<({AuditAction action, String entityId})> entries = [];

  void add(AuditAction action, String entityId) =>
      entries.add((action: action, entityId: entityId));

  List<AuditAction> get actions => [for (final e in entries) e.action];
}

String _uidOf(AuthService auth) => auth.current?.user.uid ?? 'unknown';

/// In-memory [CatalogService] over a [FakeCatalogRepository].
final class FakeCatalogService implements CatalogService {
  FakeCatalogService(this.catalog, this.auth, this.audit, {this.clock});

  final FakeCatalogRepository catalog;
  final AuthService auth;
  final FakeAuditTrail audit;
  final DateTime Function()? clock;
  int _nextId = 1;

  DateTime _now() => (clock ?? DateTime.now)();

  @override
  Future<Product> suggest({
    required String name,
    required String category,
    required Money proposedPrice,
  }) async {
    final loc = auth.current?.user.locationId;
    if (loc == null) throw const DataFailure(FailureReason.notPermitted);
    final p = Product(
      id: 'sug${_nextId++}',
      name: name,
      category: category,
      scope: loc,
      status: ProductStatus.pending,
      sortOrder: 0,
      createdBy: _uidOf(auth),
      proposedPrice: proposedPrice,
      createdAt: _now(),
      updatedAt: _now(),
    );
    catalog.put(p);
    return p;
  }

  @override
  Future<Product> save(Product product) async {
    if (!Ids.isSafeKey(product.id)) {
      throw DataFailure(FailureReason.ruleViolation, 'bad id ${product.id}');
    }
    if (product.status == ProductStatus.active && product.price == null) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'an active product needs a price',
      );
    }
    final before = catalog.byId(product.id);
    if (before != null && before.price != product.price) {
      audit.add(AuditAction.priceChange, product.id);
    }
    final saved = product.copyWith(updatedAt: _now());
    catalog.put(saved);
    return saved;
  }

  @override
  Future<Product> approve({
    required String productId,
    required Money price,
  }) async {
    final p = catalog.byId(productId);
    if (p == null) throw const DataFailure(FailureReason.notFound);
    if (p.status != ProductStatus.pending) {
      throw const DataFailure(FailureReason.ruleViolation, 'not pending');
    }
    if (!price.isPositive) {
      throw const DataFailure(FailureReason.ruleViolation, 'price');
    }
    final approved = p.copyWith(
      status: ProductStatus.active,
      price: price,
      updatedAt: _now(),
    );
    catalog.put(approved);
    audit.add(AuditAction.productApprove, productId);
    return approved;
  }

  @override
  Future<RawMaterial> addRawMaterial({
    required String name,
    required StockUnit unit,
  }) async {
    final slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
    var id = slug.isEmpty ? 'rm' : slug;
    while (catalog.materials.any((m) => m.id == id)) {
      id = '$slug${_nextId++}';
    }
    final m = RawMaterial(
      id: id,
      name: name,
      unit: unit,
      active: true,
      createdBy: _uidOf(auth),
    );
    catalog.addMaterial(m);
    return m;
  }
}

/// In-memory [LocationService]. Like the real one, it never takes
/// `nextDeviceNo` from the caller and never keeps the PIN itself.
final class FakeLocationService implements LocationService {
  FakeLocationService(this.locations, this.audit);

  final FakeLocationRepository locations;
  final FakeAuditTrail audit;

  /// The [Location] passed to the last [save], as the caller built it.
  Location? lastSaved;

  /// A stand-in for the PBKDF2 hash (02-DATA-MODEL): not the PIN itself.
  static String fakeHash(String pin) =>
      'fake\$${pin.length}\$${pin.hashCode.toRadixString(16)}';

  @override
  Future<Location> save(Location location, {String? newPin}) async {
    lastSaved = location;
    if (!Ids.isLocationCode(location.code)) {
      throw DataFailure(FailureReason.ruleViolation, 'code ${location.code}');
    }
    if (newPin != null &&
        (newPin.length < Limits.minOverridePinDigits ||
            !RegExp(r'^\d+$').hasMatch(newPin))) {
      throw const DataFailure(FailureReason.ruleViolation, 'PIN too short');
    }
    final existing = locations.byCode(location.code);
    if (existing == null && newPin == null) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'a new location needs a PIN',
      );
    }
    final stored = Location(
      code: location.code,
      name: location.name,
      address: location.address,
      phone: location.phone,
      gstin: location.gstin,
      offlineLimitHours: location.offlineLimitHours,
      overrideExtensionHours: location.overrideExtensionHours,
      maxDiscountPct: location.maxDiscountPct,
      receiptFooter: location.receiptFooter,
      active: location.active,
      overridePinHash: newPin != null
          ? fakeHash(newPin)
          : existing!.overridePinHash,
      // Only registration writes it (D-004, QA-006).
      nextDeviceNo: existing?.nextDeviceNo ?? 0,
    );
    locations.put(stored);
    audit.add(AuditAction.locationUpdate, location.code);
    return stored;
  }
}

final class FakeUserRepository implements UserRepository {
  FakeUserRepository(List<AppUser> users) : store = Watched(List.of(users));

  final Watched<List<AppUser>> store;

  List<AppUser> get users => store.value;

  @override
  Stream<List<AppUser>> watchUsers({String? locationId}) => store.watch(
    (v) => [
      for (final u in v)
        if (locationId == null || u.locationId == locationId) u,
    ],
  );
}

/// In-memory [UserService]. A created Store Manager can sign in to the
/// fake [FakeAuthService]; the signed-in Admin's session is not touched.
final class FakeUserService implements UserService {
  FakeUserService({
    required this.users,
    required this.auth,
    required this.locations,
    required this.storeManagerRole,
    required this.audit,
  });

  final FakeUserRepository users;
  final FakeAuthService auth;
  final FakeLocationRepository locations;
  final Role storeManagerRole;
  final FakeAuditTrail audit;
  int _nextUid = 1;

  @override
  Future<AppUser> createStoreManager({
    required String name,
    required String email,
    required String password,
    required String locationId,
  }) async {
    final key = email.trim().toLowerCase();
    if (users.users.any((u) => u.email.toLowerCase() == key)) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'email already in use',
      );
    }
    if (password.length < 6) {
      throw const DataFailure(FailureReason.ruleViolation, 'weak password');
    }
    final loc = locations.byCode(locationId);
    if (loc == null) throw const DataFailure(FailureReason.notFound);
    var uid = 'sm-new-${_nextUid++}';
    while (users.users.any((u) => u.uid == uid)) {
      uid = 'sm-new-${_nextUid++}';
    }
    final user = AppUser(
      uid: uid,
      name: name,
      email: key,
      roleId: storeManagerRole.id,
      locationId: locationId,
      active: true,
      createdBy: _uidOf(auth),
    );
    users.store.value = [...users.users, user];
    auth.accounts[key] = (
      password: password,
      session: SessionContext(
        user: user,
        role: storeManagerRole,
        location: loc,
      ),
    );
    audit.add(AuditAction.userCreate, uid);
    return user;
  }

  @override
  Future<void> setActive(String uid, {required bool active}) async {
    final user = users.users.where((u) => u.uid == uid).firstOrNull;
    if (user == null) throw const DataFailure(FailureReason.notFound);
    final updated = user.copyWith(active: active);
    users.store.value = [
      for (final u in users.users) u.uid == uid ? updated : u,
    ];
    final account = auth.accounts[user.email.toLowerCase()];
    if (account != null) {
      final s = account.session;
      auth.accounts[user.email.toLowerCase()] = (
        password: account.password,
        session: SessionContext(
          user: updated,
          role: s.role,
          location: s.location,
        ),
      );
    }
    if (!active) audit.add(AuditAction.userDisable, uid);
  }
}

/// In-memory [DeviceService]. The console never registers devices; it only
/// lists and retires them.
final class FakeDeviceService implements DeviceService {
  FakeDeviceService(Map<String, List<Device>> devices, this.locations)
    : store = Watched({
        for (final e in devices.entries) e.key: List.of(e.value),
      });

  /// Location code → its devices.
  final Watched<Map<String, List<Device>>> store;
  final FakeLocationRepository locations;

  @override
  String? get deviceId => null;

  @override
  Stream<List<Device>> watchDevices(String locationId) => store.watch(
    (v) => [...?v[locationId]]..sort((a, b) => a.code.compareTo(b.code)),
  );

  @override
  Future<void> retire({
    required String locationId,
    required String deviceId,
  }) async {
    final list = store.value[locationId] ?? const <Device>[];
    if (!list.any((d) => d.code == deviceId)) {
      throw const DataFailure(FailureReason.notFound);
    }
    store.value = {
      ...store.value,
      locationId: [
        for (final d in list)
          d.code == deviceId ? d.copyWith(retired: true) : d,
      ],
    };
  }

  @override
  Future<Device> register({
    required String locationId,
    required String label,
  }) async {
    final loc = locations.byCode(locationId);
    if (loc == null) throw const DataFailure(FailureReason.notFound);
    final no = loc.nextDeviceNo + 1;
    locations.put(
      Location(
        code: loc.code,
        name: loc.name,
        address: loc.address,
        phone: loc.phone,
        gstin: loc.gstin,
        offlineLimitHours: loc.offlineLimitHours,
        overrideExtensionHours: loc.overrideExtensionHours,
        maxDiscountPct: loc.maxDiscountPct,
        receiptFooter: loc.receiptFooter,
        active: loc.active,
        overridePinHash: loc.overridePinHash,
        nextDeviceNo: no,
      ),
    );
    final device = Device(
      code: Ids.deviceCode(no),
      label: label,
      registeredBy: 'unknown',
      lastBillSeq: 0,
      retired: false,
      registeredAt: DateTime.now(),
    );
    store.value = {
      ...store.value,
      locationId: [...?store.value[locationId], device],
    };
    return device;
  }
}
