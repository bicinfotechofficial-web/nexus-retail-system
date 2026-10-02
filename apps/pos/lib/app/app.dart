import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/suggest/decision_banner.dart';
import 'router.dart';
import 'theme.dart';

class PosApp extends ConsumerWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Caramel Cottage POS',
      debugShowCheckedModeBanner: false,
      theme: PosTheme.light(),
      scaffoldMessengerKey: ref.watch(messengerKeyProvider),
      builder: (context, child) =>
          DecisionBannerHost(child: child ?? const SizedBox.shrink()),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
