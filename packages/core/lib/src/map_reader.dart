/// Typed, strict reads from a Firestore document map.
///
/// Every model's `fromMap` goes through this, so a wrong or missing field
/// fails with a [FormatException] that names the document and field,
/// instead of a cast error somewhere later.
///
/// Timestamps must already be [DateTime]. The data package converts
/// Firestore `Timestamp` values at the boundary, so core stays pure Dart.
class MapReader {
  MapReader(this.data, this.context);

  final Map<String, Object?> data;

  /// What is being read, e.g. `bill D01-000123`, used in error messages.
  final String context;

  Never _fail(String key, String expected) => throw FormatException(
    '$context: field "$key" must be $expected, got ${data[key].runtimeType}',
  );

  String string(String key) {
    final v = data[key];
    return v is String ? v : _fail(key, 'a string');
  }

  String? stringOrNull(String key) {
    final v = data[key];
    if (v == null) return null;
    return v is String ? v : _fail(key, 'a string or null');
  }

  int integer(String key) {
    final v = data[key];
    return v is int ? v : _fail(key, 'an int');
  }

  int? integerOrNull(String key) {
    final v = data[key];
    if (v == null) return null;
    return v is int ? v : _fail(key, 'an int or null');
  }

  /// For defaulted fields such as `offlineLimitHours`.
  int integerOr(String key, int fallback) => integerOrNull(key) ?? fallback;

  bool boolean(String key) {
    final v = data[key];
    return v is bool ? v : _fail(key, 'a bool');
  }

  bool booleanOr(String key, bool fallback) {
    final v = data[key];
    if (v == null) return fallback;
    return v is bool ? v : _fail(key, 'a bool');
  }

  DateTime dateTime(String key) {
    final v = data[key];
    return v is DateTime ? v : _fail(key, 'a DateTime');
  }

  DateTime? dateTimeOrNull(String key) {
    final v = data[key];
    if (v == null) return null;
    return v is DateTime ? v : _fail(key, 'a DateTime or null');
  }

  T enumValue<T>(String key, T Function(String wire) fromWire) {
    try {
      return fromWire(string(key));
    } on FormatException catch (e) {
      throw FormatException('$context: field "$key": ${e.message}', e.source);
    }
  }

  List<String> stringList(String key) {
    final v = data[key];
    if (v is! List) _fail(key, 'a list of strings');
    return [
      for (final e in v)
        if (e is String) e else _fail(key, 'a list of strings'),
    ];
  }

  Map<String, Object?> map(String key) {
    final v = data[key];
    return v is Map ? v.cast<String, Object?>() : _fail(key, 'a map');
  }

  Map<String, Object?>? mapOrNull(String key) {
    final v = data[key];
    if (v == null) return null;
    return v is Map ? v.cast<String, Object?>() : _fail(key, 'a map or null');
  }

  /// A nested map read with its own [MapReader].
  MapReader child(String key) => MapReader(map(key), '$context.$key');

  MapReader? childOrNull(String key) {
    final m = mapOrNull(key);
    return m == null ? null : MapReader(m, '$context.$key');
  }

  /// A list of maps, each converted with [convert].
  List<T> objects<T>(String key, T Function(MapReader r) convert) {
    final v = data[key];
    if (v is! List) _fail(key, 'a list of maps');
    return [
      for (var i = 0; i < v.length; i++)
        if (v[i] case final Map<Object?, Object?> m)
          convert(MapReader(m.cast<String, Object?>(), '$context.$key[$i]'))
        else
          _fail(key, 'a list of maps'),
    ];
  }

  /// A list of maps that may be absent or null.
  List<T>? objectsOrNull<T>(String key, T Function(MapReader r) convert) =>
      data[key] == null ? null : objects(key, convert);

  /// A map from string keys to ints, such as `returnedQty`.
  Map<String, int> intMap(String key) {
    final v = data[key];
    if (v == null) return const {};
    if (v is! Map) _fail(key, 'a map of ints');
    return {
      for (final e in v.entries)
        if (e.key is String && e.value is int)
          e.key as String: e.value as int
        else
          e.key.toString(): _fail(key, 'a map of ints'),
    };
  }

  /// A map from string keys to nested maps, such as `byProduct`.
  Map<String, T> objectMap<T>(String key, T Function(MapReader r) convert) {
    final v = data[key];
    if (v == null) return const {};
    if (v is! Map) _fail(key, 'a map of maps');
    return {
      for (final e in v.entries)
        if (e.value case final Map<Object?, Object?> m)
          e.key.toString(): convert(
            MapReader(m.cast<String, Object?>(), '$context.$key.${e.key}'),
          )
        else
          e.key.toString(): _fail(key, 'a map of maps'),
    };
  }
}
