// The PLAN.md oracles, computed from what is on the emulator (read with
// owner access, so no device cache or implementation is involved).
//
// - Stock oracle: every stock doc's qty equals the sum of the deltas of every
//   movement doc for that itemKey (D-005).
// - Summary oracle: a day's or month's summary equals the sum of
//   `SummaryDeltas` over the bill, cancellation and return docs of that
//   period (the same recomputation as test/e2e's P-01).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';

import 'emulator.dart';

/// What the server holds at one location.
final class ServerState {
  ServerState._(this.bills, this.returns, this.movements, this.stock);

  static Future<ServerState> read(EmulatorAdmin admin, String loc) async {
    final bills = [
      for (final d in await admin.list(FirestorePaths.bills(loc)))
        Bill.fromMap(d.id, d.data),
    ];
    final returns = [
      for (final d in await admin.list(FirestorePaths.returns(loc)))
        SaleReturn.fromMap(d.id, d.data),
    ];
    final movements = [
      for (final d in await admin.list(FirestorePaths.movements(loc)))
        Movement.fromMap(d.id, d.data),
    ];
    final stock = {
      for (final d in await admin.list(FirestorePaths.stock(loc)))
        d.id: StockItem.fromMap(d.id, d.data),
    };
    return ServerState._(bills, returns, movements, stock);
  }

  final List<Bill> bills;
  final List<SaleReturn> returns;
  final List<Movement> movements;
  final Map<String, StockItem> stock;

  Bill bill(String id) => bills.singleWhere((b) => b.id == id);

  int qty(String itemKey) => stock[itemKey]?.qty ?? 0;

  /// Σ delta per itemKey over every movement doc.
  Map<String, int> get movementTotals {
    final out = <String, int>{};
    for (final m in movements) {
      for (final l in m.lines) {
        out[l.itemKey] = (out[l.itemKey] ?? 0) + l.delta;
      }
    }
    return out;
  }

  List<Movement> movementsOf(MovementType type) =>
      movements.where((m) => m.type == type).toList();
}

/// Asserts the stock oracle at [loc] and returns the server state.
Future<ServerState> expectStockOracle(EmulatorAdmin admin, String loc) async {
  final s = await ServerState.read(admin, loc);
  final totals = s.movementTotals;
  expect(
    {for (final e in s.stock.entries) e.key: e.value.qty},
    {
      for (final k in {...s.stock.keys, ...totals.keys}) k: totals[k] ?? 0,
    },
    reason: 'stock/{itemKey}.qty == Σ movement deltas at $loc (D-005)',
  );
  return s;
}

/// The summary the documents at [loc] add up to for the dates [inPeriod]
/// accepts.
Summary summaryOracle(ServerState s, bool Function(String date) inPeriod) {
  var sum = const Summary();
  for (final b in s.bills) {
    if (inPeriod(b.businessDate)) sum += SummaryDeltas.forBill(b);
    final c = b.cancel;
    if (b.status == BillStatus.cancelled &&
        c != null &&
        inPeriod(c.businessDate)) {
      sum += SummaryDeltas.forCancel(b);
    }
  }
  for (final r in s.returns) {
    if (inPeriod(r.businessDate)) sum += SummaryDeltas.forReturn(r);
  }
  return sum;
}

/// Asserts the summary oracle for [businessDate] and its month at [loc].
/// Zero fields and entries are ignored on both sides (a summary is built
/// from increments, so a key can exist with 0).
Future<void> expectSummaryOracle(
  EmulatorAdmin admin,
  String loc,
  String businessDate,
) async {
  final s = await ServerState.read(admin, loc);
  final month = BusinessDate.monthOf(businessDate);

  Future<Map<String, int>> stored(String path) async {
    final data = await admin.get(path);
    return SummaryDeltas.increments(
      data == null ? const Summary() : Summary.fromMap(path, data),
    );
  }

  expect(
    await stored(FirestorePaths.dailySummary(loc, businessDate)),
    SummaryDeltas.increments(summaryOracle(s, (d) => d == businessDate)),
    reason: 'dailySummary/$businessDate at $loc equals its documents',
  );
  expect(
    await stored(FirestorePaths.monthlySummary(loc, month)),
    SummaryDeltas.increments(
      summaryOracle(s, (d) => BusinessDate.monthOf(d) == month),
    ),
    reason: 'monthlySummary/$month at $loc equals its documents',
  );
}
