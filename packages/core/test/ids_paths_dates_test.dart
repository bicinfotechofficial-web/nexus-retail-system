import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

void main() {
  group('Ids', () {
    test('bill, movement and return IDs (D-003, D-024)', () {
      expect(Ids.billId('D01', 123), 'D01-000123');
      expect(Ids.billNo('PTB', 'D01-000123'), 'PTB-D01-000123');
      expect(Ids.movementId('D02', 42), 'D02-M000042');
      expect(Ids.returnId('D02', 7), 'D02-R000007');
      expect(Ids.saleMovementId('D01-000123'), 'D01-000123');
      expect(Ids.returnMovementId('D01-R000001'), 'D01-R000001');
      expect(Ids.cancelId('D01-000123'), 'D01-000123-X');
      expect(Ids.auditId('PTB', 'D01-000123-X'), 'PTB-D01-000123-X');
      expect(Ids.auditId('MNJ', 'D01-000123-X'), 'MNJ-D01-000123-X');
      expect(
        Ids.overrideAuditId(
          'PTB',
          'D02',
          DateTime.fromMillisecondsSinceEpoch(9, isUtc: true),
        ),
        'PTB-D02-OVR-9',
      );
      expect(Ids.deviceCode(1), 'D01');
      expect(Ids.deviceCode(99), 'D99');
      expect(Ids.rawItemKey('mix'), 'RM_mix');
      expect(Ids.finishedItemKey('bf1kg'), 'FG_bf1kg');
      expect(
        Ids.expenseAuditId(
          'e1',
          DateTime.fromMillisecondsSinceEpoch(5, isUtc: true),
        ),
        'EXP-e1-5',
      );
    });

    test('bill IDs sort in sequence order', () {
      final ids = [9, 10, 100, 1000].map((s) => Ids.billId('D01', s)).toList();
      expect([...ids]..sort(), ids);
    });

    test('rejects out-of-range numbers and bad codes', () {
      expect(() => Ids.billId('D01', 0), throwsRangeError);
      expect(() => Ids.billId('D01', 1000000), throwsRangeError);
      expect(() => Ids.deviceCode(0), throwsRangeError);
      expect(() => Ids.deviceCode(100), throwsRangeError);
      expect(() => Ids.billId('D1', 1), throwsArgumentError);
      expect(() => Ids.billNo('pt', 'D01-000001'), throwsArgumentError);
      expect(() => Ids.finishedItemKey('a.b'), throwsArgumentError);
    });

    test('validators', () {
      expect(Ids.isLocationCode('PTB'), isTrue);
      expect(Ids.isLocationCode('MN'), isTrue);
      expect(Ids.isLocationCode('ABCDE'), isFalse);
      expect(Ids.isLocationCode('ptb'), isFalse);
      expect(Ids.isDeviceCode('D07'), isTrue);
      expect(Ids.isDeviceCode('D7'), isFalse);
      expect(Ids.isSafeKey('bf_1kg-v2'), isTrue);
      for (final bad in ['', 'a.b', 'a/b', 'a b']) {
        expect(Ids.isSafeKey(bad), isFalse, reason: bad);
      }
    });
  });

  test('FirestorePaths', () {
    expect(FirestorePaths.role('ADMIN'), 'roles/ADMIN');
    expect(FirestorePaths.user('u1'), 'users/u1');
    expect(FirestorePaths.location('PTB'), 'locations/PTB');
    expect(FirestorePaths.device('PTB', 'D01'), 'locations/PTB/devices/D01');
    expect(FirestorePaths.stockItem('PTB', 'FG_x'), 'locations/PTB/stock/FG_x');
    expect(FirestorePaths.movement('PTB', 'M'), 'locations/PTB/movements/M');
    expect(FirestorePaths.bill('PTB', 'B'), 'locations/PTB/bills/B');
    expect(FirestorePaths.saleReturn('PTB', 'R'), 'locations/PTB/returns/R');
    expect(
      FirestorePaths.dailySummary('PTB', '2026-09-25'),
      'locations/PTB/dailySummary/2026-09-25',
    );
    expect(
      FirestorePaths.monthlySummary('PTB', '2026-09'),
      'locations/PTB/monthlySummary/2026-09',
    );
    expect(FirestorePaths.product('p'), 'products/p');
    expect(FirestorePaths.rawMaterial('m'), 'rawMaterials/m');
    expect(FirestorePaths.expense('e'), 'expenses/e');
    expect(FirestorePaths.audit('a'), 'auditLog/a');
  });

  group('BusinessDate (IST, D-022)', () {
    test('the day turns at 18:30 UTC', () {
      expect(
        BusinessDate.of(DateTime.utc(2026, 9, 25, 18, 29, 59)),
        '2026-09-25',
      );
      expect(BusinessDate.of(DateTime.utc(2026, 9, 25, 18, 30)), '2026-09-26');
      expect(BusinessDate.of(DateTime.utc(2026, 12, 31, 18, 30)), '2027-01-01');
    });

    test('does not depend on the device time zone', () {
      final instant = DateTime.utc(2026, 3, 1, 2);
      expect(BusinessDate.of(instant.toLocal()), BusinessDate.of(instant));
    });

    test('month and year keys', () {
      expect(BusinessDate.monthOf('2026-09-25'), '2026-09');
      expect(BusinessDate.yearOf('2026-09-25'), '2026');
      expect(() => BusinessDate.monthOf('2026-9-25'), throwsFormatException);
    });

    test('validation', () {
      expect(BusinessDate.isValid('2028-02-29'), isTrue);
      expect(BusinessDate.isValid('2026-02-29'), isFalse);
      expect(BusinessDate.isValid('2026-13-01'), isFalse);
      expect(BusinessDate.isValid('26-09-25'), isFalse);
      expect(BusinessDate.isValidMonth('2026-12'), isTrue);
      expect(BusinessDate.isValidMonth('2026-00'), isFalse);
      expect(BusinessDate.isValidMonth('2026-1'), isFalse);
    });

    test('startOf is IST midnight', () {
      expect(
        BusinessDate.startOf('2026-09-26'),
        DateTime.utc(2026, 9, 25, 18, 30),
      );
      expect(BusinessDate.of(BusinessDate.startOf('2026-09-26')), '2026-09-26');
    });

    test('addDays crosses months, years and leap days', () {
      expect(BusinessDate.addDays('2026-09-30', 1), '2026-10-01');
      expect(BusinessDate.addDays('2026-12-31', 1), '2027-01-01');
      expect(BusinessDate.addDays('2028-03-01', -1), '2028-02-29');
      expect(BusinessDate.addDays('2026-09-25', 0), '2026-09-25');
    });
  });

  group('permissions', () {
    test('the catalogue has 17 unique permissions', () {
      expect(Permission.all.toSet(), hasLength(17));
    });

    test('Admin has every permission; Store Manager matches the matrix', () {
      expect(SeedRoles.adminPermissions, Permission.all);
      expect(SeedRoles.storeManagerPermissions.toSet(), hasLength(11));
      expect(
        Permission.all.toSet().difference(
          SeedRoles.storeManagerPermissions.toSet(),
        ),
        {
          Permission.catalogManage,
          Permission.reportAll,
          Permission.expenseManage,
          Permission.auditView,
          Permission.userManage,
          Permission.locationManage,
        },
      );
    });
  });
}
