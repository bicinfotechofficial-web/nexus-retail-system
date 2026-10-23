import 'package:flutter/material.dart';
import 'package:nexus_core/nexus_core.dart';

import '../data/providers.dart';

/// A drop-down of stores for a page's own filter. [value] is a location code,
/// or null for "All stores" when [allowAll] is set. Deactivated stores stay
/// in the list, marked, because their staff, attendance and orders remain.
class StorePicker extends StatelessWidget {
  const StorePicker({
    required this.locations,
    required this.value,
    required this.onChanged,
    this.allowAll = false,
    this.label = 'Store',
    super.key,
  });

  final List<Location> locations;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowAll;
  final String label;

  @override
  Widget build(BuildContext context) {
    final sorted = [...locations]..sort((a, b) => a.code.compareTo(b.code));
    final known = sorted.any((l) => l.code == value);
    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String?>(
        key: ValueKey(value),
        initialValue: known ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
        items: [
          if (allowAll)
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All stores'),
            ),
          for (final l in sorted)
            DropdownMenuItem<String?>(
              value: l.code,
              child: Text(locationLabel(l), overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

/// The store a page opens on: the one chosen in the top-bar switcher, else the
/// first open store by code, else the first store. [locations] must not be
/// empty.
String defaultStore(List<Location> locations, String? preferred) {
  final sorted = [...locations]..sort((a, b) => a.code.compareTo(b.code));
  if (preferred != null && sorted.any((l) => l.code == preferred)) {
    return preferred;
  }
  return sorted.firstWhere((l) => l.active, orElse: () => sorted.first).code;
}
