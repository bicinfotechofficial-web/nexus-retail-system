import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_pos/app/providers.dart';
import 'package:nexus_pos/fakes/fake_data.dart';

void main() {
  Future<ProviderContainer> signedInWith(FakeDeviceService devices) async {
    final c = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService.signedIn()),
        deviceServiceProvider.overrideWithValue(devices),
      ],
    );
    addTearDown(c.dispose);
    c.listen(sessionProvider, (_, _) {});
    await c.read(sessionProvider.future);
    return c;
  }

  test('a device registered at the user\'s location keeps its code', () async {
    final devices = FakeDeviceService();
    final c = await signedInWith(devices);
    expect(c.read(deviceIdProvider), devices.deviceId);
  });

  test('a device registered at another location must register again here '
      '(D-033)', () async {
    final devices = FakeDeviceService()..locationId = 'MNJ';
    final c = await signedInWith(devices);
    expect(c.read(locationCodeProvider), isNot('MNJ'));
    expect(c.read(deviceIdProvider), isNull);
  });

  test('an unregistered install has no device code', () async {
    final c = await signedInWith(FakeDeviceService(null));
    expect(c.read(deviceIdProvider), isNull);
  });
}
