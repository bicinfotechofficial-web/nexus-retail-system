import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_admin/data/providers.dart';

import 'fake_attendance.dart';
import 'fake_orders.dart';
import 'fake_staff.dart';

/// The overrides that stand in for the `NexusBackend` fields `staffRepo`,
/// `staff`, `attendanceRepo` and `orderRepo` until they exist. Pass only the
/// fakes a test needs.
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
