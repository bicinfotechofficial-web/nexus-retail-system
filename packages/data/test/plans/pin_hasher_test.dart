import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_data/nexus_data.dart';

void main() {
  final hasher = PinHasher(random: Random(1));

  test('matches the rules fixtures (Node pbkdf2Sync, 100k, SHA-256)', () async {
    // firebase/test/support/fixtures.js: hashPin('24681357', 'fixture-PTB').
    const node =
        r'Zml4dHVyZS1QVEI=$Y5vbC8c+d3PwEX2ASwf0fm4jcorZvWHcpBdeOcHbJ/E=';
    expect(
      await hasher.hash('24681357', salt: utf8.encode('fixture-PTB')),
      node,
    );
    expect(await hasher.verify('24681357', node), isTrue);
    expect(await hasher.verify('24681358', node), isFalse);
  });

  test('a fresh salt of 16 bytes each time', () async {
    final a = await hasher.hash('12345678');
    final b = await hasher.hash('12345678');
    expect(a, isNot(b));
    expect(base64.decode(a.split(r'$').first), hasLength(PinHasher.saltBytes));
    expect(base64.decode(a.split(r'$').last), hasLength(PinHasher.hashBytes));
    expect(await hasher.verify('12345678', b), isTrue);
  });

  test('refuses short or non-digit PINs', () {
    for (final pin in ['1234567', '1234567a', '', '12 345678']) {
      expect(
        () => PinHasher.checkPin(pin),
        throwsA(isA<DataFailure>()),
        reason: pin,
      );
    }
    PinHasher.checkPin('12345678');
  });

  test('a malformed stored hash never matches', () async {
    expect(await hasher.verify('12345678', 'nodollar'), isFalse);
    expect(await hasher.verify('12345678', r'!!$!!'), isFalse);
    expect(await hasher.verify('12345678', r'YQ==$YQ=='), isFalse);
  });
}
