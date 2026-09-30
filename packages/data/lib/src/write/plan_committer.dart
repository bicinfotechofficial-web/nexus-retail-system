import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/failures.dart';
import '../firestore/failure_mapping.dart';
import '../firestore/plan_adapter.dart';
import '../plans/write_plan.dart';

/// A plan that has been committed to the device's local store.
final class CommittedPlan {
  CommittedPlan(this.plan, this.serverAck);

  final WritePlan plan;

  /// Completes when the server accepts the batch, or fails with a
  /// [DataFailure] when it rejects it. Never completes while offline, and
  /// is lost when the app is killed; the sync pass (03-SYNC §6) is what
  /// verifies a write, this is only an early signal. Errors on it are
  /// handled, so nobody has to listen.
  final Future<void> serverAck;
}

/// Applies a [WritePlan] as one atomic batch (03-SYNC §1–2).
abstract interface class PlanCommitter {
  /// Commits [plan] and completes once it is in the local store, without
  /// waiting for the server (offline-first). Throws a [DataFailure] when the
  /// batch can't even be committed locally.
  Future<CommittedPlan> commit(WritePlan plan);
}

/// [PlanCommitter] on Firestore.
///
/// FlutterFire's `WriteBatch.commit()` completes only when the **server**
/// acknowledges the batch, so offline it never completes and must not be
/// awaited. The native SDK writes the batch to its local store (the
/// persisted mutation queue) as soon as the platform side runs the commit,
/// but on Android that happens on a thread pool, so the Dart side has no
/// ordering guarantee between the commit call and a later read. This
/// committer therefore:
///
/// 1. calls `commit()` and keeps its future as [CommittedPlan.serverAck];
/// 2. polls the cache (`Source.cache`) for the first doc the plan creates
///    (or, without one, merges into; both always leave a document in the
///    local view) until it shows `hasPendingWrites`, or until the commit
///    future has completed, whichever comes first;
/// 3. rethrows a commit error that arrives before that as a [DataFailure].
///
/// When the probe times out ([localTimeout]) the write is still in flight
/// on the platform side; the commit is then treated as done, since
/// Firestore never drops a batch it has been handed, and the ledger will
/// verify it.
///
/// With [awaitServer] (the admin console, which is online only and keeps
/// no persistence on the web) the commit is awaited instead, with
/// [serverTimeout], and a timeout is `DataFailure(offline)`.
final class FirestorePlanCommitter implements PlanCommitter {
  FirestorePlanCommitter(
    this.db, {
    this.awaitServer = false,
    this.localTimeout = const Duration(seconds: 5),
    this.serverTimeout = const Duration(seconds: 20),
    this.pollEvery = const Duration(milliseconds: 15),
  });

  final FirebaseFirestore db;
  final bool awaitServer;
  final Duration localTimeout;
  final Duration serverTimeout;
  final Duration pollEvery;

  @override
  Future<CommittedPlan> commit(WritePlan plan) async {
    final WriteBatch batch;
    try {
      batch = PlanAdapter.toBatch(db, plan);
    } on FirebaseException catch (e) {
      throw failureFromFirestore(e);
    } on ArgumentError catch (e) {
      throw DataFailure(FailureReason.unknown, 'bad plan: ${e.message}');
    }
    final ack = Completer<void>();
    var settled = false;
    DataFailure? earlyError;
    unawaited(
      batch.commit().then(
        (_) {
          settled = true;
          ack.complete();
        },
        onError: (Object e, StackTrace st) {
          settled = true;
          earlyError = e is FirebaseException
              ? failureFromFirestore(e)
              : e is DataFailure
              ? e
              : DataFailure(FailureReason.unknown, '$e');
          ack.completeError(earlyError!, st);
        },
      ),
    );
    // Nobody is required to listen to the server outcome.
    unawaited(ack.future.catchError((Object _) {}));

    if (awaitServer) {
      try {
        await ack.future.timeout(serverTimeout);
      } on TimeoutException {
        throw const DataFailure(
          FailureReason.offline,
          'the server did not confirm the write',
        );
      }
      return CommittedPlan(plan, ack.future);
    }

    final probe = _probePath(plan);
    final deadline = DateTime.now().add(localTimeout);
    while (!settled && probe != null && DateTime.now().isBefore(deadline)) {
      if (await _isPendingLocally(probe)) break;
      await Future<void>.delayed(pollEvery);
    }
    final e = earlyError;
    if (e != null) throw e;
    return CommittedPlan(plan, ack.future);
  }

  /// The doc to watch: the first one the plan creates (it can't have
  /// pending writes from anything else), else the first it merges into. An
  /// `update` on a doc that isn't in the cache doesn't make it readable from
  /// the cache, so it can't be probed.
  static String? _probePath(WritePlan plan) {
    for (final kind in [WriteKind.create, WriteKind.setMerge]) {
      for (final op in plan.ops) {
        if (op.kind == kind) return op.path;
      }
    }
    return null;
  }

  Future<bool> _isPendingLocally(String path) async {
    try {
      final s = await db.doc(path).get(const GetOptions(source: Source.cache));
      return s.exists && s.metadata.hasPendingWrites;
    } on FirebaseException {
      return false; // Not in the cache yet.
    }
  }
}
