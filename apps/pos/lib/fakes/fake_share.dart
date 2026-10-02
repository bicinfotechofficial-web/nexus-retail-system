import 'dart:typed_data';

import 'package:nexus_printer/nexus_printer.dart';

import '../app/phone_store.dart';
import '../app/share.dart';

/// A [LinkLauncher] that records the links and can pretend that no app
/// opens them.
final class FakeLinkLauncher implements LinkLauncher {
  /// Every link passed to [open], in order.
  final List<Uri> opened = [];

  /// Whether an app (WhatsApp) takes the link.
  bool canOpen = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return canOpen;
  }
}

/// One call to [FakeReceiptSharer.shareImage].
typedef SharedImage = ({Uint8List png, String fileName, String? text});

/// A [ReceiptSharer] that records the images instead of opening the share
/// sheet.
final class FakeReceiptSharer implements ReceiptSharer {
  final List<SharedImage> shared = [];

  /// When set, the next share throws it.
  Exception? failNext;

  @override
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
  }) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    shared.add((png: png, fileName: fileName, text: text));
  }
}

/// A [PhoneStore] in memory. Give the same one to a second backend to
/// "restart" the app on the same phone.
final class MemoryPhoneStore implements PhoneStore {
  final Map<String, Object> values = {};

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<List<String>?> getStringList(String key) async =>
      (values[key] as List<String>?)?.toList();

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      values[key] = [...value];
}

/// A [ReceiptImageRenderer] that records what it was asked to draw and
/// returns a few fixed bytes, so tests don't need the engine's image codec.
final class FakeReceiptRenderer {
  /// Every call as (document, paper width), in order.
  final List<(ReceiptDocument, PaperWidth)> calls = [];

  static final Uint8List bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);

  Future<Uint8List> call(ReceiptDocument doc, PaperWidth width) async {
    calls.add((doc, width));
    return bytes;
  }
}
