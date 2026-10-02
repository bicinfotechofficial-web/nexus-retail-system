import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'docs.dart';

void main() {
  final at = DateTime.utc(2026, 9, 1, 10);

  group('FirestoreCustomerRepository', () {
    late FakeFirebaseFirestore db;
    late FirestoreCustomerRepository repo;

    /// A customer record as a bill's batch leaves it.
    Future<Customer> putCustomer(
      String loc,
      String name,
      String phone, {
      DateTime? lastBillAt,
      int bills = 1,
      int spend = 63100,
    }) async {
      final who = BillCustomer(name: name, phone: phone);
      final c = Customer(
        id: who.id,
        name: who.name,
        phone: who.phone,
        billCount: bills,
        totalSpend: Money(spend),
        lastWriteRef: 'D01-000001',
      );
      await put(
        db,
        customerPath(loc, c.id),
        c.toMap(),
        serverTimes: {'lastBillAt': ?lastBillAt},
      );
      return c;
    }

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestoreCustomerRepository(db);
    });

    test(
      'the customer converter reads the stored shape and its timestamp',
      () async {
        final c = await putCustomer(
          'PTB',
          'Test Customer',
          '9876543210',
          lastBillAt: at,
          bills: 3,
          spend: 190000,
        );
        final all = await repo.watchAll('PTB').first;
        expect(all, hasLength(1));
        expect(all.single.id, c.id);
        expect(all.single.name, 'Test Customer');
        expect(all.single.phone, '9876543210');
        expect(all.single.whatsapp, isNull);
        expect(all.single.billCount, 3);
        expect(all.single.totalSpend, const Money(190000));
        expect(all.single.lastWriteRef, 'D01-000001');
        expect(all.single.lastBillAt!.isAtSameMomentAs(at), isTrue);
      },
    );

    group('by phone prefix', () {
      setUp(() async {
        await putCustomer('PTB', 'Test Customer', '9876543210');
        await putCustomer('PTB', 'Another Customer', '9876543210');
        await putCustomer('PTB', 'Third Customer', '9876501234');
        await putCustomer('PTB', 'Fourth Customer', '9123456780');
        await putCustomer('MNJ', 'Other Store Customer', '9876543299');
      });

      test(
        'finds the saved names for a number, at this location only',
        () async {
          final r = await repo.watchByPhone('PTB', '98765432').first;
          expect(r.map((c) => c.name).toSet(), {
            'Test Customer',
            'Another Customer',
          });
          final wide = await repo.watchByPhone('PTB', '987').first;
          expect(wide, hasLength(3));
          expect(wide.every((c) => c.phone.startsWith('987')), isTrue);
          expect(
            (await repo.watchByPhone('PTB', '9876543210').first),
            hasLength(2),
          );
          expect(await repo.watchByPhone('PTB', '9876543211').first, isEmpty);
          expect(
            (await repo.watchByPhone('MNJ', '987').first).single.name,
            'Other Store Customer',
          );
        },
      );

      test('orders by phone', () async {
        final r = await repo.watchByPhone('PTB', '987').first;
        expect(r.map((c) => c.phone), [
          '9876501234',
          '9876543210',
          '9876543210',
        ]);
      });

      test('needs at least 3 digits, and only digits', () async {
        expect(await repo.watchByPhone('PTB', '').first, isEmpty);
        expect(await repo.watchByPhone('PTB', '98').first, isEmpty);
        expect(await repo.watchByPhone('PTB', ' 98 ').first, isEmpty);
        expect(await repo.watchByPhone('PTB', 'abc').first, isEmpty);
        expect(await repo.watchByPhone('PTB', '98x').first, isEmpty);
        expect((await repo.watchByPhone('PTB', ' 987 ').first), hasLength(3));
      });

      test('returns at most 10', () async {
        for (var i = 0; i < 15; i++) {
          await putCustomer('PTB', 'Bulk $i', '90000000${10 + i}');
        }
        final r = await repo.watchByPhone('PTB', '900').first;
        expect(r, hasLength(10));
      });

      test(
        'a customer saved by a new bill shows up in the open list',
        () async {
          final seen = <int>[];
          final sub = repo
              .watchByPhone('PTB', '999')
              .listen((l) => seen.add(l.length));
          await pumpEventQueue();
          await putCustomer('PTB', 'New Customer', '9990001111');
          await pumpEventQueue();
          await sub.cancel();
          expect(seen.first, 0);
          expect(seen.last, 1);
        },
      );
    });

    test(
      'all customers of a location, most recent bill first, limited',
      () async {
        await putCustomer('PTB', 'Oldest', '9000000001', lastBillAt: at);
        await putCustomer(
          'PTB',
          'Newest',
          '9000000002',
          lastBillAt: at.add(const Duration(days: 2)),
        );
        await putCustomer(
          'PTB',
          'Middle',
          '9000000003',
          lastBillAt: at.add(const Duration(days: 1)),
        );
        await putCustomer('MNJ', 'Elsewhere', '9000000004', lastBillAt: at);
        final all = await repo.watchAll('PTB').first;
        expect(all.map((c) => c.name), ['Newest', 'Middle', 'Oldest']);
        final two = await repo.watchAll('PTB', limit: 2).first;
        expect(two.map((c) => c.name), ['Newest', 'Middle']);
        expect(await repo.watchAll('KTL').first, isEmpty);
      },
    );

    test('every location at once, most recent bill first, limited', () async {
      await putCustomer('PTB', 'Oldest', '9000000001', lastBillAt: at);
      await putCustomer(
        'MNJ',
        'Newest',
        '9000000002',
        lastBillAt: at.add(const Duration(days: 2)),
      );
      await putCustomer(
        'PTB',
        'Middle',
        '9000000003',
        lastBillAt: at.add(const Duration(days: 1)),
      );
      final all = await repo.watchAllLocations().first;
      expect(all.map((c) => c.name), ['Newest', 'Middle', 'Oldest']);
      final one = await repo.watchAllLocations(limit: 1).first;
      expect(one.single.name, 'Newest');
    });

    test('a customer with no lastBillAt yet reads it as null', () async {
      // lastBillAt is a server timestamp, null until the server confirms it.
      // and estimated from the device clock while the write is pending.
      final who = BillCustomer(name: 'Pending Customer', phone: '9000000009');
      await db.doc(customerPath('PTB', who.id)).set({
        'name': who.name,
        'phone': who.phone,
        'whatsapp': null,
        'billCount': 1,
        'totalSpend': 63100,
        'lastWriteRef': 'D01-000002',
        'lastBillAt': null,
      });
      final r = await repo.watchAll('PTB').first;
      expect(r.single.lastBillAt, isNull);
    });
  });
}
