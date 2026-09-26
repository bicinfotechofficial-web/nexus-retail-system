import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Compares [actual] with `test/goldens/<name>.txt`. Run
/// `flutter test --update-goldens` to rewrite the files after an intended
/// layout change, then review the diff before committing.
void expectTextGolden(String actual, String name) {
  final file = File('test/goldens/$name.txt');
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
    reason: '${file.path} is missing; run flutter test --update-goldens',
  );
  expect(text, file.readAsStringSync(), reason: 'golden ${file.path}');
}
