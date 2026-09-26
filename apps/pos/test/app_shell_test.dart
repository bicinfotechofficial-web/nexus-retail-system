import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/app/theme.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

void main() {
  group('app shell', () {
    testWidgets('starts on Billing with the caramel theme', (tester) async {
      await pumpPos(tester);
      expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).colorScheme.primary, PosTheme.caramel);
      expect(Theme.of(context).scaffoldBackgroundColor, PosTheme.cream);
      expect(Theme.of(context).useMaterial3, isTrue);
    });

    testWidgets('the sync chip follows SyncService.status', (tester) async {
      final b = await pumpPos(tester);
      expect(textOf(tester, 'sync-chip'), '● Online');

      b.sync.emit(const Syncing(3));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sync-chip'), '◐ Syncing (3)');

      b.sync.emit(Offline(DateTime(2026, 9, 26, 14, 5)));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sync-chip'), '○ Offline since 14:05');
    });

    testWidgets('the drawer lists every screen a Store Manager may use', (
      tester,
    ) async {
      await pumpPos(tester);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      for (final label in ['Billing', 'Bills', 'Stock', 'Day summary']) {
        expect(find.byKey(Key('nav-$label')), findsOneWidget, reason: label);
      }
      await tester.tap(find.byKey(const Key('nav-Stock')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Stock'), findsOneWidget);
    });

    testWidgets('the drawer hides screens the role has no permission for', (
      tester,
    ) async {
      await pumpPos(
        tester,
        backend: fakeBackend(
          session: sessionWith([Permission.billCreate, Permission.stockAdjust]),
        ),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-Billing')), findsOneWidget);
      expect(find.byKey(const Key('nav-Stock')), findsOneWidget);
      expect(find.byKey(const Key('nav-Bills')), findsNothing);
      expect(find.byKey(const Key('nav-Day summary')), findsNothing);
    });

    testWidgets('without bill.create, home is the first permitted screen', (
      tester,
    ) async {
      await pumpPos(
        tester,
        backend: fakeBackend(session: sessionWith([Permission.reportOwn])),
      );
      expect(find.widgetWithText(AppBar, 'Bills'), findsOneWidget);
      expect(find.byKey(const Key('search')), findsNothing);
    });

    testWidgets('a role with no POS permissions gets a clear message', (
      tester,
    ) async {
      await pumpPos(
        tester,
        backend: fakeBackend(session: sessionWith([Permission.catalogView])),
      );
      expect(find.textContaining("can't use any POS screens"), findsOneWidget);
    });

    testWidgets('signing out leaves the billing screen for sign-in', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      b.auth.current = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-email')), findsOneWidget);
    });
  });

  group('Routes.redirect', () {
    const sm = SessionContext(
      user: Seed.storeManager,
      role: Seed.storeManagerRole,
      location: Seed.location,
    );

    test('waits on the start page until the session loads', () {
      expect(Routes.redirect(const AsyncLoading(), '/'), Routes.starting);
      expect(Routes.redirect(const AsyncLoading(), Routes.starting), isNull);
    });

    test('lets a Store Manager open every screen', () {
      const s = AsyncData<SessionContext?>(sm);
      for (final p in ['/', '/bills', '/stock', '/summary', Routes.payment]) {
        expect(Routes.redirect(s, p), isNull, reason: p);
      }
      expect(Routes.redirect(s, Routes.starting), '/');
    });

    test('sends a user without bill.create away from payment', () {
      final s = AsyncData<SessionContext?>(sessionWith([Permission.stockMove]));
      expect(Routes.redirect(s, Routes.payment), '/stock');
      expect(Routes.redirect(s, '/'), '/stock');
    });

    test('a disabled user may open nothing', () {
      const disabled = SessionContext(
        user: AppUser(
          uid: 'u',
          name: 'Store Manager',
          email: 'x@example.com',
          roleId: SeedRoles.storeManagerId,
          locationId: Seed.locationId,
          active: false,
          createdBy: 'seed',
        ),
        role: Seed.storeManagerRole,
        location: Seed.location,
      );
      expect(Routes.redirect(const AsyncData(disabled), '/'), Routes.noAccess);
    });
  });
}
