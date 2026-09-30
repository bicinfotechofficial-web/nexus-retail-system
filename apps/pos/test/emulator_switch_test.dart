import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_pos/app/emulator_switch.dart';

void main() {
  group('resolveEmulator', () {
    test('off unless requested: the real project', () {
      expect(resolveEmulator(requested: false, releaseBuild: false), isNull);
      expect(resolveEmulator(requested: false, releaseBuild: true), isNull);
    });

    test('a debug build reaches the emulators at 10.0.2.2', () {
      final t = resolveEmulator(requested: true, releaseBuild: false)!;
      expect(t.host, '10.0.2.2');
      expect(t.firestorePort, 8080);
      expect(t.authPort, 9099);
      expect(EmulatorTarget.projectId, 'demo-caramel-cottage');
    });

    test('EMULATOR_HOST points a physical phone at the PC', () {
      final t = resolveEmulator(
        requested: true,
        releaseBuild: false,
        host: ' 192.168.1.20 ',
      )!;
      expect(t.host, '192.168.1.20');
    });

    test('a release build refuses USE_EMULATOR', () {
      expect(
        () => resolveEmulator(requested: true, releaseBuild: true),
        throwsA(isA<EmulatorInReleaseError>()),
      );
      expect(
        () => resolveEmulator(
          requested: true,
          releaseBuild: true,
          host: '192.168.1.20',
        ),
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
