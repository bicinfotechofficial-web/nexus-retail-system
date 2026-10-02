import 'package:flutter/services.dart';
import 'package:nexus_printer/nexus_printer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in another app (WhatsApp, D-036a). Behind an interface so
/// tests use a fake.
abstract interface class LinkLauncher {
  /// True when an app took the link, false when none could open it.
  Future<bool> open(Uri uri);
}

/// [LinkLauncher] on `url_launcher`, always in an external app.
final class UrlLinkLauncher implements LinkLauncher {
  const UrlLinkLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}

/// Turns a receipt into a PNG for sharing (D-036b). The default is
/// `renderReceiptPng`; tests replace it, since real image encoding needs
/// the engine.
typedef ReceiptImageRenderer =
    Future<Uint8List> Function(ReceiptDocument doc, PaperWidth width);

Future<Uint8List> renderReceiptImage(ReceiptDocument doc, PaperWidth width) =>
    renderReceiptPng(doc, width: width);
