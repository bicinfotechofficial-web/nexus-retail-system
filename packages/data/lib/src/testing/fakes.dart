import 'dart:async';

import 'package:nexus_core/nexus_core.dart';

import '../api/attendance.dart';
import '../api/failures.dart';
import '../api/orders.dart';
import '../api/session.dart';
import '../api/staff.dart';
import '../convert/order_ordering.dart';
import '../plans/attendance_plans.dart';
import '../plans/order_plans.dart';
import '../plans/plan_support.dart';
import '../plans/staff_plans.dart';

/// In-memory fakes of the staff, attendance and pre-order contracts, for
/// widget tests and the demo build of the POS and the Admin console (no
/// Firebase). They run the **same pure plan builders** as the real services
/// (`StaffPlans`, `AttendancePlans`, `OrderPlans`), so validation, windows,
/// IDs, payments and the delivery bill are exactly what the real service
/// would produce; only the storing is in memory.
///
/// Wire a repository and its service to each other, and give the services
/// the signed-in session:
///
/// ```dart
/// final staffRepo = FakeStaffRepository();
/// final staff = FakeStaffService(staffRepo, session: () => auth.current);
/// final attendanceRepo = FakeAttendanceRepository();
/// final attendance = FakeAttendanceService(
///   attendanceRepo,
///   session: () => auth.current,
/// );
/// final orderRepo = FakeOrderRepository();
/// final orders = FakeOrderService(orderRepo, session: () => auth.current);
/// ```
///
/// A stream replays its latest value to each new listener, like a Firestore
/// snapshot listener.

/// A value that replays itself to every new listener.
final class _Live<T> {
  _Live(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    _changes.add(v);
  }

  Stream<T> get stream async* {
    yield _value;
    yield* _changes.stream;
  }
}

/// The session with [permission] at its own location, or
/// `DataFailure(notPermitted)`; the location code is returned with it.
(SessionContext, String) _atOwnLocation(
  SessionContext? Function() session,
  String permission,
) {
  final s = session();
  final loc = s?.location?.code ?? s?.user.locationId;
  if (s == null || loc == null || !s.canAt(permission, loc)) {
    throw DataFailure(FailureReason.notPermitted, permission);
  }
  return (s, loc);
}

String _deviceOrThrow(String? Function() deviceId) {
  final d = deviceId();
  if (d == null || !Ids.isDeviceCode(d)) {
    throw const DataFailure(FailureReason.deviceNotRegistered);
  }
  return d;
}

// ---- Staff ------------------------------------------------------------

/// The roster in memory. [seed] adds members directly (for a demo or a
/// test); a [FakeStaffService] writes through [add] and [change].
final class FakeStaffRepository implements StaffRepository {
  final _Live<Map<String, Map<String, StaffMember>>> _byLocation = _Live(
    const {},
  );

  /// Every member of [locationId], active or not, by name.
  List<StaffMember> all(String locationId) =>
      _sorted(_byLocation.value[locationId]?.values ?? const <StaffMember>[]);

  /// Puts [member] on the roster of [locationId] as it is.
  void seed(String locationId, StaffMember member) => add(locationId, member);

  void add(String locationId, StaffMember member) {
    final byLocation = {..._byLocation.value};
    byLocation[locationId] = {
      ...?byLocation[locationId],
      member.id: _at(member, locationId),
    };
    _byLocation.value = byLocation;
  }

  /// Replaces the member [staffId] of [locationId] with what [change] makes
  /// of it. Missing members are `DataFailure(notFound)`.
  void change(
    String locationId,
    String staffId,
    StaffMember Function(StaffMember current) change,
  ) {
    final current = _byLocation.value[locationId]?[staffId];
    if (current == null) {
      throw DataFailure(FailureReason.notFound, 'staff $staffId');
    }
    add(locationId, change(current));
  }

  static StaffMember _at(StaffMember m, String locationId) => StaffMember(
    id: m.id,
    name: m.name,
    role: m.role,
    active: m.active,
    locationId: locationId,
    createdBy: m.createdBy,
    createdAt: m.createdAt,
    updatedBy: m.updatedBy,
    updatedAt: m.updatedAt,
  );

  static List<StaffMember> _sorted(Iterable<StaffMember> list) =>
      list.toList()..sort((a, b) {
        final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return c != 0 ? c : a.id.compareTo(b.id);
      });

  @override
  Stream<List<StaffMember>> watchActive(String locationId) =>
      _byLocation.stream.map(
        (m) => _sorted(
          (m[locationId]?.values ?? const <StaffMember>[]).where(
            (s) => s.active,
          ),
        ),
      );

