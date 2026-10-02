import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands a receipt image to the Android share sheet (D-036b). The cashier
/// picks the chat; nothing is sent automatically and nothing is recorded
/// as sent. The POS depends on this interface, so tests use a fake.
abstract interface class ReceiptSharer {
  /// Opens the share sheet with [png], named [fileName] (for example
  /// `PTB-D01-000123.png`), and [text] as the optional caption.
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
  });
}

/// [ReceiptSharer] on `share_plus`. The PNG goes in as in-memory data and
/// the plugin writes the temporary file itself.
final class SharePlusReceiptSharer implements ReceiptSharer {
  const SharePlusReceiptSharer();

  @override
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
        fileNameOverrides: [fileName],
        text: text,
      ),
    );
  }
}
