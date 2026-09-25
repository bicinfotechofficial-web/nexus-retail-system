import 'package:flutter/material.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// A top-level screen in the navigation drawer. It is shown only when the
/// session has at least one of [anyOf] (D-017: permissions, never roles).
final class Destination {
  const Destination({
    required this.path,
    required this.label,
    required this.icon,
    required this.anyOf,
  });

  final String path;
  final String label;
  final IconData icon;
  final List<String> anyOf;

  bool allowedFor(SessionContext session) => anyOf.any(session.can);
}

abstract final class Destinations {
  static const Destination billing = Destination(
    path: '/',
    label: 'Billing',
    icon: Icons.point_of_sale,
    anyOf: [Permission.billCreate],
  );
  static const Destination bills = Destination(
    path: '/bills',
    label: 'Bills',
    icon: Icons.receipt_long,
    anyOf: [Permission.reportOwn],
  );
  static const Destination stock = Destination(
    path: '/stock',
    label: 'Stock',
    icon: Icons.inventory_2,
    anyOf: [
      Permission.stockMove,
      Permission.stockAdjust,
      Permission.stockThreshold,
    ],
  );
  static const Destination summary = Destination(
    path: '/summary',
    label: 'Day summary',
    icon: Icons.insights,
    anyOf: [Permission.reportOwn],
  );

  static const List<Destination> all = [billing, bills, stock, summary];

  static List<Destination> allowedFor(SessionContext session) =>
      all.where((d) => d.allowedFor(session)).toList();
}
