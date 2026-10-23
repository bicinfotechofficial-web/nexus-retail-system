import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/order_slip.dart';
import 'package:nexus_pos/app/providers.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_pos/fakes/latest.dart';
import 'package:nexus_printer/nexus_printer.dart';

/// Small in-memory stand-ins for the staff, attendance and pre-order
/// interfaces (D-042, D-043) and the order slip seam, until the backend
/// fields exist. They enforce the same rules the services document, so a
/// test fails when the screen sends something the real service would refuse.

final class FakeStaffRepository implements StaffRepository {
  final Latest<List<StaffMember>> _staff = Latest(const []);

  List<StaffMember> get all => _staff.value;
  set all(List<StaffMember> value) => _staff.value = value;

  List<StaffMember> _sorted(bool Function(StaffMember) keep) =>
      all.where(keep).toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Stream<List<StaffMember>> watchActive(String locationId) =>
      _staff.stream.map((_) => _sorted((s) => s.active));

  @override
  Stream<List<StaffMember>> watchAll(String locationId) =>
      _staff.stream.map((_) => _sorted((_) => true));
}

/// One `AttendanceService.mark` call.
typedef MarkCall = ({String date, List<AttendanceMark> marks});

final class FakeAttendance implements AttendanceService, AttendanceRepository {
  FakeAttendance({
    required this.auth,
    required DateTime Function() now,
    this.deviceId = Seed.deviceId,
  }) : _now = now;

  final FakeAuthService auth;
  final String deviceId;
  final DateTime Function() _now;
  final Latest<List<AttendanceRecord>> _records = Latest(const []);

  /// Every [mark] call, including failed ones.
  final List<MarkCall> markCalls = [];

  /// When set, the next [mark] throws it.
  Exception? failNext;

  /// When set, [mark] waits for it before writing.
  Completer<void>? gate;

  List<AttendanceRecord> get records => _records.value;

  /// Pre-fills a day, as if marked earlier.
  void put(AttendanceRecord record) {
    _records.value = [
      for (final r in records)
        if (r.id != record.id) r,
      record,
    ];
  }

  @override
  Future<void> mark(String businessDate, List<AttendanceMark> marks) async {
    markCalls.add((date: businessDate, marks: List.of(marks)));
    final g = gate;
    if (g != null) await g.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final session = auth.current;
    if (session == null || !session.can(Permission.attendanceMark)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    final today = BusinessDate.of(_now());
    if (!BusinessDate.isValid(businessDate) ||
        businessDate.compareTo(today) > 0 ||
        businessDate.compareTo(
              BusinessDate.addDays(today, -Limits.attendanceBackDays),
            ) <
            0) {
      throw const DataFailure(FailureReason.ruleViolation, 'date window');
    }
    if (marks.map((m) => m.staffId).toSet().length != marks.length) {
      throw const DataFailure(FailureReason.ruleViolation, 'duplicate');
    }
    for (final m in marks) {
      if ((m.note ?? '').length > Limits.attendanceNoteMax) {
        throw const DataFailure(FailureReason.ruleViolation, 'note');
      }
      put(
        AttendanceRecord(
          staffId: m.staffId,
          staffName: m.staffName,
          businessDate: businessDate,
          status: m.status,
          note: m.note,
          markedBy: ServedBy(uid: session.user.uid, name: session.user.name),
          deviceId: deviceId,
        ),
      );
    }
  }

  @override
  Stream<List<AttendanceRecord>> watchDay(String locationId, String date) =>
      _records.stream.map(
        (all) => all.where((r) => r.businessDate == date).toList(),
      );

  @override
  Stream<List<AttendanceRecord>> watchMonth(
    String locationId,
    String monthKey,
  ) => _records.stream.map(
    (all) => all
        .where((r) => BusinessDate.monthOf(r.businessDate) == monthKey)
        .toList(),
  );

  @override
  Stream<List<AttendanceRecord>> watchDayAllLocations(String date) =>
      watchDay('', date);
}

/// One `OrderService.deliver` call.
typedef DeliverCall = ({
  String orderId,
  List<Payment> payments,
  Money? cashTendered,
});

/// One `OrderService.cancel` call.
typedef CancelCall = ({String orderId, String reason, Money refund});

final class FakeOrders implements OrderService, OrderRepository {
  FakeOrders({
    required this.auth,
    required this.bills,
    required DateTime Function() now,
    this.deviceId = Seed.deviceId,
  }) : _now = now;

  final FakeAuthService auth;
  final FakeSalesRepository bills;
  final String deviceId;
  final DateTime Function() _now;
  final Latest<List<PreOrder>> _orders = Latest(const []);
  int _seq = 0;

  // Far from the ordinary bill counter of the fake sales service.
  int _billSeq = 500;

  final List<NewOrder> createCalls = [];
  final List<DeliverCall> deliverCalls = [];
  final List<CancelCall> cancelCalls = [];

  /// When set, the next write throws it.
  Exception? failNext;

  /// When set, every write waits for it first.
  Completer<void>? gate;

  List<PreOrder> get orders => _orders.value;

