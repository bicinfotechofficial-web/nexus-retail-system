/// The override PIN hash is the same on both sides (02-DATA-MODEL
/// `overridePinHash`, D-016): the Dart `PinHasher` the apps use and
/// `hashPin` in `firebase/scripts/lib/core.js`, which the seed script and
/// the rules fixtures use. A POS verifies a seeded location's PIN offline,
/// so one byte of difference locks the store out of the override.
///
/// `test/e2e` can't import `nexus_data` (QA-016), so the Dart side comes
/// from the plan fixtures: `location_create.json` and `location_edit.json`
/// hold `PinHasher().hash('24681357', salt: utf8.encode('fixture-KTL'))`,
/// which `packages/data/test/plans/fixtures_test.dart` ("the KTL fixture
/// hash is PinHasher output") keeps true. Node then hashes the same PIN and
/// salt with core.js, and each side's verify accepts the other's hash.
/// Runs `node`; skipped where it isn't installed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/plan_store.dart';

/// The PIN behind the KTL fixture hash (fixtures_test.dart).
const String fixturePin = '24681357';

final String coreJs = File(
  '../../firebase/scripts/lib/core.js',
).absolute.uri.toString();

/// Runs [body] as an ES module importing core.js, and returns its stdout.
String node(String body) {
  final r = Process.runSync('node', [
    '--input-type=module',
    '-e',
    "import { hashPin, verifyPin, PIN_HASH_ITERATIONS, PIN_HASH_BYTES } from '$coreJs';\n$body",
  ]);
  if (r.exitCode != 0) fail('node failed: ${r.stderr}');
  return (r.stdout as String).trim();
}

bool get hasNode {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final fixtures = loadPlanFixtures();
  final dartHashes = {
    for (final name in ['location_create', 'location_edit'])
      name:
          fixtures[name]!.ops
                  .firstWhere((o) => o.collection == 'locations')
                  .data['overridePinHash']
              as String,
  };

  group('PIN hash: Dart PinHasher and core.js hashPin', () {
    test('the fixtures carry a Dart hash in the stored format', () {
      for (final e in dartHashes.entries) {
        final parts = e.value.split(r'$');
        expect(parts, hasLength(2), reason: e.key);
        expect(utf8.decode(base64.decode(parts[0])), 'fixture-KTL');
        expect(base64.decode(parts[1]), hasLength(32), reason: e.key);
      }
    });

    test('core.js uses the parameters of 02-DATA-MODEL', () {
      expect(
        node('console.log(PIN_HASH_ITERATIONS, PIN_HASH_BYTES)'),
        '100000 32',
      );
    }, skip: hasNode ? null : 'node is not installed');

    for (final e in dartHashes.entries) {
      test('${e.key}: same PIN and salt give the same bytes', () {
        final dart = e.value;
        final salt = dart.split(r'$').first;
        final fromNode = node(
          "console.log(hashPin('$fixturePin', Buffer.from('$salt', 'base64')))",
        );
        expect(fromNode, dart);
      }, skip: hasNode ? null : 'node is not installed');

      test('${e.key}: core.js verifyPin accepts the Dart hash, only for '
          'its PIN', () {
        final dart = e.value;
        expect(node("console.log(verifyPin('$fixturePin', '$dart'))"), 'true');
        expect(node("console.log(verifyPin('24681358', '$dart'))"), 'false');
        expect(
          node("console.log(verifyPin('$fixturePin ', '$dart'))"),
          'false',
        );
      }, skip: hasNode ? null : 'node is not installed');
    }
  });
}
