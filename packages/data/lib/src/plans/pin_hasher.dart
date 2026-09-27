import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';

/// The offline override PIN hash (02-DATA-MODEL `overridePinHash`, D-016):
/// PBKDF2-HMAC-SHA256, 100 000 iterations, a 32-byte key, stored as
/// `base64(salt)$base64(hash)`. The same scheme as the rules fixtures
/// (`firebase/test/support/fixtures.js` `hashPin`), so either side can check
/// the other's hash.
final class PinHasher {
  PinHasher({Random? random}) : _random = random ?? Random.secure();

  static const int iterations = 100000;
  static const int saltBytes = 16;
  static const int hashBytes = 32;

  final Random _random;

  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: hashBytes * 8,
  );

  /// Throws `DataFailure(ruleViolation)` unless [pin] is digits only and at
  /// least `Limits.minOverridePinDigits` long (D-031).
  static void checkPin(String pin) {
    if (pin.length < Limits.minOverridePinDigits ||
        !RegExp(r'^[0-9]+$').hasMatch(pin)) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'the PIN must be at least ${Limits.minOverridePinDigits} digits',
      );
    }
  }

  /// Hashes [pin] with a fresh random salt, or with [salt] (tests and
  /// fixtures only).
  Future<String> hash(String pin, {List<int>? salt}) async {
    checkPin(pin);
    final s =
        salt ?? List<int>.generate(saltBytes, (_) => _random.nextInt(256));
    return '${base64.encode(s)}\$${base64.encode(await _derive(pin, s))}';
  }

  /// True when [pin] matches [stored] (`salt$hash`). A malformed [stored]
  /// never matches.
  Future<bool> verify(String pin, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 2) return false;
    final List<int> salt;
    final List<int> want;
    try {
      salt = base64.decode(parts[0]);
      want = base64.decode(parts[1]);
    } on FormatException {
      return false;
    }
    final got = await _derive(pin, salt);
    if (got.length != want.length) return false;
    var diff = 0;
    for (var i = 0; i < got.length; i++) {
      diff |= got[i] ^ want[i];
    }
    return diff == 0;
  }

  static Future<List<int>> _derive(String pin, List<int> salt) async {
    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }
}
