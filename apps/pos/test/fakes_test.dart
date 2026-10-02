import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

/// The fakes keep the same promises as the real services, so a FAKE_DATA
/// run and the widget tests behave like the real thing.
void main() {
  test(
    'createBill creates the customer, then only counts later bills',
    () async {
      final b = fakeBackend();
      final first = await addBill(b, {'bf-500': 1});
      await addBill(b, {'veg-puff': 2});
      await addBill(b, {
        'veg-puff': 1,
      }, customer: testCustomer(name: 'Sample Buyer', whatsapp: null));

      final all = b.customers.all('PTB');
      expect(all, hasLength(2));
      final test = all.firstWhere((c) => c.name == 'Test Customer');
      expect(test.id, CustomerId.of('9876543210', 'Test Customer'));
      expect(test.billCount, 2);
      expect(test.totalSpend, const Money(45000 + 5000));
      expect(test.lastWriteRef, 'D01-000002');
      expect(first.customer?.name, 'Test Customer');
      // Same mobile, another name: another customer (D-037).
      expect(all.map((c) => c.phone).toSet(), {'9876543210'});

      expect(await b.customers.watchByPhone('PTB', '987').first, hasLength(2));
      expect(await b.customers.watchByPhone('PTB', '912').first, isEmpty);
      expect(await b.customers.watchByPhone('MNJ', '987').first, isEmpty);
      expect(await b.customers.watchAll('PTB').first, hasLength(2));
      expect(await b.customers.watchAllLocations().first, hasLength(2));
    },
  );

  test('approve and decline record the reviewer, and watchMySuggestions '
      'follows them', () async {
    final b = fakeBackend();
    final mine = await b.catalogService.suggest(
      name: 'Lemon Drizzle',
      category: 'Cakes',
      proposedPrice: const Money(35000),
    );
    final other = await b.catalogService.suggest(
      name: 'Date Loaf',
      category: 'Cakes',
      proposedPrice: const Money(25000),
    );
    // Without catalog.manage a Store Manager can't decide.
    await expectLater(
      b.catalogService.approve(productId: mine.id, price: const Money(1)),
      throwsA(isA<DataFailure>()),
    );

    final admin = FakeCatalogService(
      auth: FakeAuthService(
        const SessionContext(
          user: AppUser(
            uid: 'admin-1',
            name: 'Admin',
            email: 'a@example.com',
            roleId: SeedRoles.adminId,
            locationId: null,
            active: true,
            createdBy: 'seed',
          ),
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
    final approved = await admin.approve(
      productId: mine.id,
      price: const Money(36000),
    );
    expect(approved.status, ProductStatus.active);
    expect(approved.reviewedBy, 'admin-1');
    expect(approved.reviewedAt, testNow);
    final declined = await admin.decline(productId: other.id, note: 'No');
    expect(declined.wasDeclined, isTrue);
    expect(declined.reviewNote, 'No');
    await expectLater(
      admin.decline(productId: other.id, note: ' '),
      throwsA(isA<DataFailure>()),
    );

    final listed = await b.catalog.watchMySuggestions('PTB', Seed.userId).first;
    expect(
      listed.map((p) => p.name),
      containsAll(['Lemon Drizzle', 'Date Loaf']),
    );
    expect(await b.catalog.watchMySuggestions('PTB', 'nobody').first, isEmpty);
    expect(
      await b.catalog.watchMySuggestions('MNJ', Seed.userId).first,
      isEmpty,
    );
  });

  test('watchMovements returns one location and day, newest first', () async {
    final clock = TestClock();
    final b = fakeBackend(clock: clock);
    await b.stock.stockIn(const [StockLineInput(itemKey: 'RM_butter', qty: 1)]);
    clock.advance(const Duration(hours: 1));
    await b.stock.stockOutRaw(const [
      StockLineInput(itemKey: 'RM_butter', qty: 1),
    ], reason: 'Test');
    clock.advance(const Duration(days: 1));
    await b.stock.stockIn(const [StockLineInput(itemKey: 'RM_butter', qty: 2)]);

    final day = await b.stock.watchMovements('PTB', '2026-09-26').first;
    expect(day.map((m) => m.type), [
      MovementType.stockOutRaw,
      MovementType.stockIn,
    ]);
    expect(
      await b.stock.watchMovements('PTB', '2026-09-27').first,
      hasLength(1),
    );
    expect(await b.stock.watchMovements('MNJ', '2026-09-26').first, isEmpty);
  });

  test('the demo bills carry made-up customers', () async {
    final b = fakeBackend();
    await b.seedDemo();
    final bills = b.bills.all('PTB');
    expect(bills, isNotEmpty);
    expect(bills.every((x) => x.customer != null), isTrue);
    expect(b.customers.all('PTB'), isNotEmpty);
  });

  test(
    'MemoryPhoneStore keeps lists apart from what the caller holds',
    () async {
      final store = MemoryPhoneStore();
      final list = ['a'];
      await store.setStringList('k', list);
      list.add('b');
      expect(await store.getStringList('k'), ['a']);
      expect(await store.getBool('missing'), isNull);
    },
  );
}
