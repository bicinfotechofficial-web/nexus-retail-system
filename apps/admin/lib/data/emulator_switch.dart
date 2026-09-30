/// `--dart-define=USE_EMULATOR=true` points Firestore and Auth at the
/// Firebase emulators instead of the real project. Debug builds only: a
/// release build refuses to start with it.
const bool useEmulatorDefine = bool.fromEnvironment('USE_EMULATOR');

/// `--dart-define=EMULATOR_HOST=...` when the emulators aren't on this
/// machine. Empty means [EmulatorTarget.webHost].
const String emulatorHostDefine = String.fromEnvironment('EMULATOR_HOST');

/// Where the Firebase emulators are, as seen from the browser.
final class EmulatorTarget {
  const EmulatorTarget({
    required this.host,
    this.firestorePort = firestoreEmulatorPort,
    this.authPort = authEmulatorPort,
  });

  /// The browser runs on the PC that runs the emulators.
  static const String webHost = 'localhost';

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
      'builds. Build the release version without it.';
}

/// The emulator to use, or null for the real project.
///
/// [releaseBuild] is `kReleaseMode`; passed in so tests can check both.
/// Throws [EmulatorInReleaseError] when [requested] in a release build, so
/// a deployed console can never talk to an emulator. [host] is
/// `EMULATOR_HOST`; empty means [EmulatorTarget.webHost].
EmulatorTarget? resolveEmulator({
  required bool requested,
  required bool releaseBuild,
  String host = '',
}) {
  if (!requested) return null;
  if (releaseBuild) throw const EmulatorInReleaseError();
  final h = host.trim();
  return EmulatorTarget(host: h.isEmpty ? EmulatorTarget.webHost : h);
}
