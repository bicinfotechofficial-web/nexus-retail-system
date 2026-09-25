import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_core/nexus_core.dart';

import 'app.dart';
import 'fakes/fake_backend.dart';
import 'firebase_options.dart';
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final overrides = firestoreOverrides();
  if (overrides.isEmpty) {
    runApp(
      const StartupErrorApp(
        'The Firestore data layer is not available in this build yet. '
        'Run with --dart-define=FAKE_DATA=true to use demo data.',
      ),
    );
    return;
  }
  runApp(ProviderScope(overrides: overrides, child: const AdminApp()));
}

/// The Firestore implementations of the `nexus_data` interfaces the console
/// uses. Empty until the backend implementations (BE-8 to BE-13) are merged;
/// then this overrides every provider in `data/providers.dart`.
List<Override> firestoreOverrides() => const [];
