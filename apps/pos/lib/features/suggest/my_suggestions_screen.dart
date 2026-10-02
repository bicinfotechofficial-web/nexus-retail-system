import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../widgets/pos_scaffold.dart';
import 'decisions.dart';

/// The signed-in Store Manager's suggestions with the Admin's decisions
/// (POS-17, D-038). Opening it counts the decisions as seen, which clears
/// the dot on the menu; the ones that were new stay marked until you leave.
class MySuggestionsScreen extends ConsumerStatefulWidget {
  const MySuggestionsScreen({super.key});

  @override
  ConsumerState<MySuggestionsScreen> createState() =>
      _MySuggestionsScreenState();
}

class _MySuggestionsScreenState extends ConsumerState<MySuggestionsScreen> {
  /// Decisions that were unseen when they arrived or when this page opened.
  final Set<String> _fresh = {};

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(mySuggestionsProvider);
    final unseen = ref.watch(unseenDecisionsProvider);
    if (unseen.isNotEmpty) {
      final tokens = {for (final p in unseen) decisionToken(p)};
      _fresh.addAll(tokens);
      // Seen as soon as they are on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(seenDecisionsProvider.notifier).markSeen(tokens));
        }
      });
    }
    return PosScaffold(
      title: 'My suggestions',
      showDrawer: false,
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Text("Couldn't load your suggestions. Please try again."),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text(
                'You have not suggested anything yet.',
                key: Key('no-suggestions'),
              ),
            );
          }
          return ListView.separated(
            key: const Key('suggestion-list'),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) =>
                _SuggestionTile(product: list[i], isNew: _isNew(list[i])),
          );
        },
      ),
    );
  }

  bool _isNew(Product p) => _fresh.contains(decisionToken(p));
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.product, required this.isNew});

  final Product product;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = statusOf(product);
    final (label, color) = switch (status) {
      SuggestionStatus.pending => ('Pending', theme.colorScheme.outline),
      SuggestionStatus.approved => (
        'Approved at ${rupees(product.price ?? Money.zero)}',
        const Color(0xFF1E6B2A),
      ),
      SuggestionStatus.declined => ('Not approved', theme.colorScheme.error),
    };
    final note = product.reviewNote;
    return ListTile(
      key: Key('suggestion-${product.id}'),
      isThreeLine: status == SuggestionStatus.declined && note != null,
      title: Text(product.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              product.category,
              if (product.proposedPrice != null)
                'proposed ${rupees(product.proposedPrice!)}',
            ].join(' · '),
          ),
          if (status == SuggestionStatus.declined && note != null)
            Text(
              note,
              key: Key('suggestion-note-${product.id}'),
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Chip(
            key: Key('suggestion-status-${product.id}'),
            label: Text(label),
            side: BorderSide(color: color),
            labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
            visualDensity: VisualDensity.compact,
          ),
          if (isNew)
            Text(
              'New',
              key: Key('suggestion-new-${product.id}'),
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
        ],
      ),
    );
  }
}
