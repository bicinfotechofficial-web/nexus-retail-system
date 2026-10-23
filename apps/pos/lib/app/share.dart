import 'dart:typed_data';
import 'package:nexus_printer/nexus_printer.dart';

/// Turns a receipt into a PNG for sharing (D-036b). The default is
/// `renderReceiptPng`; tests replace it, since real image encoding needs
/// the engine.
typedef ReceiptImageRenderer =
    Future<Uint8List> Function(ReceiptDocument doc, PaperWidth width);

Future<Uint8List> renderReceiptImage(ReceiptDocument doc, PaperWidth width) =>
    renderReceiptPng(doc, width: width);
