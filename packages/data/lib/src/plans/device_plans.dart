import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import 'plan_support.dart';
import 'write_plan.dart';

/// Device registration and retirement (03-SYNC §3, D-004).
abstract final class DevicePlans {
  /// The writes of a registration, given the location's current
  /// `nextDeviceNo` as read inside the transaction: `nextDeviceNo` + 1 and
  /// a clean `devices/D{new value}` (04-PERMISSIONS #4). Every call hands
  /// out the next code, so a reinstall never gets an old one.
  ///
  /// Throws `DataFailure(ruleViolation)` past `D99` (`Ids.maxDeviceNo`).
  static PlannedWrite<Device> register({
    required PlanContext ctx,
    required String locationId,
    required int currentNextDeviceNo,
    required String label,
  }) {
    final n = currentNextDeviceNo + 1;
    if (n < 1 || n > Ids.maxDeviceNo) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'no device codes left at $locationId (D${Ids.maxDeviceNo} is the last)',
      );
    }
    final device = Device(
      code: Ids.deviceCode(n),
      label: label.trim(),
      registeredBy: ctx.uid,
      lastBillSeq: 0,
      retired: false,
    );
    final plan =
        (PlanBuilder()
              ..update(FirestorePaths.location(locationId), {'nextDeviceNo': n})
              ..create(FirestorePaths.device(locationId, device.code), {
                ...device.toMap(),
                'registeredAt': serverTimestamp,
              }))
            .build();
    return PlannedWrite(device, plan);
  }

  /// Retires a device (`location.manage`). Its code is never handed out
  /// again (D-004).
  static WritePlan retire({
    required String locationId,
    required String deviceId,
  }) =>
      (PlanBuilder()..update(FirestorePaths.device(locationId, deviceId), {
            'retired': true,
          }))
          .build();
}
