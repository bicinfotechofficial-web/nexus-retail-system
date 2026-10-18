import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../firebase_options.dart';
import '../firebase_options_demo.dart' as demo;
import 'emulator_switch.dart';

/// `--dart-define=APP_ENV=demo` builds the trial console, which runs on its own
/// Firebase project (D-040). Anything else is the real system.
const String _appEnv = String.fromEnvironment('APP_ENV');

NexusBackend? _backend;

/// Initialises Firebase and builds the console's `nexus_data` backend
/// (`NexusBackend.firebase(admin: true)`: online only, writes wait for the
/// server, D-026).
///
/// With [emulator], the default app gets the demo project ID and Firestore
/// and Auth go to the emulators, including the secondary app that creates
/// Store Manager accounts (AD-4), so a new account never lands in the real
/// project.
///
/// Safe to call again after a failure: a backend that was already built is
/// reused.
Future<NexusBackend> startFirebase(EmulatorTarget? emulator) async =>
    _backend ??= await _open(emulator);

Future<NexusBackend> _open(EmulatorTarget? emulator) async {
  final options = _appEnv == 'demo'
      ? demo.DefaultFirebaseOptions.currentPlatform
      : DefaultFirebaseOptions.currentPlatform;
  if (emulator == null) {
    await Firebase.initializeApp(options: options);
    return NexusBackend.firebase(admin: true);
  }
  await Firebase.initializeApp(
    options: options.copyWith(projectId: EmulatorTarget.projectId),
  );
  var secondaryOnEmulator = false;
  return NexusBackend.firebase(
    admin: true,
    configure: (db, auth) async {
      db.useFirestoreEmulator(emulator.host, emulator.firestorePort);
      await auth.useAuthEmulator(emulator.host, emulator.authPort);
    },
    secondaryAuth: () async {
      // The same app the default factory opens (with the default app's
      // options, so the demo project), pointed at the Auth emulator once,
      // before its first use.
      final auth = await FirestoreUserService.secondaryAuthFromDefaultApp();
      if (!secondaryOnEmulator) {
        await auth.useAuthEmulator(emulator.host, emulator.authPort);
        secondaryOnEmulator = true;
      }
      return auth;
    },
  );
}

/// Waits until [auth] knows whether a session was restored (it emits its
/// first value then), so the console doesn't flash the login page, or lose
/// the page in the address bar, for an Admin who is still signed in. Gives
/// up after [timeout] and starts signed out.
Future<SessionContext?> restoredSession(
  AuthService auth, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    return await auth.session.first.timeout(timeout);
  } on Object {
    return auth.current;
  }
}
