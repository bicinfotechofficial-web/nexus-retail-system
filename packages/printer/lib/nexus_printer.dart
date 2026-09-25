/// Receipt documents, the text layout engine, the ESC/POS encoder and the
/// Bluetooth Classic transport.
///
/// `src/api.dart` is the contract the POS app builds against; the central
/// agent owns it, and changes go through docs/CHANGE-REQUESTS.md. The
/// printer agent implements it (PR-1 to PR-6).
library;

export 'src/api.dart';
