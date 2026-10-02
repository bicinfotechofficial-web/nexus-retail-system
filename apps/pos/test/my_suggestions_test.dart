import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

/// POS-17: My suggestions, the dot and the banner for a decision (D-038).
const AppUser _admin = AppUser(
  uid: 'admin-1',
  name: 'Admin',
  email: 'admin@example.com',
  roleId: SeedRoles.adminId,
  locationId: null,
  active: true,
  createdBy: 'seed',
);

/// The Admin's side: approves or declines through the same fake catalog,
/// under its own login so the Store Manager's session isn't touched.
FakeCatalogService adminCatalog(FakeBackend b) => FakeCatalogService(
  auth: FakeAuthService(
    const SessionContext(
      user: _admin,
      role: Role(
        id: SeedRoles.adminId,
        name: 'Admin',
        permissions: SeedRoles.adminPermissions,
        allLocations: true,
      ),
      location: null,
    ),
  ),
  catalog: b.catalog,
  now: () => testNow,
);

/// The Store Manager suggests "Black Forest 1 kg" at ₹800.
Future<Product> suggestBlackForest(FakeBackend b) => b.catalogService.suggest(
  name: 'Black Forest 1 kg',
  category: 'Cakes',
  proposedPrice: const Money(80000),
);

Future<void> openMySuggestions(WidgetTester tester) async {
  await openNav(tester, 'Suggest special');
  await tapKey(tester, 'open-my-suggestions');
  expect(find.widgetWithText(AppBar, 'My suggestions'), findsOneWidget);
}

bool menuDot(WidgetTester tester) =>
    tester.widget<Badge>(find.byKey(const Key('decision-dot'))).isLabelVisible;

