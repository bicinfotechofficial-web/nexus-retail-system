import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// A decoded logo: straight (non-premultiplied) RGBA, row by row.
final class LogoBitmap {
  LogoBitmap({required this.width, required this.height, required this.rgba})
    : assert(width > 0 && height > 0, 'empty logo $width x $height'),
      assert(rgba.length == width * height * 4, 'rgba is the wrong length');

  final int width;
  final int height;

  /// 4 bytes per pixel: red, green, blue, alpha.
  final Uint8List rgba;
}

/// Where the shop logo comes from (D-041). The receipt code only asks for
/// it; tests pass a synthetic one and never touch the asset bundle.
///
/// [load] returns null when there is no logo, and must not throw: a bill
/// prints without a logo rather than not at all.
abstract interface class ReceiptLogo {
  Future<LogoBitmap?> load();
}

/// No logo: receipts print as text only.
final class NoReceiptLogo implements ReceiptLogo {
  const NoReceiptLogo();

  @override
  Future<LogoBitmap?> load() async => null;
}

/// Loads `assets/brand/logo.png` of this package through the asset bundle.
/// Any failure (asset missing, bytes not an image, decode error) gives null.
/// The result, including a null, is kept for the life of the object.
final class AssetReceiptLogo implements ReceiptLogo {
  AssetReceiptLogo({AssetBundle? bundle, this.assetKey = defaultAssetKey})
    : _bundle = bundle;

  /// The key an app that depends on this package sees.
  static const String defaultAssetKey =
      'packages/nexus_printer/assets/brand/logo.png';

  /// Larger than this is refused rather than decoded (about 64 MB of RGBA).
  static const int maxPixels = 16 * 1000 * 1000;

  final AssetBundle? _bundle;
  final String assetKey;
  Future<LogoBitmap?>? _loading;

  @override
  Future<LogoBitmap?> load() => _loading ??= _read();

  Future<LogoBitmap?> _read() async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      final data = await (_bundle ?? rootBundle).load(assetKey);
      codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      image = (await codec.getNextFrame()).image;
      final w = image.width;
      final h = image.height;
      if (w <= 0 || h <= 0 || w * h > maxPixels) return null;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return null;
      return LogoBitmap(
        width: w,
        height: h,
        rgba: pixels.buffer.asUint8List(
          pixels.offsetInBytes,
          pixels.lengthInBytes,
        ),
      );
    } on Object {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

/// The logo shared by every call that does not pass its own.
final ReceiptLogo defaultReceiptLogo = AssetReceiptLogo();

/// [logo]'s bitmap, or null when it has none or fails. Never throws.
Future<LogoBitmap?> loadLogoSafely(ReceiptLogo logo) async {
  try {
    return await logo.load();
  } on Object {
    return null;
  }
}
