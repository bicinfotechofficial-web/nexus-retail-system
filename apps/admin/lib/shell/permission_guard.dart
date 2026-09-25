import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_data/nexus_data.dart';

import '../data/providers.dart';

/// True when [session] holds at least one of [anyOf] (D-017: permissions,
/// never role names). An empty list allows every signed-in user.
bool hasAnyPermission(SessionContext? session, List<String> anyOf) {
  if (session == null) return false;
  return anyOf.isEmpty || anyOf.any(session.can);
}

/// Shows [child] only when the session has one of [anyOf]; otherwise a
/// "not permitted" message.
class PermissionGuard extends ConsumerWidget {
  const PermissionGuard({required this.anyOf, required this.child, super.key});

  final List<String> anyOf;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (hasAnyPermission(session, anyOf)) return child;
    return const NotPermitted();
  }
}

class NotPermitted extends StatelessWidget {
  const NotPermitted({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'You do not have permission to view this page.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
