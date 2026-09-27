import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/sales.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [SalesRepository] over `locations/{loc}/bills` and `returns`.
final class FirestoreSalesRepository implements SalesRepository {
  FirestoreSalesRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// `businessDate ==` ordered by `clientCreatedAt` descending (index:
  /// bills `businessDate, clientCreatedAt DESC`). Ties, which only a
  /// hand-built doc could produce, fall back to the doc ID.
  @override
  Stream<List<Bill>> watchBills(String locationId, String businessDate) => _db
      .collection(FirestorePaths.bills(locationId))
      .where('businessDate', isEqualTo: businessDate)
      .orderBy('clientCreatedAt', descending: true)
      .snapshots()
      .map(
        (s) => modelsOf(
          s,
          Bill.fromMap,
          now: _now,
          serverTimestampFields: Bill.serverTimestampFields,
        ),
      )
      .mapFirestoreErrors();

  @override
  Future<Bill?> getBill(String locationId, String billId) => guardFirestore(
    () async => modelOrNull(
      await _db
          .doc(FirestorePaths.bill(locationId, billId))
          .get(estimateServerTimestamps),
      Bill.fromMap,
      serverTimestampFields: Bill.serverTimestampFields,
      now: _now,
    ),
  );

  /// Parses `{loc}-{deviceId}-{seq}` with `Ids`, then reads that one doc. A
  /// number that isn't in that exact form (after trimming and upper-casing)
  /// finds nothing. A bill at a location the user can't read throws
  /// `DataFailure(notPermitted)`.
  @override
  Future<Bill?> findByBillNo(String billNo) async {
    final ref = parseBillNo(billNo);
    if (ref == null) return null;
    final bill = await getBill(ref.locationId, ref.billId);
    return bill != null && bill.billNo == ref.billNo ? bill : null;
  }

  /// Returns processed on [businessDate] (D-012), newest first. Sorted here
  /// so it needs no composite index; a day has few returns.
  @override
  Stream<List<SaleReturn>> watchReturns(
    String locationId,
    String businessDate,
  ) => _db
      .collection(FirestorePaths.returns(locationId))
      .where('businessDate', isEqualTo: businessDate)
      .snapshots()
      .map((s) => _returns(s)..sort(_newestFirst))
      .mapFirestoreErrors();

  /// Oldest first, the order they were made in.
  @override
  Future<List<SaleReturn>> returnsForBill(String locationId, String billId) =>
      guardFirestore(() async {
        final s = await _db
            .collection(FirestorePaths.returns(locationId))
            .where('billId', isEqualTo: billId)
            .get(estimateServerTimestamps);
        return _returns(s)..sort((a, b) => _newestFirst(b, a));
      });

  List<SaleReturn> _returns(QuerySnapshot<Map<String, dynamic>> s) => modelsOf(
    s,
    SaleReturn.fromMap,
    serverTimestampFields: SaleReturn.serverTimestampFields,
    now: _now,
  );

  static int _newestFirst(SaleReturn a, SaleReturn b) {
    final c = b.clientCreatedAt.compareTo(a.clientCreatedAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  }
}

/// The parts of a printed bill number.
typedef BillRef = ({String billNo, String locationId, String billId});

/// Splits `PTB-D01-000123` into its location and bill ID, or null when it
/// isn't a well-formed bill number. Surrounding spaces and lower case are
/// accepted; anything else (a missing part, a short or out-of-range seq) is
/// not.
BillRef? parseBillNo(String input) {
  final s = input.trim().toUpperCase();
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final [loc, dev, seqText] = parts;
  if (!Ids.isLocationCode(loc) || !Ids.isDeviceCode(dev)) return null;
  if (seqText.length != Ids.seqWidth) return null;
  final seq = int.tryParse(seqText);
  if (seq == null || seq < 1 || seq > Ids.maxSeq) return null;
  final billId = Ids.billId(dev, seq);
  final billNo = Ids.billNo(loc, billId);
  return billNo == s ? (billNo: billNo, locationId: loc, billId: billId) : null;
}