  @override
  Stream<List<StaffMember>> watchAll(String locationId) => _byLocation.stream
      .map((m) => _sorted(m[locationId]?.values ?? const <StaffMember>[]));
}

/// [StaffService] on a [FakeStaffRepository]. Needs `staff.manage` at the
/// location, like the real one; IDs are `staff-1`, `staff-2`, ...
final class FakeStaffService implements StaffService {
  FakeStaffService(
    this.repo, {
    required SessionContext? Function() session,
    DateTime Function()? now,
  }) : _session = session,
       _now = now ?? DateTime.now;

  final FakeStaffRepository repo;
  final SessionContext? Function() _session;
  final DateTime Function() _now;
  int _seq = 0;

  /// Every [create] call as (locationId, name, role), including failed ones.
  final List<(String, String, String)> createCalls = [];

  /// When set, the next [create] or [update] throws it instead of saving.
  Exception? failNext;

  SessionContext _require(String locationId) {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final s = _session();
    if (s == null || !s.canAt(Permission.staffManage, locationId)) {
      throw DataFailure(
        FailureReason.notPermitted,
        '${Permission.staffManage} at $locationId',
      );
    }
    return s;
  }

  @override
  Future<StaffMember> create({
    required String locationId,
    required String name,
    String role = '',
  }) async {
    createCalls.add((locationId, name, role));
    final s = _require(locationId);
    final planned = StaffPlans.create(
      ctx: PlanContext(uid: s.user.uid, now: _now(), locationId: locationId),
      locationId: locationId,
      staffId: 'staff-${++_seq}',
      name: name,
      role: role,
    );
    repo.add(locationId, planned.value);
    return planned.value;
  }

  @override
  Future<void> update({
    required String locationId,
    required String staffId,
    String? name,
    String? role,
    bool? active,
  }) async {
    final s = _require(locationId);
    final ctx = PlanContext(
      uid: s.user.uid,
      now: _now(),
      locationId: locationId,
    );
    // The same checks as the real plan (a bad value, nothing to change).
    StaffPlans.update(
      ctx: ctx,
      locationId: locationId,
      staffId: staffId,
      name: name,
      role: role,
      active: active,
    );
    repo.change(
      locationId,
      staffId,
      (m) => StaffMember(
        id: m.id,
        name: name == null ? m.name : StaffMember.cleanText(name),
        role: role == null ? m.role : StaffMember.cleanText(role),
        active: active ?? m.active,
        locationId: m.locationId,
        createdBy: m.createdBy,
        createdAt: m.createdAt,
        updatedBy: s.user.uid,
        updatedAt: ctx.now,
      ),
    );
  }
}

// ---- Attendance ----------------------------------------------------------

/// Attendance marks in memory, keyed by location and document ID
/// (`{businessDate}_{staffId}`), so marking again overwrites.
final class FakeAttendanceRepository implements AttendanceRepository {
  final _Live<Map<String, Map<String, AttendanceRecord>>> _byLocation = _Live(
    const {},
  );

  /// Every mark at [locationId], by date then name.
  List<AttendanceRecord> all(String locationId) =>
      _sorted(_byLocation.value[locationId]?.values ?? const []);

  /// Stores [record] at [locationId], replacing the same day's mark of that
  /// person.
  void put(String locationId, AttendanceRecord record) {
    final byLocation = {..._byLocation.value};
    byLocation[locationId] = {
      ...?byLocation[locationId],
      record.id: _at(record, locationId),
    };
    _byLocation.value = byLocation;
  }

  static AttendanceRecord _at(AttendanceRecord r, String locationId) =>
      AttendanceRecord(
        staffId: r.staffId,
        staffName: r.staffName,
        businessDate: r.businessDate,
        status: r.status,
        note: r.note,
        markedBy: r.markedBy,
        deviceId: r.deviceId,
        editedAt: r.editedAt,
        locationId: locationId,
      );

  static List<AttendanceRecord> _sorted(Iterable<AttendanceRecord> list) =>
      list.toList()..sort((a, b) {
        final byDate = a.businessDate.compareTo(b.businessDate);
        if (byDate != 0) return byDate;
        final byName = a.staffName.toLowerCase().compareTo(
          b.staffName.toLowerCase(),
        );
        return byName != 0 ? byName : a.staffId.compareTo(b.staffId);
      });

  @override
  Stream<List<AttendanceRecord>> watchDay(String locationId, String date) =>
      _byLocation.stream.map(
        (m) => _sorted(
          (m[locationId]?.values ?? const <AttendanceRecord>[]).where(
            (r) => r.businessDate == date,
          ),
        ),
      );

