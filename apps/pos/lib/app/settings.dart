import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'phone_store.dart';
import 'providers.dart';

/// Review bill before saving (D-035). On by default, kept on this phone for
/// the signed-in user, so it survives a restart. Until it has loaded the
/// answer is the default, which is the safe one.
class ReviewBeforeSaveNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final uid = ref.watch(uidProvider);
    if (uid == null) return true;
    try {
      return await ref
              .read(phoneStoreProvider)
              .getBool(PhoneKeys.reviewBeforeSave(uid)) ??
          true;
    } on Object {
      return true;
    }
  }

  Future<void> set(bool value) async {
    final uid = ref.read(uidProvider);
    if (uid == null) return;
    state = AsyncData(value);
    try {
      await ref
          .read(phoneStoreProvider)
          .setBool(PhoneKeys.reviewBeforeSave(uid), value);
    } on Object {
      // The choice still holds until the app closes.
    }
  }
}

final reviewBeforeSaveProvider =
    AsyncNotifierProvider<ReviewBeforeSaveNotifier, bool>(
      ReviewBeforeSaveNotifier.new,
    );

/// Whether the review step is on right now (the default until loaded).
bool reviewIsOn(WidgetRef ref) =>
    ref.watch(reviewBeforeSaveProvider).value ?? true;
