import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../repos/docs.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late FirebaseAuthService service;

  final smRole = role(
    SeedRoles.storeManagerId,
    permissions: SeedRoles.storeManagerPermissions,
  );
  final adminRole = role(
    SeedRoles.adminId,
    permissions: SeedRoles.adminPermissions,
    all: true,
  );

  Future<void> putUser(AppUser u) => put(
    db,
    FirestorePaths.user(u.uid),
    u.toMap(),
    serverTimes: {'createdAt': DateTime.utc(2026)},
  );

  Future<void> seed() async {
    await put(db, FirestorePaths.role(smRole.id), smRole.toMap());
    await put(db, FirestorePaths.role(adminRole.id), adminRole.toMap());
    await put(db, FirestorePaths.location('PTB'), location('PTB').toMap());
  }

  MockFirebaseAuth mockAuth(String uid, {bool signedIn = false}) =>
      MockFirebaseAuth(
        signedIn: signedIn,
        mockUser: MockUser(uid: uid, email: '$uid@example.com'),
      );

  void throwOnSignIn(String code) => whenCalling(
    Invocation.method(#signInWithEmailAndPassword, null),
  ).on(auth).thenThrow(FirebaseAuthException(code: code));

  Future<SessionContext> signIn() =>
      service.signIn(email: ' sm1@example.com ', password: 'secret1');

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seed();
  });

  tearDown(() => service.dispose());

  group('signIn', () {
    setUp(() {
      auth = mockAuth('sm1');
      service = FirebaseAuthService(auth: auth, firestore: db);
    });

    test('a Store Manager gets their user, role and location', () async {
      await putUser(appUser('sm1'));
      final signIns = <void>[];
      final sub = service.interactiveSignIns.listen(signIns.add);
      final s = await signIn();
      expect(s.user.uid, 'sm1');
      expect(s.role.id, SeedRoles.storeManagerId);
      expect(s.location!.code, 'PTB');
      expect(s.canAt(Permission.billCreate, 'PTB'), isTrue);
      expect(s.canAt(Permission.billCreate, 'MNJ'), isFalse);
      expect(service.current, same(s));
      await pumpEventQueue();
      expect(signIns, hasLength(1));
      expect(await service.session.first, isNotNull);
      await sub.cancel();
    });

    test('an all-locations Admin has no location', () async {
      await putUser(
        appUser('sm1', locationId: null, roleId: SeedRoles.adminId),
      );
      final s = await signIn();
      expect(s.role.allLocations, isTrue);
      expect(s.location, isNull);
      expect(s.canAt(Permission.reportAll, 'MNJ'), isTrue);
    });

    for (final (code, reason) in [
      ('invalid-credential', FailureReason.invalidCredentials),
      ('wrong-password', FailureReason.invalidCredentials),
      ('user-not-found', FailureReason.invalidCredentials),
      ('invalid-email', FailureReason.invalidCredentials),
      ('user-disabled', FailureReason.userDisabled),
      ('network-request-failed', FailureReason.offline),
      ('too-many-requests', FailureReason.unknown),
    ]) {
      test('Auth error $code is ${reason.name}', () async {
        throwOnSignIn(code);
        await expectLater(
          signIn(),
          throwsA(isA<DataFailure>().having((f) => f.reason, 'reason', reason)),
        );
        expect(service.current, isNull);
      });
    }

    Future<void> expectRefused(FailureReason reason) async {
      await expectLater(
        signIn(),
        throwsA(isA<DataFailure>().having((f) => f.reason, 'reason', reason)),
      );
      expect(auth.currentUser, isNull, reason: 'signed out again');
      expect(service.current, isNull);
    }

    test('an inactive user is userDisabled and signed out', () async {
      await putUser(appUser('sm1', active: false));
      await expectRefused(FailureReason.userDisabled);
    });

    test('no users doc is noProfile', () async {
      await expectRefused(FailureReason.noProfile);
    });

    test('a missing role is noProfile', () async {
      await putUser(appUser('sm1', roleId: 'CASHIER'));
      await expectRefused(FailureReason.noProfile);
    });

    test('a scoped user without a location is noProfile', () async {
      await putUser(appUser('sm1', locationId: null));
      await expectRefused(FailureReason.noProfile);
    });

    test('a missing location doc is noProfile', () async {
      await putUser(appUser('sm1', locationId: 'MNJ'));
      await expectRefused(FailureReason.noProfile);
    });

    test('a malformed users doc is noProfile', () async {
      await db.doc(FirestorePaths.user('sm1')).set({'name': 'x'});
      await expectRefused(FailureReason.noProfile);
    });

    test('no network for the profile read is offline', () async {
      await putUser(appUser('sm1'));
      whenCalling(Invocation.method(#get, null))
          .on(db.doc(FirestorePaths.user('sm1')))
          .thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
      await expectRefused(FailureReason.offline);
    });

    test('a failed sign-in does not count as an interactive one', () async {
      final signIns = <void>[];
      final sub = service.interactiveSignIns.listen(signIns.add);
      await putUser(appUser('sm1', active: false));
      await expectLater(signIn(), throwsA(isA<DataFailure>()));
      await pumpEventQueue();
      expect(signIns, isEmpty);
      await sub.cancel();
    });
  });

  group('session', () {
    late List<SessionContext?> seen;
    late StreamSubscription<SessionContext?> sub;

    setUp(() async {
      auth = mockAuth('sm1');
      service = FirebaseAuthService(auth: auth, firestore: db);
      await putUser(appUser('sm1'));
      seen = [];
      sub = service.session.listen(seen.add);
      await signIn();
      await pumpEventQueue();
    });

    tearDown(() => sub.cancel());

    test('starts with null (signed out), then the session', () {
      expect(seen.first, isNull);
      expect(seen.last!.user.uid, 'sm1');
    });

    test('re-emits when the user doc changes', () async {
      await db.doc(FirestorePaths.user('sm1')).update({'name': 'Renamed'});
      await pumpEventQueue();
      expect(seen.last!.user.name, 'Renamed');
      expect(service.current!.user.name, 'Renamed');
    });

    test('re-emits when the role changes', () async {
      await db.doc(FirestorePaths.role(smRole.id)).update({
        'permissions': [Permission.catalogView],
      });
      await pumpEventQueue();
      expect(seen.last!.can(Permission.billCreate), isFalse);
      expect(seen.last!.can(Permission.catalogView), isTrue);
    });

    test('re-emits when the location changes', () async {
      await db.doc(FirestorePaths.location('PTB')).update({
        'receiptFooter': 'New footer',
      });
      await pumpEventQueue();
      expect(seen.last!.location!.receiptFooter, 'New footer');
    });

    test('follows a move to another location', () async {
      await put(db, FirestorePaths.location('MNJ'), location('MNJ').toMap());
      await db.doc(FirestorePaths.user('sm1')).update({'locationId': 'MNJ'});
      await pumpEventQueue();
      expect(seen.last!.location!.code, 'MNJ');
      expect(seen.last!.canAt(Permission.billCreate, 'PTB'), isFalse);
    });

    test(
      'a user disabled while signed in keeps a session that can do nothing',
      () async {
        await db.doc(FirestorePaths.user('sm1')).update({'active': false});
        await pumpEventQueue();
        expect(seen.last!.user.active, isFalse);
        expect(seen.last!.can(Permission.catalogView), isFalse);
        expect(auth.currentUser, isNotNull);
      },
    );

    test('a users doc deleted on the server ends the session', () async {
      await db.doc(FirestorePaths.user('sm1')).delete();
      await pumpEventQueue();
      expect(seen.last, isNull);
      expect(service.current, isNull);
    });

    test('signOut emits null once', () async {
      final before = seen.length;
      await service.signOut();
      await pumpEventQueue();
      expect(seen.sublist(before), [null]);
      expect(auth.currentUser, isNull);
      expect(service.current, isNull);
    });

    test('a later listener gets the current session first', () async {
      final first = await service.session.first;
      expect(first!.user.uid, 'sm1');
    });
  });

  group('a session restored at start-up', () {
    test('loads from the docs without an interactive sign-in', () async {
      await putUser(appUser('sm1'));
      auth = mockAuth('sm1', signedIn: true);
      service = FirebaseAuthService(auth: auth, firestore: db);
      final signIns = <void>[];
      final sub = service.interactiveSignIns.listen(signIns.add);
      final s = await service.session.firstWhere((s) => s != null);
      expect(s!.location!.code, 'PTB');
      expect(signIns, isEmpty);
      await sub.cancel();
    });

    test('signed out at start-up emits null', () async {
      auth = mockAuth('sm1');
      service = FirebaseAuthService(auth: auth, firestore: db);
      expect(await service.session.first, isNull);
    });
  });
}
