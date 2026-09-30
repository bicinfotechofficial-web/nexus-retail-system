import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/emulator_switch.dart';
import 'app/firebase_start.dart';
import 'app/startup_error.dart';
import 'fakes/fake_backend.dart';

/// `--dart-define=FAKE_DATA=true` runs on in-memory fakes, without Firebase.
const bool useFakeData = bool.fromEnvironment('FAKE_DATA');

/// With FAKE_DATA, `--dart-define=FAKE_FIRST_RUN=true` starts signed out on
/// an unregistered install, to walk through sign-in and device setup. The
/// demo login is `sm.ptb@example.com` / `cottage-demo` (FakeAuthService).
const bool fakeFirstRun = bool.fromEnvironment('FAKE_FIRST_RUN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useFakeData) {
    final fake = FakeBackend(
      signedIn: !fakeFirstRun,
      registered: !fakeFirstRun,
    );
    await fake.seedDemo();
    runApp(ProviderScope(overrides: fake.overrides, child: const PosApp()));
    return;
  }
  await startPos();
}

/// Starts on the real data layer: the project in `firebase_options.dart`,
/// or the emulators with USE_EMULATOR in a debug build. The router then
/// goes from a restored session (or sign-in) to device setup or billing.
Future<void> startPos() async {
  try {
    final emulator = resolveEmulator(
      requested: useEmulatorDefine,
      releaseBuild: kReleaseMode,
      host: emulatorHostDefine,
    );
    if (emulator != null) debugPrint('POS: using the emulators at $emulator');
    final services = await startFirebase(emulator);
    runApp(ProviderScope(overrides: services.overrides, child: const PosApp()));
  } on Object catch (e, st) {
    debugPrint('POS: startup failed: $e\n$st');
    runApp(StartupErrorApp(error: e, onRetry: startPos));
  }
}