void main() {
  testWidgets('lists suggestions with Pending, Approved at and Not approved '
      'with the note', (tester) async {
    final b = fakeBackend();
    final bf = await suggestBlackForest(b);
    final choco = await b.catalogService.suggest(
      name: 'Choco Walnut Loaf',
      category: 'Cakes',
      proposedPrice: const Money(30000),
    );
    final admin = adminCatalog(b);
    await admin.approve(productId: bf.id, price: const Money(85000));
    await admin.decline(productId: choco.id, note: 'Too close to the brownie');
    await pumpPos(tester, backend: b);
    await openMySuggestions(tester);

    // Pending: the seeded Jackfruit Cake.
    expect(textOf(tester, 'suggestion-status-jack-cake'), 'Pending');
    expect(textOf(tester, 'suggestion-status-${bf.id}'), 'Approved at ₹850');
    expect(textOf(tester, 'suggestion-status-${choco.id}'), 'Not approved');
    expect(
      textOf(tester, 'suggestion-note-${choco.id}'),
      'Too close to the brownie',
    );
    expect(find.byKey(const Key('suggestion-note-jack-cake')), findsNothing);
  });

  testWidgets("only the signed-in user's own suggestions are listed", (
    tester,
  ) async {
    final b = fakeBackend();
    b.catalog.products = [
      ...b.catalog.products,
      const Product(
        id: 'someone-elses',
        name: 'Another Manager Cake',
        category: 'Cakes',
        scope: Seed.locationId,
        status: ProductStatus.pending,
        sortOrder: 2000,
        createdBy: 'other-manager',
        proposedPrice: Money(40000),
      ),
    ];
    await pumpPos(tester, backend: b);
    await openMySuggestions(tester);
    expect(find.text('Jackfruit Cake 500 g'), findsOneWidget);
    expect(find.text('Another Manager Cake'), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    final b = fakeBackend();
    b.catalog.products = [
      for (final p in b.catalog.products)
        if (p.createdBy != Seed.userId) p,
    ];
    await pumpPos(tester, backend: b);
    await openMySuggestions(tester);
    expect(find.byKey(const Key('no-suggestions')), findsOneWidget);
  });

  testWidgets('a decision while the app is open shows the banner and the dot, '
      'and opening the list clears the dot', (tester) async {
    final b = fakeBackend();
    final bf = await suggestBlackForest(b);
    await pumpPos(tester, backend: b);
    // Pending only: no dot, no banner.
    expect(menuDot(tester), isFalse);
    expect(find.byKey(const Key('decision-banner')), findsNothing);

    await adminCatalog(b).approve(productId: bf.id, price: const Money(85000));
    await tester.pumpAndSettle();
    expect(find.text('Black Forest 1 kg was approved at ₹850'), findsOneWidget);
    expect(menuDot(tester), isTrue);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'suggestions-badge'), '1');
    await tester.tap(find.byKey(const Key('nav-Suggest special')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'my-suggestions-badge'), '1');

    await tapKey(tester, 'open-my-suggestions');
    expect(find.byKey(Key('suggestion-new-${bf.id}')), findsOneWidget);
    // Seen now: the dot is gone, but the New mark stays while on the page.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-suggestions-badge')), findsNothing);
    expect(menuDot(tester), isFalse);
  });

  testWidgets('a declined suggestion reads as not approved in the banner', (
    tester,
  ) async {
    final b = fakeBackend();
    final bf = await suggestBlackForest(b);
    await pumpPos(tester, backend: b);
    await adminCatalog(b).decline(productId: bf.id, note: 'Not this season');
    await tester.pumpAndSettle();
    expect(find.text('Black Forest 1 kg was not approved'), findsOneWidget);
    expect(menuDot(tester), isTrue);
  });

  testWidgets('a decision that arrived while closed shows at the next open, '
      'once the list was opened it does not come back', (tester) async {
    final phone = MemoryPhoneStore();
    final b = fakeBackend(phoneStore: phone);
    final bf = await suggestBlackForest(b);
    await adminCatalog(b).approve(productId: bf.id, price: const Money(85000));

    // The app opens with the decision already there.
    await pumpPos(tester, backend: b);
    expect(find.text('Black Forest 1 kg was approved at ₹850'), findsOneWidget);
    expect(menuDot(tester), isTrue);

    // Not looked at: a restart shows it again.
    await tester.pumpWidget(const SizedBox());
    final again = fakeBackend(phoneStore: phone);
    again.catalog.products = b.catalog.products;
    await pumpPos(tester, backend: again);
    expect(find.byKey(const Key('decision-banner')), findsOneWidget);

    // Open the list: it is remembered per user on the phone.
    await openMySuggestions(tester);
    expect(phone.values['seenSuggestions.${Seed.userId}'], [
      '${bf.id}:approved',
    ]);
    await tester.pumpWidget(const SizedBox());
    final third = fakeBackend(phoneStore: phone);
    third.catalog.products = b.catalog.products;
    await pumpPos(tester, backend: third);
    expect(find.byKey(const Key('decision-banner')), findsNothing);
    expect(menuDot(tester), isFalse);
  });

  testWidgets('several decisions are summed up in one banner', (tester) async {
    final b = fakeBackend();
    final one = await suggestBlackForest(b);
    final two = await b.catalogService.suggest(
      name: 'Lemon Drizzle',
      category: 'Cakes',
      proposedPrice: const Money(35000),
    );
    final admin = adminCatalog(b);
    await admin.approve(productId: one.id, price: const Money(85000));
    await admin.decline(productId: two.id, note: 'No');
    await pumpPos(tester, backend: b);
    expect(
      find.text('2 of your suggestions have been decided'),
      findsOneWidget,
    );
    await tapKey(tester, 'decision-banner-view');
    expect(find.widgetWithText(AppBar, 'My suggestions'), findsOneWidget);
  });

  testWidgets('a role without catalog.suggest gets no dot or banner', (
    tester,
  ) async {
    final b = fakeBackend(
      session: sessionWith([Permission.billCreate, Permission.stockMove]),
    );
    await pumpPos(tester, backend: b);
    expect(menuDot(tester), isFalse);
    expect(find.byKey(const Key('decision-banner')), findsNothing);
  });
}
