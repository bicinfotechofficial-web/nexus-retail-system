// The one seam between the device scenarios and the backend's Firestore
// implementations. Every scenario gets its devices from `openDevice` below
// and nowhere else. A device is `NexusTestDevice` from
// `package:nexus_data/testing.dart`: the full `NexusBackend` on a named app
// pointed at the emulators, with the per-device hooks the scenarios need
// (goOffline / goOnline, restart, reapplyLastPlan, dispose).

import 'package:firebase_core/firebase_core.dart';
import 'package:nexus_data/testing.dart';

import 'emulator.dart';

/// The `skip:` value of every scenario in `integration_test/`. The real
/// implementations are wired in, so nothing is skipped.
const String? backendSkip = null;

/// One simulated POS install (see `NexusTestDevice`).
typedef TestDevice = NexusTestDevice;

/// Opens a device on [app] against the emulator in [target]. With
/// [freshInstall] (the default) it starts as a new install, signed out and
/// unregistered.
Future<TestDevice> openDevice(
  FirebaseApp app, {
  required EmulatorTarget target,
  bool freshInstall = true,
}) => NexusTestDevice.open(
  app,
  target: EmulatorHost(
    host: target.host,
    firestorePort: target.firestorePort,
    authPort: target.authPort,
  ),
  freshInstall: freshInstall,
);
