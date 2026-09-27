import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/session.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [AuthService] over Firebase Auth (email and password) and the
/// `users/{uid}`, `roles/{roleId}` and `locations/{loc}` docs.
///
/// After sign-in, and for a session Firebase Auth restores at start-up,
/// snapshot listeners on those three docs keep [session] fresh (03-SYNC §8)
/// and keep them in the offline cache. A user disabled while signed in stays
/// in the session with `active == false`, so every `can` check fails; they
/// are not signed out, because an offline device may still hold their
/// queued writes. A user, role or location doc that the server says is gone
/// ends the session (null) without signing out of Firebase Auth.
///
/// This class does not touch `lastSyncAt`. The sync service listens to
/// [interactiveSignIns] for that (03-SYNC §6).
final class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : _auth = auth,
       _db = firestore {
    _authSub = _auth.authStateChanges().listen(_onAuthUser);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  late final StreamSubscription<User?> _authSub;

  final _changes = StreamController<SessionContext?>.broadcast();
  final _signIns = StreamController<void>.broadcast();

  SessionContext? _current;

  /// False until the first session state is known (signed out, or a
  /// restored session loaded), so [session] doesn't start with a null that
  /// would flash the login screen for a signed-in user.
  bool _resolved = false;
  bool _signingIn = false;
  _ProfileWatch? _watch;

  /// Emits the current value on listen (once it is known), then every
  /// change.
  @override
  Stream<SessionContext?> get session => Stream.multi((c) {
    if (_resolved) c.add(_current);
    final sub = _changes.stream.listen(c.add, onError: c.addError);
    c.onCancel = sub.cancel;
  });

  @override
  SessionContext? get current => _current;

  /// One event per successful interactive [signIn], after [session] has the
  /// new value. Restoring a saved session at start-up does not emit.
  Stream<void> get interactiveSignIns => _signIns.stream;

  @override
  Future<SessionContext> signIn({
    required String email,
    required String password,
  }) async {
    if (_signingIn) {
      throw const DataFailure(FailureReason.unknown, 'sign-in in progress');
    }
    _signingIn = true;
    try {
      final UserCredential cred;
      try {
        cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        throw authFailure(e);
      }
      final uid = cred.user?.uid;
      if (uid == null) {
        throw const DataFailure(FailureReason.unknown, 'no user after sign-in');
      }
      final SessionContext ctx;
      try {
        ctx = await _loadProfile(uid);
      } on Object {
        await _auth.signOut();
        rethrow;
      }
      _startWatch(uid, ctx);
      _publish(ctx);
      _signIns.add(null);
      return ctx;
    } finally {
      _signingIn = false;
    }
  }

  @override
  Future<void> signOut() async {
    _stopWatch();
    _publish(null);
    await _auth.signOut();
  }

  /// Stops the listeners. The service can't be used afterwards.
  Future<void> dispose() async {
    _stopWatch();
    await _authSub.cancel();
    await _changes.close();
    await _signIns.close();
  }

  /// Reads the user, role and location once, from the server when online.
  /// The user doc is readable even when inactive (04-PERMISSIONS #3), which
  /// is what tells [FailureReason.userDisabled] from
  /// [FailureReason.noProfile].
  Future<SessionContext> _loadProfile(String uid) async {
    Future<DocumentSnapshot<Map<String, dynamic>>> read(String path) async {
      try {
        return await _db.doc(path).get(estimateServerTimestamps);
      } on FirebaseException catch (e) {
        final f = failureFromFirestore(e);
        throw f.reason == FailureReason.notPermitted
            ? DataFailure(FailureReason.noProfile, f.detail)
            : f;
      }
    }

    T parse<T>(T? Function() convert, String what) {
      try {
        final v = convert();
        if (v == null) throw DataFailure(FailureReason.noProfile, what);
        return v;
      } on FormatException catch (e) {
        throw DataFailure(FailureReason.noProfile, '$what: ${e.message}');
      }
    }

    final userSnap = await read(FirestorePaths.user(uid));
    final user = parse(
      () => modelOrNull(
        userSnap,
        AppUser.fromMap,
        serverTimestampFields: AppUser.serverTimestampFields,
      ),
      'user $uid',
    );
    if (!user.active) throw const DataFailure(FailureReason.userDisabled);
    final roleSnap = await read(FirestorePaths.role(user.roleId));
    final role = parse(
      () => modelOrNull(roleSnap, Role.fromMap),
      'role ${user.roleId}',
    );
    if (role.allLocations) {
      return SessionContext(user: user, role: role, location: null);
    }
    final loc = user.locationId;
    if (loc == null) {
      throw DataFailure(FailureReason.noProfile, 'user $uid has no location');
    }
    final locSnap = await read(FirestorePaths.location(loc));
    final location = parse(
      () => modelOrNull(locSnap, Location.fromMap),
      'location $loc',
    );
    return SessionContext(user: user, role: role, location: location);
  }

  void _onAuthUser(User? user) {
    if (_signingIn) return; // signIn handles its own outcome.
    if (user == null) {
      _stopWatch();
      _publish(null);
    } else if (_watch?.uid != user.uid) {
      _startWatch(user.uid, null); // A session restored at start-up.
    }
  }

  void _startWatch(String uid, SessionContext? initial) {
    _stopWatch();
    _watch = _ProfileWatch(_db, uid, initial, _onWatch);
  }

  void _stopWatch() {
    _watch?.cancel();
    _watch = null;
  }

  void _onWatch(_ProfileWatch w, SessionContext? s) {
    if (!identical(w, _watch)) return;
    _publish(s);
  }

  void _publish(SessionContext? s) {
    if (_resolved && s == null && _current == null) return;
    _resolved = true;
    _current = s;
    _changes.add(s);
  }
}