  @override
  Stream<List<AttendanceRecord>> watchMonth(
    String locationId,
    String monthKey,
  ) => _byLocation.stream.map(
    (m) => _sorted(
      (m[locationId]?.values ?? const <AttendanceRecord>[]).where(
        (r) => r.businessDate.startsWith('$monthKey-'),
      ),
    ),
  );

  @override
  Stream<List<AttendanceRecord>> watchDayAllLocations(String date) =>
      _byLocation.stream.map(
        (m) => _sorted(
          m.values.expand((l) => l.values).where((r) => r.businessDate == date),
        ),
      );
}

/// [AttendanceService] on a [FakeAttendanceRepository]. Needs
/// `attendance.mark` at the user's location and a device code, and applies
/// the real window (today and `Limits.attendanceBackDays` back), duplicate
/// and note checks through `AttendancePlans`.
final class FakeAttendanceService implements AttendanceService {
  FakeAttendanceService(
    this.repo, {
    required SessionContext? Function() session,
    DateTime Function()? now,
    String? Function()? deviceId,
  }) : _session = session,
       _now = now ?? DateTime.now,
       _deviceId = deviceId ?? (() => 'D01');

  final FakeAttendanceRepository repo;
  final SessionContext? Function() _session;
  final DateTime Function() _now;
  final String? Function() _deviceId;

  /// Every [mark] call as (businessDate, marks), including failed ones.
  final List<(String, List<AttendanceMark>)> markCalls = [];

  /// When set, the next [mark] throws it instead of saving.
  Exception? failNext;

  /// When set, [mark] waits for it before saving.
  Completer<void>? gate;

  @override
  Future<void> mark(String businessDate, List<AttendanceMark> marks) async {
    markCalls.add((businessDate, marks));
    final g = gate;
    if (g != null) await g.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final (s, loc) = _atOwnLocation(_session, Permission.attendanceMark);
    final dev = _deviceOrThrow(_deviceId);
    final at = _now();
    // The real plan checks everything; its documents are not needed here.
    AttendancePlans.mark(
      ctx: PlanContext(
        uid: s.user.uid,
        locationId: loc,
        deviceId: dev,
        now: at,
      ),
      businessDate: businessDate,
      marks: marks,
      markedByName: s.user.name,
    );
    for (final m in marks) {
      final note = m.note?.trim();
      repo.put(
        loc,
        AttendanceRecord(
          staffId: m.staffId,
          staffName: StaffMember.cleanText(m.staffName),
          businessDate: businessDate,
          status: m.status,
          note: note == null || note.isEmpty ? null : note,
          markedBy: ServedBy(uid: s.user.uid, name: s.user.name),
          deviceId: dev,
          editedAt: at,
        ),
      );
    }
  }
}

// ---- Pre-orders -----------------------------------------------------------

/// Pre-orders in memory, keyed by location and order ID.
final class FakeOrderRepository implements OrderRepository {
  final _Live<Map<String, Map<String, PreOrder>>> _byLocation = _Live(const {});

  /// Every order at [locationId], soonest due first.
  List<PreOrder> all(String locationId) =>
      soonestDueFirst(_byLocation.value[locationId]?.values.toList() ?? []);

  /// Stores [order] at [locationId], replacing the same ID.
  void put(String locationId, PreOrder order) {
    final byLocation = {..._byLocation.value};
    byLocation[locationId] = {
      ...?byLocation[locationId],
      order.id: OrderPlans.copyOrder(order, locationId: locationId),
    };
    _byLocation.value = byLocation;
  }

  @override
  Stream<List<PreOrder>> watchOpen(String locationId) => _byLocation.stream.map(
    (m) => soonestDueFirst([
      for (final o in m[locationId]?.values ?? const <PreOrder>[])
        if (o.isOpen) o,
    ]),
  );

  @override
  Stream<List<PreOrder>> watchClosed(String locationId, {int limit = 50}) =>
      _byLocation.stream.map(
        (m) => newestFirst([
          for (final o in m[locationId]?.values ?? const <PreOrder>[])
            if (!o.isOpen) o,
        ]).take(limit).toList(),
      );

  @override
  Future<PreOrder?> getOrder(String locationId, String orderId) async =>
      _byLocation.value[locationId]?[orderId];

  @override
  Stream<List<PreOrder>> watchAllLocations({
    String? locationId,
    OrderStatus? status,
    String? dueFrom,
    String? dueTo,
    int limit = 300,
  }) => _byLocation.stream.map(
    (m) => soonestDueFirst([
      for (final MapEntry(key: loc, value: l) in m.entries)
        if (locationId == null || loc == locationId)
          for (final o in l.values)
            if ((status == null || o.status == status) &&
                (dueFrom == null || o.dueDate.compareTo(dueFrom) >= 0) &&
                (dueTo == null || o.dueDate.compareTo(dueTo) <= 0))
              o,
    ]).take(limit).toList(),
  );
}

