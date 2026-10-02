import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/phone_store.dart';
import '../../app/providers.dart';

/// Where a suggestion stands (D-008, D-038).
enum SuggestionStatus { pending, approved, declined }

SuggestionStatus statusOf(Product p) {
  if (p.wasDeclined) return SuggestionStatus.declined;
  if (p.status == ProductStatus.active ||
      (p.price != null && p.reviewedBy != null)) {
    return SuggestionStatus.approved;
  }
  return SuggestionStatus.pending;
}

/// What the manager has been told about one suggestion: the product and its
/// decision, so a decision that changes is new again.
String decisionToken(Product p) => '${p.id}:${statusOf(p).name}';

/// `₹850` for whole rupees, `₹850.50` otherwise.
String rupees(Money m) {
  final text = m.format();
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

/// The signed-in Store Manager's suggestions at their location, newest
/// first. Served from the cache offline.
final mySuggestionsProvider = StreamProvider<List<Product>>((ref) {
  final loc = ref.watch(locationCodeProvider);
  final uid = ref.watch(uidProvider);
  final canSuggest =
      ref.watch(
        sessionProvider.select((s) => s.value?.can(Permission.catalogSuggest)),
      ) ??
      false;
  if (loc == null || uid == null || !canSuggest) return Stream.value(const []);
  return ref.watch(catalogRepositoryProvider).watchMySuggestions(loc, uid);
});

/// The decisions this phone has already shown the signed-in user, kept per
/// user on the phone (D-038: "last seen" is local).
class SeenDecisionsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final uid = ref.watch(uidProvider);
    if (uid == null) return const {};
    try {
      final saved = await ref
          .read(phoneStoreProvider)
          .getStringList(PhoneKeys.seenSuggestions(uid));
      return {...?saved};
    } on Object {
      return const {};
    }
  }

  Future<void> markSeen(Iterable<String> tokens) async {
    final uid = ref.read(uidProvider);
    final before = state.value;
    if (uid == null || before == null) return;
    final next = {...before, ...tokens};
    if (next.length == before.length) return;
    state = AsyncData(next);
    try {
      await ref
          .read(phoneStoreProvider)
          .setStringList(PhoneKeys.seenSuggestions(uid), next.toList()..sort());
    } on Object {
      // Held in memory until the app closes.
    }
  }
}

final seenDecisionsProvider =
    AsyncNotifierProvider<SeenDecisionsNotifier, Set<String>>(
      SeenDecisionsNotifier.new,
    );

/// Decisions (approved or declined) the manager hasn't seen yet. Empty
/// until the saved "seen" set has loaded, so nothing flashes by mistake.
final unseenDecisionsProvider = Provider<List<Product>>((ref) {
  final seen = ref.watch(seenDecisionsProvider).value;
  final mine = ref.watch(mySuggestionsProvider).value;
  if (seen == null || mine == null) return const [];
  return [
    for (final p in mine)
      if (statusOf(p) != SuggestionStatus.pending &&
          !seen.contains(decisionToken(p)))
        p,
  ];
});

/// The sentence for the banner.
String decisionSentence(Product p) => switch (statusOf(p)) {
  SuggestionStatus.approved =>
    '${p.name} was approved at ${rupees(p.price ?? Money.zero)}',
  SuggestionStatus.declined => '${p.name} was not approved',
  SuggestionStatus.pending => '${p.name} is waiting for approval',
};
