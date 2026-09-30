/// `--dart-define=USE_EMULATOR=true` points Firestore and Auth at the
/// Firebase emulators instead of the real project. Debug and profile builds
/// only: a release build refuses to start with it.
const bool useEmulatorDefine = bool.fromEnvironment('USE_EMULATOR');

/// `--dart-define=EMULATOR_HOST=192.168.1.20` for a physical phone on the
/// PC's Wi-Fi. Empty means [EmulatorTarget.androidHost].
const String emulatorHostDefine = String.fromEnvironment('EMULATOR_HOST');

/// Where the Firebase emulators are, as seen from the phone.
final class EmulatorTarget {
  const EmulatorTarget({
    required this.host,
    this.firestorePort = firestoreEmulatorPort,
    this.authPort = authEmulatorPort,
  });

  /// The host PC, from inside an Android emulator.
  static const String androidHost = '10.0.2.2';

  /// The ports in `firebase/firebase.json`.
  static const int firestoreEmulatorPort = 8080;
  static const int authEmulatorPort = 9099;

  /// The emulator's demo project (docs/SETUP-FIREBASE.md §2). A `demo-`
  /// project exists only in the emulator, so no request can reach
  /// production data.
  static const String projectId = 'demo-caramel-cottage';

  final String host;
  final int firestorePort;
  final int authPort;

  @override
  String toString() => '$host (Firestore $firestorePort, Auth $authPort)';
}

/// USE_EMULATOR in a release build.
final class EmulatorInReleaseError implements Exception {
  const EmulatorInReleaseError();

  @override
  String toString() =>
      'This build was made with USE_EMULATOR, which only works in debug '
      'builds. Build the release APK without it.';
}

/// The emulator to use, or null for the real project.
///
/// [releaseBuild] is `kReleaseMode`; passed in so tests can check both.
/// Throws [EmulatorInReleaseError] when [requested] in a release build, so
/// a release APK can never talk to an emulator (or be mistaken for one that
/// does). [host] is `EMULATOR_HOST`; empty means [EmulatorTarget.androidHost].
EmulatorTarget? resolveEmulator({
  required bool requested,
  required bool releaseBuild,
  String host = '',
}) {
  if (!requested) return null;
  if (releaseBuild) throw const EmulatorInReleaseError();
  final h = host.trim();
  return EmulatorTarget(host: h.isEmpty ? EmulatorTarget.androidHost : h);
}
