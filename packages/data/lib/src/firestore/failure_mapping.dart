import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/failures.dart';

/// The [DataFailure] for a Firestore error code, e.g. a read the rules deny
/// (another location, a disabled user) or one made without a network and
/// without the doc in the cache.
DataFailure failureFromFirestore(FirebaseException e) =>
    DataFailure(switch (e.code) {
      'permission-denied' || 'unauthenticated' => FailureReason.notPermitted,
      'unavailable' || 'deadline-exceeded' => FailureReason.offline,
      'not-found' => FailureReason.notFound,
      _ => FailureReason.unknown,
    }, '${e.code}: ${e.message ?? ''}');

/// Runs [op] (a read or a commit) and rethrows a Firestore error as a
/// [DataFailure]. Model format errors (`FormatException`) pass through
/// unchanged.
Future<T> guardFirestore<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on FirebaseException catch (e) {
    throw failureFromFirestore(e);
  }
}

extension FirestoreFailureStream<T> on Stream<T> {
  /// The same stream with Firestore errors turned into [DataFailure]s.
  Stream<T> mapFirestoreErrors() => transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stack, sink) => sink.addError(
        error is FirebaseException ? failureFromFirestore(error) : error,
        stack,
      ),
    ),
  );
}
