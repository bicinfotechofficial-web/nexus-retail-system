import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/data/emulator_switch.dart';

void main() {
  group('resolveEmulator', () {
    test('off unless requested: the real project', () {
      expect(resolveEmulator(requested: false, releaseBuild: false), isNull);
      expect(resolveEmulator(requested: false, releaseBuild: true), isNull);
    });

    test('a debug build reaches the emulators on localhost', () {
      final t = resolveEmulator(requested: true, releaseBuild: false)!;
      expect(t.host, 'localhost');
      expect(t.firestorePort, 8080);
      expect(t.authPort, 9099);
      expect(EmulatorTarget.projectId, 'demo-caramel-cottage');
    });

    test('EMULATOR_HOST overrides the host', () {
      final t = resolveEmulator(
        requested: true,
        releaseBuild: false,
        host: '127.0.0.1',
      )!;
      expect(t.host, '127.0.0.1');
    });

    test('a release build refuses USE_EMULATOR', () {
      expect(
        () => resolveEmulator(requested: true, releaseBuild: true),
        throwsA(isA<EmulatorInReleaseError>()),
      );
    });

    test('tests run in debug, where the defines are off', () {
      expect(kReleaseMode, isFalse);
      expect(useEmulatorDefine, isFalse);
      expect(emulatorHostDefine, isEmpty);
    });
  });
}
