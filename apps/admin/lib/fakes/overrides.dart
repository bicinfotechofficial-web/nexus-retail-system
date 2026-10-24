import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_core/nexus_core.dart';
import '../data/providers.dart';

import 'fake_attendance.dart';
import 'fake_orders.dart';
import 'fake_staff.dart';

/// The overrides that install the staff, attendance and order fakes. Pass
/// only the fakes a test needs; `FAKE_DATA=true` uses [demoInterfaceOverrides].
List<Override> newInterfaceOverrides({
  FakeStaffStore? staff,
  FakeAttendanceRepository? attendance,
  FakeOrderRepository? orders,
}) => [
  if (staff != null) ...[
    staffRepositoryProvider.overrideWithValue(staff),
    staffServiceProvider.overrideWithValue(staff),
  ],
  if (attendance != null)
    attendanceRepositoryProvider.overrideWithValue(attendance),
  if (orders != null) orderRepositoryProvider.overrideWithValue(orders),
];

/// Staff, attendance and pre-orders at PTB and MNJ around [today], so the
/// Staff, Attendance and Orders pages have something to show with
///  (D-042, D-043). PTB has marked today; MNJ has not.
List<Override> demoInterfaceOverrides(String today) {
  String day(int offset) => BusinessDate.addDays(today, offset);
  final roster = {
    'PTB': const [
      StaffMember(id: 'ptb-1', name: 'Staff One', role: 'Baker', active: true),
      StaffMember(
        id: 'ptb-2',
        name: 'Staff Two',
        role: 'Counter',
        active: true,
      ),
      StaffMember(
        id: 'ptb-3',
        name: 'Staff Three',
        role: 'Helper',
        active: true,
      ),
      StaffMember(
        id: 'ptb-4',
        name: 'Staff Four',
        role: 'Helper',
        active: false,
      ),
    ],
    'MNJ': const [
      StaffMember(id: 'mnj-1', name: 'Staff Five', role: 'Baker', active: true),
      StaffMember(
        id: 'mnj-2',
        name: 'Staff Six',
        role: 'Counter',
        active: true,
      ),
    ],
  };
  const cycle = [
    AttendanceStatus.present,
    AttendanceStatus.present,
    AttendanceStatus.present,
    AttendanceStatus.halfDay,
    AttendanceStatus.present,
    AttendanceStatus.absent,
  ];
  final marks = [
    for (final MapEntry(key: loc, value: staff) in roster.entries)
      for (var d = loc == 'PTB' ? 0 : -1; d >= -20; d--)
        for (final (i, s) in staff.indexed)
          if (s.active)
            mark(loc, day(d), s.id, s.name, cycle[(i - d) % cycle.length]),
  ];
  final orders = [
    order(
      'PTB',
      'D01-O000001',
      dueDate: day(-1),
      dueTime: '18:00',
      takenOn: day(-4),
    ),
    order(
      'PTB',
      'D01-O000002',
      dueDate: today,
      dueTime: '16:30',
      takenOn: day(-3),
    ),
    order(
      'PTB',
      'D01-O000003',
      dueDate: day(1),
      description: 'Red velvet, 2 kg, two layers',
      price: 2400,
      advance: 1000,
      takenOn: day(-2),
    ),
    order(
      'PTB',
      'D01-O000004',
      dueDate: day(-2),
      status: OrderStatus.delivered,
      takenOn: day(-5),
    ),
    order(
      'MNJ',
      'D02-O000001',
      dueDate: day(3),
      description: 'Pineapple, 500 g, no message',
      price: 550,
      advance: 0,
      takenOn: day(-1),
    ),
    order(
      'MNJ',
      'D02-O000002',
      dueDate: day(-1),
      status: OrderStatus.cancelled,
      cancel: cancelled(
        reason: 'Customer changed plans',
        refunded: 300,
        on: day(-3),
      ),
      takenOn: day(-6),
    ),
  ];
  return newInterfaceOverrides(
    staff: FakeStaffStore(roster),
    attendance: FakeAttendanceRepository(marks),
    orders: FakeOrderRepository(orders),
  );
}
