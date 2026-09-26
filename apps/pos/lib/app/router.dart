import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../features/billing/billing_screen.dart';
import '../features/bills/bill_detail_screen.dart';
import '../features/bills/bills_screen.dart';
import '../features/payment/bill_saved_screen.dart';
import '../features/payment/payment_screen.dart';
import '../features/placeholder_screen.dart';
import '../features/returns/return_screen.dart';
import '../features/summary/day_summary_screen.dart';
import 'destinations.dart';
import 'providers.dart';

abstract final class Routes {
  static const String starting = '/starting';
  static const String signedOut = '/signed-out';
  static const String noAccess = '/no-access';
  static const String payment = '/payment';
  static const String billSaved = '/bill-saved';

  /// `/bills/D01-000123`: one bill, with reprint, cancel and return.
  static String bill(String billId) => '${Destinations.bills.path}/$billId';

  /// `/bills/D01-000123/return`.
  static String billReturn(String billId) => '${bill(billId)}/return';

  static final RegExp _billPath = RegExp(r'^/bills/[^/]+$');
  static final RegExp _returnPath = RegExp(r'^/bills/[^/]+/return$');

  /// Pages that aren't drawer destinations, with the permissions that open
  /// them (any one of).
  static const Map<String, List<String>> _extra = {
    payment: [Permission.billCreate],
    billSaved: [Permission.billCreate],
  };

  static const Set<String> _open = {starting, signedOut, noAccess};

  /// Where [session] may go instead of [path], or null to stay. Pure, so
  /// the permission rules are tested without a widget tree.
  static String? redirect(AsyncValue<SessionContext?> session, String path) {
    if (!session.hasValue) {
      return path == starting ? null : starting;
    }
    final s = session.value;
    if (s == null) return path == signedOut ? null : signedOut;

    final allowed = Destinations.allowedFor(s);
    final home = allowed.isEmpty ? noAccess : allowed.first.path;
    if (_open.contains(path)) return path == home ? null : home;

    final needs =
        _extra[path] ??
        (_returnPath.hasMatch(path) ? const [Permission.returnCreate] : null) ??
        (_billPath.hasMatch(path) ? Destinations.bills.anyOf : null) ??
        Destinations.all
            .where((d) => d.path == path)
            .map((d) => d.anyOf)
            .firstOrNull;
    if (needs != null && !needs.any(s.can)) return home;
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Destinations.billing.path,
    redirect: (context, state) =>
        Routes.redirect(ref.read(sessionProvider), state.uri.path),
    routes: [
      GoRoute(
        path: Destinations.billing.path,
        builder: (context, state) => const BillingScreen(),
      ),
      GoRoute(
        path: Routes.payment,
        builder: (context, state) => const PaymentScreen(),
      ),
      GoRoute(
        path: Routes.billSaved,
        redirect: (context, state) =>
            state.extra is Bill ? null : Destinations.billing.path,
        builder: (context, state) =>
            BillSavedScreen(bill: state.extra! as Bill),
      ),
      GoRoute(
        path: Destinations.bills.path,
        builder: (context, state) => const BillsScreen(),
        routes: [
          GoRoute(
            path: ':billId',
            builder: (context, state) =>
                BillDetailScreen(billId: state.pathParameters['billId']!),
            routes: [
              GoRoute(
                path: 'return',
                builder: (context, state) =>
                    ReturnScreen(billId: state.pathParameters['billId']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Destinations.stock.path,
        builder: (context, state) =>
            const PlaceholderScreen(title: 'Stock', task: 'POS-9'),
      ),
      GoRoute(
        path: Destinations.summary.path,
        builder: (context, state) => const DaySummaryScreen(),
      ),
      GoRoute(
        path: Routes.starting,
        builder: (context, state) => Consumer(
          builder: (context, ref, _) {
            final session = ref.watch(sessionProvider);
            return session.hasError
                ? MessageScreen(message: "Couldn't start: ${session.error}")
                : const MessageScreen(message: 'Starting…', busy: true);
          },
        ),
      ),
      GoRoute(
        path: Routes.signedOut,
        builder: (context, state) => const MessageScreen(
          message: 'Signed out. Sign-in arrives in POS-2.',
        ),
      ),
      GoRoute(
        path: Routes.noAccess,
        builder: (context, state) => const MessageScreen(
          message:
              "This login can't use any POS screens. Ask the Admin to check "
              'its role.',
        ),
      ),
    ],
  );
  ref.listen(sessionProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});
