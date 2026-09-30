import 'package:nexus_core/nexus_core.dart';

import 'write_plan.dart';

/// Writes of the sync service and the offline guard (03-SYNC §6–7).
abstract final class OfflinePlans {
  /// `lastSeenAt` on this device's doc, set by the server
  /// (04-PERMISSIONS #4 allows it for any active user at the location).
  static WritePlan lastSeen({
    required String locationId,
    required String deviceId,
  }) =>
      (PlanBuilder()..update(FirestorePaths.device(locationId, deviceId), {
            'lastSeenAt': serverTimestamp,
          }))
          .build();
}
