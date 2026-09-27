import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/admin.dart';
import '../api/failures.dart';
import 'failure_mapping.dart';

/// Opens the Firebase Auth instance that creates new accounts. It must not
/// be the Admin's own instance, or creating a user would sign the Admin out.
typedef SecondaryAuthFactory = Future<FirebaseAuth> Function();

/// [UserService] for the admin console (D-018). Online only.
///
/// A new Store Manager's Auth account is created through a secondary
/// [FirebaseApp], so the Admin's session on the default app is untouched.
/// Then `users/{uid}` and a USER_CREATE audit entry are written in one batch
/// by the Admin. If that batch fails, the new Auth account is deleted again
/// (it is still signed in on the secondary app), so a retry with the same
/// email works.
final class FirestoreUserService implements UserService {
  FirestoreUserService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    SecondaryAuthFactory? secondaryAuth,
    DateTime Function()? clock,
  }) : _auth = auth,
       _db = firestore,
       _secondaryAuth = secondaryAuth ?? secondaryAuthFromDefaultApp,
       _now = clock ?? DateTime.now;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final SecondaryAuthFactory _secondaryAuth;
  final DateTime Function() _now;

  /// Name of the secondary app [secondaryAuthFromDefaultApp] opens.
  static const String secondaryAppName = 'nexus-user-admin';

  /// The Auth instance of a secondary app with the default app's options,
  /// created on first use and reused after.
  static Future<FirebaseAuth> secondaryAuthFromDefaultApp() async {
    final app = Firebase.apps.any((a) => a.name == secondaryAppName)
        ? Firebase.app(secondaryAppName)
        : await Firebase.initializeApp(
            name: secondaryAppName,
            options: Firebase.app().options,
          );
    return FirebaseAuth.instanceFor(app: app);
  }

  /// The audit ID of a user event (D-032).
  static String userAuditId(String? locationId, String uid, DateTime at) =>
      Ids.userAuditId(locationId, uid, at);

  @override
  Future<AppUser> createStoreManager({
    required String name,
    required String email,
    required String password,
    required String locationId,
  }) async {
    final adminUid = _adminUid();
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanName.isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'name is empty');
    }
    if (!Ids.isLocationCode(locationId)) {
      throw DataFailure(FailureReason.ruleViolation, 'location $locationId');
    }

    final secondary = await _secondaryAuth();
    final UserCredential cred;
    try {
      cred = await secondary.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _createFailure(e);
    }
    final newUser = cred.user;
    if (newUser == null) {
      throw const DataFailure(FailureReason.unknown, 'no user after create');
    }

    final user = AppUser(
      uid: newUser.uid,
      name: cleanName,
      email: cleanEmail,
      roleId: SeedRoles.storeManagerId,
      locationId: locationId,
      active: true,
      createdBy: adminUid,
    );
    final now = _now();
    final audit = AuditEntry(
      id: userAuditId(locationId, user.uid, now),
      action: AuditAction.userCreate,
      entityPath: FirestorePaths.user(user.uid),
      locationId: locationId,
      after: {
        'name': user.name,
        'email': user.email,
        'roleId': user.roleId,
        'locationId': locationId,
        'active': true,
      },
      by: adminUid,
      clientAt: now,
    );
    final batch = _db.batch()
      ..set(_db.doc(FirestorePaths.user(user.uid)), {
        ...user.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(_db.doc(FirestorePaths.audit(audit.id)), {
        ...audit.toMap(),
        'at': FieldValue.serverTimestamp(),
      });
    try {
      await guardFirestore(batch.commit);
    } on Object {
      // Roll back the Auth account so the email can be used again.
      try {
        await newUser.delete();
      } on Object {
        // Best effort: an orphan account has no users doc, so it can't do
        // anything (noProfile), and the Admin sees the original error.
      }
      rethrow;
    } finally {
      await secondary.signOut();
    }
    return user;
  }

  /// Sets `active`. Disabling writes a USER_DISABLE audit entry in the same
  /// batch; enabling is not audited, because there is no action for it
  /// (proposed in CHANGE-REQUESTS). The Admin can't change their own
  /// `active` (04-PERMISSIONS #3). Setting the value it already has writes
  /// nothing.
  @override
  Future<void> setActive(String uid, {required bool active}) async {
    final adminUid = _adminUid();
    if (uid == adminUid) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'you cannot change your own active state',
      );
    }
    final ref = _db.doc(FirestorePaths.user(uid));
    final snap = await guardFirestore(ref.get);
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw DataFailure(FailureReason.notFound, 'user $uid');
    }
    final wasActive = data['active'] == true;
    if (wasActive == active) return;

    final batch = _db.batch()..update(ref, {'active': active});
    if (!active) {
      final now = _now();
      final locationId = data['locationId'] as String?;
      final audit = AuditEntry(
        id: userAuditId(locationId, uid, now),
        action: AuditAction.userDisable,
        entityPath: FirestorePaths.user(uid),
        locationId: locationId,
        before: {'active': wasActive},
        after: {'active': false},
        by: adminUid,
        clientAt: now,
      );
      batch.set(_db.doc(FirestorePaths.audit(audit.id)), {
        ...audit.toMap(),
        'at': FieldValue.serverTimestamp(),
      });
    }
    await guardFirestore(batch.commit);
  }

  String _adminUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const DataFailure(FailureReason.notPermitted, 'not signed in');
    }
    return uid;
  }

  /// Admin-readable details: the console shows `detail` in its error
  /// dialog.
  static DataFailure _createFailure(FirebaseAuthException e) =>
      switch (e.code) {
        'email-already-in-use' => const DataFailure(
          FailureReason.ruleViolation,
          'email already in use',
        ),
        'invalid-email' => const DataFailure(
          FailureReason.ruleViolation,
          'not a valid email address',
        ),
        'weak-password' => const DataFailure(
          FailureReason.ruleViolation,
          'weak password (at least 6 characters)',
        ),
        'network-request-failed' => const DataFailure(FailureReason.offline),
        _ => DataFailure(
          FailureReason.unknown,
          '${e.code}: ${e.message ?? ''}',
        ),
      };
}
