import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../repos/docs.dart';

// Unit tests with mocks. AD-4's own done-check, that the Admin stays signed
// in when a user is created through the secondary app, needs a run against
// the Auth emulator on a device or browser; the mocks can only show that
// the service never touches the Admin's instance.
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth adminAuth;
  late MockFirebaseAuth secondary;
  late FirestoreUserService service;
  var secondaryOpened = 0;
  final now = DateTime.utc(2026, 9, 26, 5, 30);

  setUp(() async {
    db = FakeFirebaseFirestore();
    adminAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'admin1', email: 'admin@example.com'),
    );
    secondary = MockFirebaseAuth();
    secondaryOpened = 0;
    service = FirestoreUserService(
      auth: adminAuth,
      firestore: db,
      secondaryAuth: () async {
        secondaryOpened++;
        return secondary;
      },
      clock: () => now,
    );
    await put(db, FirestorePaths.location('PTB'), location('PTB').toMap());
  });

  Future<AppUser> create({String email = ' New.SM@Example.com '}) =>
      service.createStoreManager(
        name: ' New SM ',
        email: email,
        password: 'secret1',
        locationId: 'PTB',
      );

  Future<Map<String, dynamic>?> doc(String path) async =>
      (await db.doc(path).get()).data();

  group('createStoreManager', () {
    test('creates the account on the secondary app, then the users doc '
        'and a USER_CREATE audit entry', () async {
      final u = await create();
      expect(secondaryOpened, 1);
      expect(adminAuth.currentUser!.uid, 'admin1', reason: 'Admin untouched');
      expect(secondary.currentUser, isNull, reason: 'secondary signed out');

      expect(u.email, 'new.sm@example.com');
      expect(u.name, 'New SM');
      final data = (await doc(FirestorePaths.user(u.uid)))!;
      expect(data, {
        'name': 'New SM',
        'email': 'new.sm@example.com',
        'roleId': SeedRoles.storeManagerId,
        'locationId': 'PTB',
        'active': true,
        'createdBy': 'admin1',
        'createdAt': isA<Timestamp>(),
      });
      expect(AppUser.fromMap(u.uid, plainFromFirestore(data)).active, isTrue);

      final auditId = 'PTB-USR-${u.uid}-${now.millisecondsSinceEpoch}';
      expect(FirestoreUserService.userAuditId('PTB', u.uid, now), auditId);
      final a = (await doc(FirestorePaths.audit(auditId)))!;
      expect(a.keys.toSet(), {
        'action',
        'entityPath',
        'locationId',
        'before',
        'after',
        'reason',
        'by',
        'deviceId',
        'clientAt',
        'at',
      });
      final entry = AuditEntry.fromMap(auditId, plainFromFirestore(a));
      expect(entry.action, AuditAction.userCreate);
      expect(entry.entityPath, 'users/${u.uid}');
      expect(entry.locationId, 'PTB');
      expect(entry.by, 'admin1');
      expect(entry.after!['email'], 'new.sm@example.com');
      expect(entry.clientAt.isAtSameMomentAs(now), isTrue);
    });

    for (final (code, detail) in [
      ('email-already-in-use', 'email already in use'),
      ('weak-password', 'weak password (at least 6 characters)'),
      ('invalid-email', 'not a valid email address'),
    ]) {
      test('$code is a ruleViolation and writes nothing', () async {
        whenCalling(
          Invocation.method(#createUserWithEmailAndPassword, null),
        ).on(secondary).thenThrow(FirebaseAuthException(code: code));
        await expectLater(
          create(),
          throwsA(
            isA<DataFailure>()
                .having((f) => f.reason, 'reason', FailureReason.ruleViolation)
                .having((f) => f.detail, 'detail', detail),
          ),
        );
        expect((await db.collection(FirestorePaths.users).get()).docs, isEmpty);
        expect(
          (await db.collection(FirestorePaths.auditLog).get()).docs,
          isEmpty,
        );
      });
    }

    test('no network is offline', () async {
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(secondary)
          .thenThrow(FirebaseAuthException(code: 'network-request-failed'));
      await expectLater(
        create(),
        throwsA(
          isA<DataFailure>().having(
            (f) => f.reason,
            'reason',
            FailureReason.offline,
          ),
        ),
      );
    });

    test('checks the name and location before creating anything', () async {
      await expectLater(
        service.createStoreManager(
          name: '  ',
          email: 'a@b.c',
          password: 'secret1',
          locationId: 'PTB',
        ),
        throwsA(isA<DataFailure>()),
      );
      await expectLater(
        service.createStoreManager(
          name: 'x',
          email: 'a@b.c',
          password: 'secret1',
          locationId: 'ptb',
        ),
        throwsA(isA<DataFailure>()),
      );
      expect(secondaryOpened, 0);
    });

    test('needs a signed-in Admin', () async {
      await adminAuth.signOut();
      await expectLater(
        create(),
        throwsA(
          isA<DataFailure>().having(
            (f) => f.reason,
            'reason',
            FailureReason.notPermitted,
          ),
        ),
      );
      expect(secondaryOpened, 0);
    });
  });

  group('setActive', () {
    setUp(() async {
      await put(
        db,
        FirestorePaths.user('sm1'),
        appUser('sm1').toMap(),
        serverTimes: {'createdAt': DateTime.utc(2026)},
      );
    });

    test('disabling sets active false with a USER_DISABLE entry', () async {
      await service.setActive('sm1', active: false);
      expect((await doc(FirestorePaths.user('sm1')))!['active'], false);
      final id = FirestoreUserService.userAuditId('PTB', 'sm1', now);
      final entry = AuditEntry.fromMap(
        id,
        plainFromFirestore((await doc(FirestorePaths.audit(id)))!),
      );
      expect(entry.action, AuditAction.userDisable);
      expect(entry.before, {'active': true});
      expect(entry.after, {'active': false});
      expect(entry.locationId, 'PTB');
      expect(entry.entityPath, 'users/sm1');
    });

    test(
      'enabling sets active true with a USER_ENABLE entry (QA-046)',
      () async {
        await db.doc(FirestorePaths.user('sm1')).update({'active': false});
        await service.setActive('sm1', active: true);
        expect((await doc(FirestorePaths.user('sm1')))!['active'], true);
        final id = FirestoreUserService.userAuditId('PTB', 'sm1', now);
        final entry = AuditEntry.fromMap(
          id,
          plainFromFirestore((await doc(FirestorePaths.audit(id)))!),
        );
        expect(entry.action, AuditAction.userEnable);
        expect(entry.before, {'active': false});
        expect(entry.after, {'active': true});
        expect(entry.locationId, 'PTB');
        expect(entry.by, isNotEmpty);
      },
    );

    test('the value it already has writes nothing', () async {
      await service.setActive('sm1', active: true);
      expect(
        (await db.collection(FirestorePaths.auditLog).get()).docs,
        isEmpty,
      );
    });

    test('a user without a location gets an unprefixed audit ID', () {
      expect(
        FirestoreUserService.userAuditId(null, 'admin2', now),
        'USR-admin2-${now.millisecondsSinceEpoch}',
      );
    });

    test('a missing user is notFound; the Admin themself is refused', () async {
      await expectLater(
        service.setActive('nobody', active: false),
        throwsA(
          isA<DataFailure>().having(
            (f) => f.reason,
            'reason',
            FailureReason.notFound,
          ),
        ),
      );
      await expectLater(
        service.setActive('admin1', active: false),
        throwsA(
          isA<DataFailure>().having(
            (f) => f.reason,
            'reason',
            FailureReason.ruleViolation,
          ),
        ),
      );
    });
  });
}