/// [OrderService] on a [FakeOrderRepository]: orders numbered
/// `{deviceId}-O{seq}` from its own counter, and the real [OrderPlans] for
/// every check, the advance, the delivery bill and the cancellation.
///
/// [deliver] builds the delivery bill with the real plan and hands it to
/// [onBill], so a fake sales store can record it; bill numbers come from
/// [nextBillSeq] (share the fake sales service's counter to avoid clashes),
/// else from a counter of its own.
final class FakeOrderService implements OrderService {
  FakeOrderService(
    this.repo, {
    required SessionContext? Function() session,
    DateTime Function()? now,
    String? Function()? deviceId,
    int Function()? nextBillSeq,
    this.onBill,
  }) : _session = session,
       _now = now ?? DateTime.now,
       _deviceId = deviceId ?? (() => 'D01'),
       _nextBillSeq = nextBillSeq;

  final FakeOrderRepository repo;
  final SessionContext? Function() _session;
  final DateTime Function() _now;
  final String? Function() _deviceId;
  final int Function()? _nextBillSeq;

  /// Told about each delivery bill, in the batch that marks the order
  /// DELIVERED.
  final void Function(String locationId, Bill bill)? onBill;

  int _seq = 0;
  int _billSeq = 0;

  /// Every [create] call, including failed ones.
  final List<NewOrder> createCalls = [];

  /// Every [deliver] call as (orderId, payments), including failed ones.
  final List<(String, List<Payment>)> deliverCalls = [];

  /// Every [cancel] call as (orderId, reason, refund), including failed ones.
  final List<(String, String, Money)> cancelCalls = [];

  /// When set, the next [create], [deliver] or [cancel] throws it instead of
  /// saving.
  Exception? failNext;

  /// When set, every write waits for it before saving.
  Completer<void>? gate;

  Future<void> _before() async {
    final g = gate;
    if (g != null) await g.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
  }

  PlanContext _ctx(SessionContext s, String loc, String dev) =>
      PlanContext(uid: s.user.uid, locationId: loc, deviceId: dev, now: _now());

  @override
  Future<PreOrder> create(NewOrder order) async {
    createCalls.add(order);
    await _before();
    final (s, loc) = _atOwnLocation(_session, Permission.orderManage);
    final dev = _deviceOrThrow(_deviceId);
    final planned = OrderPlans.create(
      ctx: _ctx(s, loc, dev),
      seq: ++_seq,
      input: order,
      servedByName: s.user.name,
    );
    repo.put(loc, planned.value);
    return planned.value;
  }

  @override
  Future<Bill> deliver({
    required String orderId,
    required List<Payment> payments,
    Money? cashTendered,
  }) async {
    deliverCalls.add((orderId, payments));
    await _before();
    final (s, loc) = _atOwnLocation(_session, Permission.orderManage);
    if (!s.canAt(Permission.billCreate, loc)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    final dev = _deviceOrThrow(_deviceId);
    final order = await _find(loc, orderId);
    final seq = _nextBillSeq?.call() ?? ++_billSeq;
    final planned = OrderPlans.deliver(
      ctx: _ctx(s, loc, dev),
      seq: seq,
      order: order,
      payments: payments,
      cashTendered: cashTendered,
      servedByName: s.user.name,
    );
    final bill = planned.value;
    repo.put(
      loc,
      OrderPlans.copyOrder(
        order,
        status: OrderStatus.delivered,
        billId: bill.id,
        deliveredAt: _now(),
      ),
    );
    onBill?.call(loc, bill);
    return bill;
  }

  @override
  Future<PreOrder> cancel({
    required String orderId,
    required String reason,
    required Money refund,
  }) async {
    cancelCalls.add((orderId, reason, refund));
    await _before();
    final (s, loc) = _atOwnLocation(_session, Permission.orderManage);
    final dev = _deviceOrThrow(_deviceId);
    final order = await _find(loc, orderId);
    final planned = OrderPlans.cancel(
      ctx: _ctx(s, loc, dev),
      order: order,
      reason: reason,
      refund: refund,
    );
    repo.put(loc, planned.value);
    return planned.value;
  }

  Future<PreOrder> _find(String loc, String orderId) async {
    final order = await repo.getOrder(loc, orderId);
    if (order == null) {
      throw DataFailure(FailureReason.notFound, 'order $orderId');
    }
    return order;
  }
}
