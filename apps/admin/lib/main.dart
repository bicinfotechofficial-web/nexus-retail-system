import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import 'app.dart';
import 'data/emulator_switch.dart';
import 'data/firebase_start.dart';
import 'data/services.dart';
import 'fakes/fake_backend.dart';
import 'login/login_screen.dart';

/// `--dart-define=FAKE_DATA=true` runs the console on in-memory fakes of
/// the `nexus_data` interfaces, without Firebase.
const bool useFakeData = bool.fromEnvironment('FAKE_DATA');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useFakeData) {
    final fakes = FakeBackend.seeded(today: BusinessDate.of(DateTime.now()));
    runApp(
      ProviderScope(
        overrides: [
          ...fakes.overrides,
          demoLoginHintProvider.overrideWithValue(
            'Demo data. Admin: ${FakeBackend.adminEmail}, '
            'Store Manager: ${FakeBackend.storeManagerEmail}, '
            'password ${FakeBackend.demoPassword}.',
          ),
        ],
        child: const AdminApp(),
      ),
    );
    return;
  }
  await startConsole();
}

/// Starts on the real data layer: the project in `firebase_options.dart`,
/// or the emulators with USE_EMULATOR in a debug build. A saved sign-in is
/// restored before the console shows, so a signed-in Admin lands on the
/// page they asked for, not on the login page.
Future<void> startConsole() async {
  runApp(const StartingApp());
  try {
    final emulator = resolveEmulator(
      requested: useEmulatorDefine,
      releaseBuild: kReleaseMode,
      host: emulatorHostDefine,
    );
    if (emulator != null) {
      debugPrint('Console: using the emulators at $emulator');
    }
    final backend = await startFirebase(emulator);
    await restoredSession(backend.authService);
    runApp(
      ProviderScope(
        overrides: [
          ...AdminServices.fromBackend(backend).overrides,
          if (emulator != null)
            demoLoginHintProvider.overrideWithValue(
              'Local emulator (${EmulatorTarget.projectId}). Sign in with '
              'the Admin created by the seed script.',
            ),
        ],
        child: const AdminApp(),
      ),
    );
  } on Object catch (e, st) {
    debugPrint('Console: startup failed: $e\n$st');
    runApp(StartupErrorApp(error: e, onRetry: startConsole));
  }
}
