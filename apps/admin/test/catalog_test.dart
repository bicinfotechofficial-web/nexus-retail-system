import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/catalog/catalog_providers.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

Future<void> _openCatalog(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await tester.tap(find.text('Catalog'));
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  group('approval queue', () {
    testWidgets('approving a suggestion sets the price and makes it active', (
      tester,
    ) async {
      await _openCatalog(tester, backend);
      expect(find.text('Approval queue (2)'), findsOneWidget);

      await _tapTab(tester, 'tab-approvals');
      expect(find.byKey(const ValueKey('pending-sugplum')), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-sugpudding')), findsOneWidget);
      expect(find.textContaining('MNJ · proposed ₹420.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('approve-sugplum')));
      await tester.pumpAndSettle();
      // The proposed price is the starting point.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('approve-price')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '420.00',
      );
      await tester.enterText(find.byKey(const Key('approve-price')), '450');
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();

      final plum = backend.catalog.byId('sugplum')!;
      expect(plum.status, ProductStatus.active);
      expect(plum.price, Money.rupees(450));
      expect(plum.isSellableAt('MNJ'), isTrue);
      expect(plum.isSellableAt('PTB'), isFalse);
      expect(backend.audit.actions, [AuditAction.productApprove]);

      expect(find.byKey(const ValueKey('pending-sugplum')), findsNothing);
      expect(find.text('Approval queue (1)'), findsOneWidget);
      expect(find.text('Plum Cake 500 g is approved.'), findsOneWidget);
    });

    testWidgets('approval needs a price above zero', (tester) async {
      await _openCatalog(tester, backend);
      await _tapTab(tester, 'tab-approvals');
      await tester.tap(find.byKey(const Key('approve-sugpudding')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('approve-price')), '0');
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a price above ₹0'), findsOneWidget);
      expect(backend.catalog.byId('sugpudding')!.status, ProductStatus.pending);
    });

    testWidgets('rejecting asks first, then deactivates the suggestion', (
      tester,
    ) async {
      await _openCatalog(tester, backend);
      await _tapTab(tester, 'tab-approvals');

      await tester.tap(find.byKey(const Key('reject-sugpudding')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-cancel')));
      await tester.pumpAndSettle();
      expect(backend.catalog.byId('sugpudding')!.status, ProductStatus.pending);

      await tester.tap(find.byKey(const Key('reject-sugpudding')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await tester.pumpAndSettle();
      expect(
        backend.catalog.byId('sugpudding')!.status,
        ProductStatus.inactive,
      );
      expect(backend.catalog.byId('sugpudding')!.price, isNull);
    });

    testWidgets('an empty queue says so', (tester) async {
      final empty = FakeBackend(
        auth: backend.auth,
        locations: backend.locations,
        summaries: backend.summaries,
        stock: backend.stock,
        catalog: FakeCatalogRepository(products: FakeBackend.seedProducts),
      );
      await _openCatalog(tester, empty);
      expect(find.text('Approval queue'), findsOneWidget);
      await _tapTab(tester, 'tab-approvals');
      expect(find.byKey(const Key('approvals-empty')), findsOneWidget);
    });
  });

  group('products', () {
    testWidgets('lists every status and filters by status, category, text', (
      tester,
    ) async {
      await _openCatalog(tester, backend);
      expect(find.text('11 of 11 products'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('status-fruitcake'))).data,
        'Inactive',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('price-sugplum'))).data,
        'proposed ₹420.00',
      );

      await tester.tap(find.byKey(const Key('filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending approval').last);
      await tester.pumpAndSettle();
      expect(find.text('2 of 11 products'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pastries').last);
      await tester.pumpAndSettle();
      expect(find.text('2 of 11 products'), findsOneWidget);
      expect(find.text('Chocolate Pastry'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('product-search')), 'choc');
      await tester.pumpAndSettle();
      expect(find.text('1 of 11 products'), findsOneWidget);
      expect(find.text('Pineapple Pastry'), findsNothing);
    });

    testWidgets('creates an active product with a safe ID', (tester) async {
      await _openCatalog(tester, backend);
      await tester.tap(find.byKey(const Key('product-add')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('product-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Enter a category'), findsOneWidget);
      expect(
        find.text('Enter a price above ₹0, e.g. 350 or 349.50'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('product-name')),
        'Butterscotch 1 kg',
      );
      await tester.enterText(
        find.byKey(const Key('product-category')),
        'Cakes',
      );
      await tester.enterText(find.byKey(const Key('product-price')), '720.50');
      await tester.tap(find.byKey(const Key('product-save')));
      await tester.pumpAndSettle();

      final created = backend.catalog.products.singleWhere(
        (p) => p.name == 'Butterscotch 1 kg',
      );
      expect(Ids.isSafeKey(created.id), isTrue);
      expect(created.price, const Money(72050));
      expect(created.status, ProductStatus.active);
      expect(created.scope, Product.globalScope);
      expect(created.createdBy, 'admin-0001');
      expect(find.text('12 of 12 products'), findsOneWidget);
      // A new product is not a price change.
      expect(backend.audit.actions, isEmpty);
    });

    testWidgets('editing the price warns that it is audited and saves it', (
      tester,
    ) async {
      await _openCatalog(tester, backend);
      await _tapVisible(tester, find.byKey(const Key('edit-bf1kg')));

      expect(find.byKey(const Key('price-change-note')), findsNothing);
      await tester.enterText(find.byKey(const Key('product-price')), '680');
      await tester.pump();
      expect(
        find.text(
          'Price change from ₹650.00. It is recorded in the audit log.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('product-save')));
      await tester.pumpAndSettle();

      final bf = backend.catalog.byId('bf1kg')!;
      expect(bf.price, Money.rupees(680));
      expect(bf.name, 'Black Forest 1 kg');
      expect(backend.audit.actions, [AuditAction.priceChange]);
      expect(
        tester.widget<Text>(find.byKey(const Key('price-bf1kg'))).data,
        '₹680.00',
      );
    });

    testWidgets('deactivates after confirmation and can reactivate', (
      tester,
    ) async {
      await _openCatalog(tester, backend);
      await _tapVisible(tester, find.byKey(const Key('deactivate-vegpuff')));
      expect(find.text('Deactivate Veg Puff?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await tester.pumpAndSettle();
      expect(backend.catalog.byId('vegpuff')!.status, ProductStatus.inactive);

      await _tapVisible(tester, find.byKey(const Key('reactivate-vegpuff')));
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await tester.pumpAndSettle();
      expect(backend.catalog.byId('vegpuff')!.status, ProductStatus.active);
      expect(backend.audit.actions, isEmpty);
    });
  });

  group('raw materials', () {
    testWidgets('lists and adds a raw material', (tester) async {
      await _openCatalog(tester, backend);
      await _tapTab(tester, 'tab-materials');
      expect(find.text('Whipping cream'), findsOneWidget);
      expect(find.text('Millilitres (ml)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('material-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('material-name')), 'Butter');
      await tester.tap(find.byKey(const Key('material-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grams (g)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('material-save')));
      await tester.pumpAndSettle();

      final butter = backend.catalog.materials.singleWhere(
        (m) => m.name == 'Butter',
      );
      expect(butter.unit, StockUnit.g);
      expect(find.text('Butter'), findsOneWidget);
    });

    testWidgets('refuses a duplicate name', (tester) async {
      await _openCatalog(tester, backend);
      await _tapTab(tester, 'tab-materials');
      await tester.tap(find.byKey(const Key('material-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('material-name')), 'flour');
      await tester.tap(find.byKey(const Key('material-save')));
      await tester.pumpAndSettle();
      expect(find.text('flour already exists.'), findsOneWidget);
      expect(backend.catalog.materials, hasLength(3));
    });
  });

  testWidgets('a Store Manager has no catalog entry and is refused there', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Catalog'), findsNothing);

    await goTo(tester, '/catalog');
    expect(find.byType(NotPermitted), findsOneWidget);
    expect(find.byKey(const Key('product-add')), findsNothing);
  });

  test('new product IDs are safe keys', () {
    for (var i = 0; i < 50; i++) {
      expect(Ids.isSafeKey(newProductId()), isTrue);
    }
    expect(parsePositiveMoney('1,200.50'), const Money(120050));
    expect(parsePositiveMoney('0'), isNull);
    expect(parsePositiveMoney('abc'), isNull);
    expect(parsePositiveMoney('-5'), isNull);
  });
}
