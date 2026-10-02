import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'limits.dart';

/// Checks for the customer fields on a bill (D-034) and the customer ID
/// (D-037). Both apps and the data layer use these, so the same input is
/// accepted or refused everywhere. The rules repeat the shape checks.
abstract final class CustomerValidator {
  static final RegExp _mobile = RegExp(r'^[6-9][0-9]{9}$');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _nonDigits = RegExp(r'[^0-9]');

  /// Trims and collapses runs of whitespace. This is what is stored.
  static String cleanName(String name) => name.trim().replaceAll(_spaces, ' ');

  /// Keeps only the digits, and drops a leading `+91`, `91` or `0` when
  /// that leaves ten digits, so a pasted `+91 98765 43210` works.
  static String cleanPhone(String input) {
    var digits = input.replaceAll(_nonDigits, '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// A message for the form, or null when [name] is fine.
  static String? nameError(String name) {
    final n = cleanName(name);
    if (n.isEmpty) return 'Enter the customer name.';
    if (n.length > Limits.customerNameMax) {
      return 'Name can be at most ${Limits.customerNameMax} characters.';
    }
    return null;
  }

  /// A message for the form, or null when [phone] is a valid mobile.
  static String? phoneError(String phone) {
    final p = cleanPhone(phone);
    if (p.isEmpty) return 'Enter the mobile number.';
    if (!_mobile.hasMatch(p)) {
      return 'Enter a 10-digit mobile number starting with 6, 7, 8 or 9.';
    }
    return null;
  }

  /// Same shape as [phoneError]. Null means "no WhatsApp", which is fine.
  static String? whatsappError(String? number) =>
      number == null ? null : phoneError(number);

  static bool isMobile(String s) => _mobile.hasMatch(s);
}

/// `{phone}_{nameKey}` (D-037). The same mobile with a different name is a
/// different customer.
abstract final class CustomerId {
  static final RegExp _shape = RegExp(r'^[6-9][0-9]{9}_[0-9a-f]{10}$');

  /// Case, spacing and Unicode form don't change the ID. The name is
  /// normalised as: trim, collapse spaces, lower-case. (Dart has no built-in
  /// NFC, so a name typed with a different Unicode form of the same letters
  /// can give a second customer, which D-037 accepts.)
  static String nameKey(String name) {
    final normal = CustomerValidator.cleanName(name).toLowerCase();
    return sha256.convert(utf8.encode(normal)).toString().substring(0, 10);
  }

  /// [phone] must already be ten digits (see `CustomerValidator.cleanPhone`).
  static String of(String phone, String name) {
    if (!CustomerValidator.isMobile(phone)) {
      throw ArgumentError.value(phone, 'phone', 'must be a 10-digit mobile');
    }
    return '${phone}_${nameKey(name)}';
  }

  static bool isValid(String id) => _shape.hasMatch(id);

  /// The mobile part of a valid [id].
  static String phoneOf(String id) => id.substring(0, 10);
}
