import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../repos/docs.dart';

void main() {
  final t = DateTime.utc(2026, 9, 25, 18, 29, 59, 123, 456);

  group('plainFromFirestore', () {
    test('turns Timestamps into DateTimes at any depth', () {
      final out = plainFromFirestore({
        'at': Timestamp.fromDate(t),
        'cancel': {'at': Timestamp.fromDate(t), 'reason': 'x'},
        'list': [
          Timestamp.fromDate(t),
          {
            'nested': [Timestamp.fromDate(t)],
          },
        ],
      });
      expect((out['at']! as DateTime).isAtSameMomentAs(t), isTrue);
      final cancel = out['cancel']! as Map<String, Object?>;
      expect((cancel['at']! as DateTime).isAtSameMomentAs(t), isTrue);
      expect(cancel['reason'], 'x');
      final list = out['list']! as List<Object?>;
      expect((list[0]! as DateTime).isAtSameMomentAs(t), isTrue);
      final nested =
          ((list[1]! as Map<String, Object?>)['nested']! as List<Object?>)
              .single;
      expect(nested, isA<DateTime>());
    });

    test('keeps microseconds', () {
      final out = plainFromFirestore({'at': Timestamp.fromDate(t)});
      expect((out['at']! as DateTime).toUtc(), t);
    });

    test('turns whole doubles into ints and leaves the rest alone', () {
      final out = plainFromFirestore({
        'whole': 500.0,
        'fraction': 1.5,
        'int': 7,
        'negative': -300.0,
        'null': null,
        'bool': true,
        'string': '2026-09-25',
      });
      expect(out['whole'], isA<int>());
      expect(out['whole'], 500);
      expect(out['negative'], -300);
      expect(out['fraction'], 1.5);
      expect(out['int'], 7);
      expect(out.containsKey('null'), isTrue);
      expect(out['null'], isNull);
      expect(out['bool'], true);
      expect(out['string'], '2026-09-25');
    });

    group('pending server timestamps', () {
      final now = DateTime.utc(2026, 9, 26, 10);
      final data = <String, dynamic>{
        'serverCreatedAt': null,
        'reason': null,
        'clientCreatedAt': Timestamp.fromDate(t),
      };

      test('are estimated from the clock while the doc has pending writes', () {
        final out = plainFromFirestore(
          data,
          serverTimestampFields: const {'serverCreatedAt'},
          hasPendingWrites: true,
          now: () => now,
        );
        expect(out['serverCreatedAt'], now);
        expect(out['reason'], isNull, reason: 'not a server timestamp field');
      });

      test('stay null on a synced doc, where they are really unset', () {
        final out = plainFromFirestore(
          data,
          serverTimestampFields: const {'serverCreatedAt'},
          now: () => now,
        );
        expect(out['serverCreatedAt'], isNull);
      });

      test('keep a value the server already confirmed', () {
        final out = plainFromFirestore(
          {'serverCreatedAt': Timestamp.fromDate(t)},
          serverTimestampFields: const {'serverCreatedAt'},
          hasPendingWrites: true,
          now: () => now,
        );
        expect((out['serverCreatedAt']! as DateTime).toUtc(), t);
      });

      test('are not added when the field is absent', () {
        final out = plainFromFirestore(
          const {'x': 1},
          serverTimestampFields: const {'serverCreatedAt'},
          hasPendingWrites: true,
          now: () => now,
        );
        expect(out.containsKey('serverCreatedAt'), isFalse);
      });
    });

    test('a stored bill reads back through Bill.fromMap', () {
      final b = bill('PTB', 'D01', 123, t);
      final withCancel = Bill.fromMap(b.id, {
        ...b.toMap(),
        'status': 'CANCELLED',
        'cancel': BillCancel(
          reason: 'Wrong item',
          by: 'sm1',
          at: t,
          businessDate: b.businessDate,
        ).toMap(),
      });
      final data = stored(
        withCancel.toMap(),
        serverTimes: {'serverCreatedAt': t},
      );
      final back = Bill.fromMap(b.id, plainFromFirestore(data));
      expect(back.billNo, 'PTB-D01-000123');
      expect(back.clientCreatedAt.isAtSameMomentAs(t), isTrue);
      expect(back.serverCreatedAt!.isAtSameMomentAs(t), isTrue);
      expect(back.cancel!.at.isAtSameMomentAs(t), isTrue);
      expect(back.businessDate, '2026-09-25');
      expect(back.total, const Money(80000));
    });
  });

  group('modelOrNull and modelsOf', () {
    test('read docs and return null for a missing one', () async {
      final db = FakeFirebaseFirestore();
      final u = appUser('sm1');
      await put(
        db,
        FirestorePaths.user('sm1'),
        u.toMap(),
        serverTimes: {'createdAt': t},
      );
      final got = modelOrNull(
        await db.doc(FirestorePaths.user('sm1')).get(),
        AppUser.fromMap,
      );
      expect(got!.uid, 'sm1');
      expect(got.createdAt!.isAtSameMomentAs(t), isTrue);
      expect(
        modelOrNull(
          await db.doc(FirestorePaths.user('nobody')).get(),
          AppUser.fromMap,
        ),
        isNull,
      );
      final all = modelsOf(
        await db.collection(FirestorePaths.users).get(),
        AppUser.fromMap,
      );
      expect(all.map((u) => u.uid), ['sm1']);
    });

    test('a malformed doc fails loudly with its context', () async {
      final db = FakeFirebaseFirestore();
      await db.doc(FirestorePaths.user('bad')).set({'name': 'x'});
      expect(
        () async => modelOrNull(
          await db.doc(FirestorePaths.user('bad')).get(),
          AppUser.fromMap,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('user bad'),
          ),
        ),
      );
    });
  });

  group('failureFromFirestore', () {
    DataFailure f(String code) => failureFromFirestore(
      FirebaseException(plugin: 'cloud_firestore', code: code),
    );

    test('maps error codes to reasons', () {
      expect(f('permission-denied').reason, FailureReason.notPermitted);
      expect(f('unavailable').reason, FailureReason.offline);
      expect(f('not-found').reason, FailureReason.notFound);
      expect(f('internal').reason, FailureReason.unknown);
    });
  });
}
