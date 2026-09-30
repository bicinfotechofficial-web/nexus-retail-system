import 'package:nexus_core/nexus_core.dart';

import 'plan_support.dart';
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

  /// OFFLINE_OVERRIDE: one audit doc `{loc}-{dev}-OVR-{millis}`
  /// (`Ids.overrideAuditId`) whose `entityPath` is the device doc, recording
  /// the last sync and the new end of billing. Needs `bill.create` at the
  /// location (04-PERMISSIONS #10).
  static WritePlan override({
    required PlanContext ctx,
    required DateTime until,
    required DateTime? lastSyncAt,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    return (PlanBuilder()..create(
          FirestorePaths.audit(Ids.overrideAuditId(loc, dev, ctx.now)),
          auditDoc(
            action: AuditAction.offlineOverride,
            entityPath: FirestorePaths.device(loc, dev),
            ctx: ctx,
            locationId: loc,
            before: {'lastSyncAt': lastSyncAt},
            after: {'billingAllowedUntil': until},
          ),
        ))
        .build();
  }
}
