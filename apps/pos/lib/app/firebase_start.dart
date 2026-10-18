import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../firebase_options.dart';
import '../firebase_options_demo.dart' as demo;
import 'emulator_switch.dart';
import 'services.dart';

/// The Firebase app the POS runs on against the emulator. The default app
/// is configured natively from `google-services.json` with the real
/// project, so the emulator gets its own app with the demo project ID.
const String emulatorAppName = 'pos-emulator';

NexusBackend? _backend;

/// Initialises Firebase, builds the `nexus_data` backend (D-026) and the
/// Bluetooth printer, and returns them as the POS's services.
///
/// With [emulator], Firestore and Auth go to the emulators, on an app with
/// the demo project ID and its own local stores (so a device code or queued
/// write from the real project never mixes with emulator data).
///
/// Safe to call again after a failure: a backend that was already built is
/// reused rather than started twice.
Future<PosServices> startFirebase(EmulatorTarget? emulator) async {
  final backend = _backend ??= await _openBackend(emulator);
  final printer = await BluetoothPrinterService.create();
  return PosServices.fromBackend(backend, printer);
}

Future<NexusBackend> _openBackend(EmulatorTarget? emulator) async {
  // The demo build (--flavor demo) runs on its own Firebase project (D-040).
  final options = appFlavor == 'demo'
      ? demo.DefaultFirebaseOptions.currentPlatform
      : DefaultFirebaseOptions.currentPlatform;
  if (emulator == null) {
    await Firebase.initializeApp(options: options);
    return NexusBackend.firebase();
  }
  final app = Firebase.apps.any((a) => a.name == emulatorAppName)
      ? Firebase.app(emulatorAppName)
      : await Firebase.initializeApp(
          name: emulatorAppName,
          options: options.copyWith(projectId: EmulatorTarget.projectId),
        );
  return NexusBackend.firebase(
    app: app,
    boxPrefix: 'emulator-',
    configure: (db, auth) async {
      db.useFirestoreEmulator(emulator.host, emulator.firestorePort);
      await auth.useAuthEmulator(emulator.host, emulator.authPort);
    },
  );
}
