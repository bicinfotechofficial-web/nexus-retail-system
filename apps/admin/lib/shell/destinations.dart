import 'package:flutter/material.dart';
import 'package:nexus_core/nexus_core.dart';

/// A side-nav entry and the permissions that unlock it (any one of them).
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
}

const List<Destination> destinations = [
  Destination(
    path: '/dashboard',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    anyOf: [Permission.reportOwn, Permission.reportAll],
  ),
  Destination(
    path: '/reports',
    label: 'Reports',
    icon: Icons.bar_chart_outlined,
    anyOf: [Permission.reportOwn, Permission.reportAll],
  ),
  Destination(
    path: '/catalog',
    label: 'Catalog',
    icon: Icons.cake_outlined,
    anyOf: [Permission.catalogManage],
  ),
  Destination(
    path: '/locations',
    label: 'Locations',
    icon: Icons.storefront_outlined,
    anyOf: [Permission.locationManage],
  ),
  Destination(
    path: '/users',
    label: 'Users',
    icon: Icons.people_outline,
    anyOf: [Permission.userManage],
  ),
  Destination(
    path: '/devices',
    label: 'Devices',
    icon: Icons.phone_android_outlined,
    anyOf: [Permission.locationManage],
  ),
];

Destination destinationFor(String path) => destinations.firstWhere(
  (d) => path.startsWith(d.path),
  orElse: () => destinations.first,
);
