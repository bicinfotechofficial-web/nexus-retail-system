import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Compares [actual] with `test/goldens/<name>.txt`. Run
/// `flutter test --update-goldens` to rewrite the files after an intended
/// layout change, then review the diff before committing.
void expectTextGolden(String actual, String name) =>
    _expectGoldenFile(actual, 'test/goldens/$name.txt');

/// Compares [bytes] with `test/goldens/<name>.hex`: 16 bytes per line, as
/// lowercase hex, so a byte diff is readable in review.
void expectBytesGolden(List<int> bytes, String name) {
  final rows = <String>[
    for (var i = 0; i < bytes.length; i += 16)
      bytes
          .sublist(i, i + 16 > bytes.length ? bytes.length : i + 16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' '),
  ];
  _expectGoldenFile(rows.join('\n'), 'test/goldens/$name.hex');
}

void _expectGoldenFile(String actual, String path) {
  final file = File(path);
  final text = '$actual\n';
  if (autoUpdateGoldenFiles) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path is missing; run flutter test --update-goldens',
  );
  expect(text, file.readAsStringSync(), reason: 'golden $path');
}
