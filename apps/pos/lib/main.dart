import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'app/app.dart';
import 'fakes/fake_backend.dart';
import 'firebase_options.dart';

/// `--dart-define=FAKE_DATA=true` runs on in-memory fakes, without Firebase.
const bool useFakeData = bool.fromEnvironment('FAKE_DATA');

/// With FAKE_DATA, `--dart-define=FAKE_FIRST_RUN=true` starts signed out on
/// an unregistered install, to walk through sign-in and device setup. The
/// demo login is `sm.ptb@example.com` / `cottage-demo` (FakeAuthService).
const bool fakeFirstRun = bool.fromEnvironment('FAKE_FIRST_RUN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final List<Override> overrides;
  if (useFakeData) {
    final fake = FakeBackend(
      signedIn: !fakeFirstRun,
      registered: !fakeFirstRun,
    );
    await fake.seedDemo();
    overrides = fake.overrides;
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // The nexus_data and nexus_printer implementations are overridden here
    // once they are merged (BE-8…BE-13, PR-5). Until then the providers
    // report that they aren't configured.
    overrides = const [];
  }
  runApp(ProviderScope(overrides: overrides, child: const PosApp()));
}
