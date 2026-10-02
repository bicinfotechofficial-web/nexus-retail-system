import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import 'decisions.dart';

/// The messenger the whole app shows banners through, so a decision shows
/// up on whatever screen is open (D-038).
final messengerKeyProvider = Provider<GlobalKey<ScaffoldMessengerState>>(
  (ref) => GlobalKey<ScaffoldMessengerState>(),
);

/// Shows "Black Forest 1 kg was approved at ₹850" once per decision per app
/// run: when one arrives while the app is open, and at the next open for
/// the ones that came in while it was closed. The dot on the menu stays
/// until the list has been opened.
class DecisionBannerHost extends ConsumerStatefulWidget {
  const DecisionBannerHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DecisionBannerHost> createState() => _DecisionBannerHostState();
}

class _DecisionBannerHostState extends ConsumerState<DecisionBannerHost> {
  final Set<String> _announced = {};

  @override
  void initState() {
    super.initState();
    ref.listenManual(unseenDecisionsProvider, (_, next) {
      final fresh = [
        for (final p in next)
          if (!_announced.contains(decisionToken(p))) p,
      ];
      if (fresh.isEmpty) return;
      _announced.addAll(fresh.map(decisionToken));
      final text = fresh.length == 1
          ? decisionSentence(fresh.single)
          : '${fresh.length} of your suggestions have been decided';
      // After this frame: the messenger can't be changed while building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(messengerKeyProvider).currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('decision-banner'),
              content: Text(text),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                key: const Key('decision-banner-view'),
                label: 'View',
                onPressed: () =>
                    ref.read(routerProvider).push(Routes.mySuggestions),
              ),
            ),
          );
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