  PreOrder byId(String id) => orders.firstWhere((o) => o.id == id);

  /// Adds [order] directly, as if taken earlier.
  void put(PreOrder order) {
    _orders.value = [
      for (final o in orders)
        if (o.id != order.id) o,
      order,
    ];
  }

  /// Adds an OPEN order due [dueDate] with plain defaults, and returns it.
  PreOrder add({
    required String dueDate,
    String? dueTime,
    String customer = 'Test Customer',
    String description = 'Black Forest, 1 kg\nWrite "Happy Birthday"',
    int price = 1200,
    int advance = 500,
    PaymentMode? advanceMode,
  }) {
    _seq++;
    final id = Ids.orderId(deviceId, _seq);
    final order = PreOrder(
      id: id,
      orderNo: Ids.orderNo(Seed.locationId, id),
      deviceId: deviceId,
      seq: _seq,
      customer: BillCustomer(
        name: customer,
        phone: '9876543210',
        whatsapp: '9876543210',
      ),
      dueDate: dueDate,
      dueTime: dueTime,
      description: description,
      price: Money.rupees(price),
      advance: Money.rupees(advance),
      advanceMode: advance == 0 ? null : (advanceMode ?? PaymentMode.cash),
      status: OrderStatus.open,
      servedBy: const ServedBy(uid: Seed.userId, name: 'PTB Store Manager'),
      businessDate: BusinessDate.of(_now()),
      clientCreatedAt: _now(),
      createdBy: Seed.userId,
    );
    put(order);
    return order;
  }

  Future<void> _before() async {
    final g = gate;
    if (g != null) await g.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
  }

  (SessionContext, Location) _session() {
    final session = auth.current;
    final location = session?.location;
    if (session == null || location == null) {
      throw const DataFailure(FailureReason.noProfile);
    }
    if (!session.canAt(Permission.orderManage, location.code)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    return (session, location);
  }

  @override
  Future<PreOrder> create(NewOrder order) async {
    createCalls.add(order);
    await _before();
    final (session, location) = _session();
    final problem =
        OrderValidator.dueDateError(order.dueDate, BusinessDate.of(_now())) ??
        OrderValidator.dueTimeError(order.dueTime) ??
        OrderValidator.descriptionError(order.description) ??
        OrderValidator.priceError(order.price) ??
        OrderValidator.advanceError(
          order.advance,
          order.price,
          order.advanceMode,
        );
    if (problem != null) {
      throw DataFailure(FailureReason.ruleViolation, problem);
    }
    _seq++;
    final id = Ids.orderId(deviceId, _seq);
    final created = PreOrder(
      id: id,
      orderNo: Ids.orderNo(location.code, id),
      deviceId: deviceId,
      seq: _seq,
      customer: order.customer,
      dueDate: order.dueDate,
      dueTime: order.dueTime,
      description: OrderValidator.cleanDescription(order.description),
      price: order.price,
      advance: order.advance,
      advanceMode: order.advanceMode,
      status: OrderStatus.open,
      servedBy: ServedBy(uid: session.user.uid, name: session.user.name),
      businessDate: BusinessDate.of(_now()),
      clientCreatedAt: _now(),
      createdBy: session.user.uid,
    );
    put(created);
    return created;
  }

  @override
  Future<Bill> deliver({
    required String orderId,
    required List<Payment> payments,
    Money? cashTendered,
  }) async {
    deliverCalls.add((
      orderId: orderId,
      payments: List.of(payments),
      cashTendered: cashTendered,
    ));
    await _before();
    final (session, location) = _session();
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) throw DataFailure(FailureReason.notFound, orderId);
    if (!order.isOpen) {
      throw const DataFailure(FailureReason.ruleViolation, 'not open');
    }
    if (payments.any((p) => !PaymentMode.selectable.contains(p.mode))) {
      throw const DataFailure(FailureReason.ruleViolation, 'mode');
    }
    final check = BillCalculator.checkPayments(
      order.balance,
      payments,
      cashTendered: cashTendered,
    );
    if (!check.isValid) {
      throw DataFailure(
        FailureReason.ruleViolation,
        check.errors.map((e) => e.name).join(','),
      );
    }
    final totals = BillCalculator.compute([
      CartLine(
        productId: 'CUSTOM-CAKE',
        name: 'Custom cake',
        qty: 1,
        unitPrice: order.price,
      ),
    ]);
    _billSeq++;
    final id = Ids.billId(deviceId, _billSeq);
    final bill = Bill(
      id: id,
      billNo: Ids.billNo(location.code, id),
      deviceId: deviceId,
      seq: _billSeq,
      lines: totals.lines,
      subtotal: totals.subtotal,
      taxableValue: totals.taxableValue,
      roundOff: totals.roundOff,
      total: totals.total,
      payments: [
        if (order.advance.isPositive)
          Payment(mode: PaymentMode.advance, amount: order.advance),
        ...payments,
      ],
      cashTendered: cashTendered,
      status: BillStatus.completed,
      servedBy: ServedBy(uid: session.user.uid, name: session.user.name),
      customer: order.customer,
      orderId: order.id,
      businessDate: BusinessDate.of(_now()),
      clientCreatedAt: _now(),
      createdBy: session.user.uid,
    );
    bills.put(location.code, bill);
    put(_copy(order, status: OrderStatus.delivered, billId: id));
    return bill;
  }