/// The [DataFailure] for a Firebase Auth sign-in error.
DataFailure authFailure(FirebaseAuthException e) =>
    DataFailure(switch (e.code) {
      'invalid-credential' ||
      'INVALID_LOGIN_CREDENTIALS' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' => FailureReason.invalidCredentials,
      'user-disabled' => FailureReason.userDisabled,
      'network-request-failed' => FailureReason.offline,
      _ => FailureReason.unknown,
    }, '${e.code}: ${e.message ?? ''}');

/// Snapshot listeners on one user's profile docs. Calls [onChange] with the
/// session each time it changes, null when a doc is definitely gone, and
/// nothing while a doc is still loading.
final class _ProfileWatch {
  _ProfileWatch(this._db, this.uid, SessionContext? initial, this._onChange)
    : _user = initial?.user,
      _role = initial?.role,
      _location = initial?.location {
    _userSub = _db
        .doc(FirestorePaths.user(uid))
        .snapshots()
        .listen(_onUser, onError: _ignore);
    if (initial != null) {
      _listenRole(initial.role.id);
      _listenLocation(initial.user);
    }
  }

  final FirebaseFirestore _db;
  final String uid;
  final void Function(_ProfileWatch, SessionContext?) _onChange;

  AppUser? _user;
  Role? _role;
  Location? _location;
  bool _gone = false;

  late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roleSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _locSub;
  String? _roleId;

  /// `locationId` and `active` of the user the location listener was opened
  /// for. Reading a location needs an active user there (04-PERMISSIONS
  /// #4), so a listener that failed while the user was disabled is reopened
  /// when they are enabled again.
  String? _locKey;

  void cancel() {
    unawaited(_userSub.cancel());
    unawaited(_roleSub?.cancel());
    unawaited(_locSub?.cancel());
  }

  /// A failed listener keeps the last value it had; a later change to the
  /// user doc reopens the role and location listeners.
  static void _ignore(Object _) {}

  void _onUser(DocumentSnapshot<Map<String, dynamic>> s) {
    if (!s.exists) {
      // Not in the cache yet: wait for the server, but let the app show the
      // login screen meanwhile if nothing is known.
      if (s.metadata.isFromCache) {
        if (_user == null) _onChange(this, null);
        return;
      }
      return _end();
    }
    final AppUser user;
    try {
      user = modelOrNull(
        s,
        AppUser.fromMap,
        serverTimestampFields: AppUser.serverTimestampFields,
      )!;
    } on FormatException {
      return _end();
    }
    _user = user;
    _gone = false;
    if (user.roleId != _roleId) {
      _role = null;
      _listenRole(user.roleId);
    }
    _listenLocation(user);
    _emit();
  }

  void _listenRole(String roleId) {
    unawaited(_roleSub?.cancel());
    _roleId = roleId;
    _roleSub = _db.doc(FirestorePaths.role(roleId)).snapshots().listen((s) {
      if (!s.exists) {
        if (!s.metadata.isFromCache) _end();
        return;
      }
      try {
        _role = modelOrNull(s, Role.fromMap);
      } on FormatException {
        return _end();
      }
      _emit();
    }, onError: _ignore);
  }

  void _listenLocation(AppUser user) {
    final loc = user.locationId;
    final key = loc == null ? null : '$loc|${user.active}';
    if (key == _locKey) return;
    _locKey = key;
    unawaited(_locSub?.cancel());
    _locSub = null;
    if (_location?.code != loc) _location = null;
    if (loc == null) return;
    _locSub = _db.doc(FirestorePaths.location(loc)).snapshots().listen((s) {
      if (!s.exists) {
        if (!s.metadata.isFromCache) _end();
        return;
      }
      try {
        _location = modelOrNull(s, Location.fromMap);
      } on FormatException {
        return _end();
      }
      _emit();
    }, onError: _ignore);
  }

  void _end() {
    _gone = true;
    _onChange(this, null);
  }

  void _emit() {
    final user = _user;
    final role = _role;
    if (_gone || user == null || role == null) return;
    if (role.allLocations) {
      return _onChange(
        this,
        SessionContext(user: user, role: role, location: null),
      );
    }
    final location = _location;
    if (user.locationId == null) return _end();
    if (location == null || location.code != user.locationId) return;
    _onChange(this, SessionContext(user: user, role: role, location: location));
  }
}
