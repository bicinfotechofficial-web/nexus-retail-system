// Direct access to the Firebase emulator for seeding and for the oracles,
// over the emulators' REST APIs with the `owner` token, which bypasses the
// security rules. The scenarios never use this to do what a device does:
// devices only go through the `nexus_data` interfaces (support/backend.dart).

import 'dart:convert';
import 'dart:io';

/// Where the emulator is. From an Android emulator the host machine is
/// `10.0.2.2`; override with `--dart-define=EMULATOR_HOST=...` for a
/// physical phone on the same network.
final class EmulatorTarget {
  const EmulatorTarget({
    required this.host,
    this.firestorePort = 8080,
    this.authPort = 9099,
    this.projectId = 'demo-caramel-cottage',
  });

  /// Reads `--dart-define=USE_EMULATOR=true` and `EMULATOR_HOST`. Throws
  /// when USE_EMULATOR is not set, so a run can never reach a real project.
  factory EmulatorTarget.fromEnvironment() {
    const useEmulator = bool.fromEnvironment('USE_EMULATOR');
    if (!useEmulator) {
      throw StateError(
        'The device scenarios run against the Firebase emulator only. '
        'Run with --dart-define=USE_EMULATOR=true (see integration_test/README.md).',
      );
    }
    return const EmulatorTarget(
      host: String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2'),
    );
  }

  final String host;
  final int firestorePort;
  final int authPort;

  /// The demo project from docs/SETUP-FIREBASE.md; the emulator never
  /// reaches a real project with a `demo-` ID.
  final String projectId;
}

/// A Firestore document as read back from the emulator.
typedef Doc = ({String id, Map<String, Object?> data});

/// Owner access to the emulator: clear it, create Auth users, and read and
/// write any document, rules off.
final class EmulatorAdmin {
  EmulatorAdmin(this.target);

  final EmulatorTarget target;
  final HttpClient _http = HttpClient();

  String get _firestore =>
      'http://${target.host}:${target.firestorePort}/v1/projects/'
      '${target.projectId}/databases/(default)/documents';

  /// Deletes every document and every Auth user.
  Future<void> reset() async {
    await _send(
      'DELETE',
      Uri.parse(
        'http://${target.host}:${target.firestorePort}/emulator/v1/projects/'
        '${target.projectId}/databases/(default)/documents',
      ),
    );
    await _send(
      'DELETE',
      Uri.parse(
        'http://${target.host}:${target.authPort}/emulator/v1/projects/'
        '${target.projectId}/accounts',
      ),
    );
  }

  /// Creates an email/password account in the Auth emulator; returns its uid.
  Future<String> createAuthUser(String email, String password) async {
    final res = await _send(
      'POST',
      Uri.parse(
        'http://${target.host}:${target.authPort}/identitytoolkit.googleapis.com'
        '/v1/accounts:signUp?key=demo-api-key',
      ),
      {'email': email, 'password': password, 'returnSecureToken': true},
    );
    return res!['localId']! as String;
  }

  /// Creates or replaces the document at [path].
  Future<void> set(String path, Map<String, Object?> data) async {
    await _send('PATCH', Uri.parse('$_firestore/$path'), {
      'fields': FirestoreValues.encodeFields(data),
    });
  }

  /// Sets only [fields] on the existing document at [path].
  Future<void> update(String path, Map<String, Object?> fields) async {
    final mask = fields.keys
        .map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}')
        .join('&');
    await _send(
      'PATCH',
      Uri.parse('$_firestore/$path?$mask&currentDocument.exists=true'),
      {'fields': FirestoreValues.encodeFields(fields)},
    );
  }

  /// The document at [path], or null when it doesn't exist.
  Future<Map<String, Object?>?> get(String path) async {
    final res = await _send('GET', Uri.parse('$_firestore/$path'), null, {404});
    if (res == null) return null;
    return FirestoreValues.decodeFields(res['fields']);
  }

  /// Every document of the collection at [path].
  Future<List<Doc>> list(String path) async {
    final out = <Doc>[];
    String? pageToken;
    do {
      final token = pageToken == null ? '' : '&pageToken=$pageToken';
      final res = await _send(
        'GET',
        Uri.parse('$_firestore/$path?pageSize=300$token'),
      );
      final docs = (res?['documents'] as List<Object?>?) ?? const [];
      for (final d in docs.cast<Map<String, Object?>>()) {
        final name = d['name']! as String;
        out.add((
          id: name.substring(name.lastIndexOf('/') + 1),
          data: FirestoreValues.decodeFields(d['fields']),
        ));
      }
      pageToken = res?['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return out;
  }

  void close() => _http.close(force: true);

  Future<Map<String, Object?>?> _send(
    String method,
    Uri uri, [
    Map<String, Object?>? body,
    Set<int> nullOn = const {},
  ]) async {
    final req = await _http.openUrl(method, uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (nullOn.contains(res.statusCode)) return null;
    if (res.statusCode >= 300) {
      throw HttpException('$method $uri → ${res.statusCode}: $text', uri: uri);
    }
    if (text.trim().isEmpty) return null;
    return jsonDecode(text) as Map<String, Object?>;
  }
}

/// Plain Dart values ⇄ Firestore REST `Value`s. Timestamps are [DateTime]
/// on the Dart side, as the `nexus_core` models expect.
abstract final class FirestoreValues {
  static Map<String, Object?> encodeFields(Map<String, Object?> data) => {
    for (final e in data.entries) e.key: encode(e.value),
  };

  static Map<String, Object?> encode(Object? v) => switch (v) {
    null => {'nullValue': null},
    final bool b => {'booleanValue': b},
    final int i => {'integerValue': '$i'},
    final double d => {'doubleValue': d},
    final String s => {'stringValue': s},
    final DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
    final List<Object?> l => {
      'arrayValue': {'values': l.map(encode).toList()},
    },
    final Map<String, Object?> m => {
      'mapValue': {'fields': encodeFields(m)},
    },
    _ => throw ArgumentError('Cannot encode ${v.runtimeType} for Firestore'),
  };

  static Map<String, Object?> decodeFields(Object? fields) => {
    for (final e in ((fields as Map<String, Object?>?) ?? const {}).entries)
      e.key: decode(e.value! as Map<String, Object?>),
  };

  static Object? decode(Map<String, Object?> v) {
    final MapEntry(:key, :value) = v.entries.single;
    return switch (key) {
      'nullValue' => null,
      'booleanValue' => value! as bool,
      'integerValue' => int.parse(value! as String),
      'doubleValue' => (value! as num).toDouble(),
      'stringValue' => value! as String,
      'timestampValue' => DateTime.parse(value! as String),
      'arrayValue' => [
        for (final x
            in ((value! as Map<String, Object?>)['values'] as List<Object?>?) ??
                const <Object?>[])
          decode(x! as Map<String, Object?>),
      ],
      'mapValue' => decodeFields((value! as Map<String, Object?>)['fields']),
      _ => throw ArgumentError('Unsupported Firestore value type $key'),
    };
  }
}