  @override
  Future<PreOrder> cancel({
    required String orderId,
    required String reason,
    required Money refund,
  }) async {
    cancelCalls.add((orderId: orderId, reason: reason, refund: refund));
    await _before();
    final (session, _) = _session();
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) throw DataFailure(FailureReason.notFound, orderId);
    final r = reason.trim();
    if (!order.isOpen ||
        r.isEmpty ||
        r.length > Limits.orderReasonMax ||
        OrderValidator.refundError(refund, order.advance) != null) {
      throw const DataFailure(FailureReason.ruleViolation, 'cancel');
    }
    final cancelled = _copy(
      order,
      status: OrderStatus.cancelled,
      cancel: OrderCancel(
        reason: r,
        by: session.user.uid,
        at: _now(),
        businessDate: BusinessDate.of(_now()),
        refunded: refund,
      ),
    );
    put(cancelled);
    return cancelled;
  }

  PreOrder _copy(
    PreOrder o, {
    required OrderStatus status,
    String? billId,
    OrderCancel? cancel,
  }) => PreOrder(
    id: o.id,
    orderNo: o.orderNo,
    deviceId: o.deviceId,
    seq: o.seq,
    customer: o.customer,
    dueDate: o.dueDate,
    dueTime: o.dueTime,
    description: o.description,
    price: o.price,
    advance: o.advance,
    advanceMode: o.advanceMode,
    status: status,
    billId: billId,
    deliveredAt: status == OrderStatus.delivered ? _now() : null,
    cancel: cancel,
    servedBy: o.servedBy,
    businessDate: o.businessDate,
    clientCreatedAt: o.clientCreatedAt,
    createdBy: o.createdBy,
  );

  @override
  Stream<List<PreOrder>> watchOpen(String locationId) => _orders.stream.map(
    (all) => all.where((o) => o.isOpen).toList()
      ..sort((a, b) {
        final d = a.dueDate.compareTo(b.dueDate);
        if (d != 0) return d;
        return (a.dueTime ?? '99:99').compareTo(b.dueTime ?? '99:99');
      }),
  );

  @override
  Stream<List<PreOrder>> watchClosed(String locationId, {int limit = 50}) =>
      _orders.stream.map(
        (all) =>
            (all.where((o) => !o.isOpen).toList()
                  ..sort((a, b) => b.seq.compareTo(a.seq)))
                .take(limit)
                .toList(),
      );

  @override
  Future<PreOrder?> getOrder(String locationId, String orderId) async =>
      orders.where((o) => o.id == orderId).firstOrNull;

  @override
  Stream<List<PreOrder>> watchAllLocations({
    OrderStatus? status,
    String? dueFrom,
    String? dueTo,
    int limit = 300,
  }) => _orders.stream.map(
    (all) => all.where((o) => status == null || o.status == status).toList(),
  );
}

/// Records the slip actions instead of printing or opening the share sheet.
final class FakeOrderSlipActions implements OrderSlipActions {
  final List<PreOrder> printed = [];
  final List<PreOrder> shared = [];

  /// Results for the next prints, first first; [Printed] when empty.
  final List<PrintResult> nextPrints = [];

  /// When set, the next share throws it.
  Exception? failShare;

  @override
  Future<PrintResult> print(PreOrder order, Location location) async {
    printed.add(order);
    return nextPrints.isEmpty ? const Printed() : nextPrints.removeAt(0);
  }

  @override
  Future<void> shareImage(PreOrder order, Location location) async {
    final failure = failShare;
    if (failure != null) {
      failShare = null;
      throw failure;
    }
    shared.add(order);
  }
}

/// The four fakes with the provider overrides that install them.
final class PreorderFakes {
  PreorderFakes(
    FakeBackend b, {
    DateTime Function()? now,
    StaffRepository? staffRepository,
  }) : staff = FakeStaffRepository(),
       _staffRepository = staffRepository,
       attendance = FakeAttendance(auth: b.auth, now: now ?? _fixedNow),
       orders = FakeOrders(auth: b.auth, bills: b.bills, now: now ?? _fixedNow),
       slips = FakeOrderSlipActions();

  final StaffRepository? _staffRepository;

  static DateTime _fixedNow() => DateTime.utc(2026, 9, 26, 5);

  final FakeStaffRepository staff;
  final FakeAttendance attendance;
  final FakeOrders orders;
  final FakeOrderSlipActions slips;

  List<Override> get overrides => [
    staffRepositoryProvider.overrideWithValue(_staffRepository ?? staff),
    attendanceServiceProvider.overrideWithValue(attendance),
    attendanceRepositoryProvider.overrideWithValue(attendance),
    orderServiceProvider.overrideWithValue(orders),
    orderRepositoryProvider.overrideWithValue(orders),
    orderSlipActionsProvider.overrideWithValue(slips),
  ];
}
