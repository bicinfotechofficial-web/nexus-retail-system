import 'package:nexus_core/nexus_core.dart';

/// This install's device registration (03-SYNC §3, D-004).
abstract interface class DeviceService {
  /// This install's device code, e.g. `D01`, or null before registration.
  String? get deviceId;

  /// The location this install registered at, or null before registration.
  /// A code is only valid at its own location: when the signed-in user's
  /// location differs, the app must register again there (D-033).
  String? get locationId;

  /// Registers this install at [locationId] in a transaction on
  /// `nextDeviceNo`. Online only; throws `DataFailure(offline)` otherwise.
  /// Every install gets a new code, even a reinstall on the same phone.
  Future<Device> register({required String locationId, required String label});

  Stream<List<Device>> watchDevices(String locationId);

  /// Admin only (`location.manage`).
  Future<void> retire({required String locationId, required String deviceId});
}
