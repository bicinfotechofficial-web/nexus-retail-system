// Placeholder for the trial project's Firebase options (D-040).
//
// `flutterfire configure` overwrites this file with the real values for the
// project `caramel-cottage-demo` (see docs/DEMO-RELEASE.md, step A). Until
// then the demo build stops with a clear message instead of silently using
// the real project.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw StateError(
    'The demo Firebase project is not configured yet. Run the flutterfire '
    'configure step for caramel-cottage-demo (docs/DEMO-RELEASE.md, step A).',
  );
}
