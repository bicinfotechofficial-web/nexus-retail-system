import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';
import 'package:nexus_printer/src/receipt/receipt_document.dart';

import 'fixtures.dart';
import 'golden_text.dart';

void main() {
  ReceiptDocument doc(Bill bill, {bool reprint = false}) =>
      ReceiptDocument.fromBill(bill, pilotLocation, reprint: reprint);

  ReturnSlipDocument slip() {
    final bill = discountedSplitBill();
    return ReturnSlipDocument.fromReturn(
      partialReturn(bill),
      bill,
      pilotLocation,
    );
  }

  final receipts = <String, List<PrintLine> Function(ReceiptLayout)>{
    'bill_normal': (l) => l.bill(doc(normalBill())),
    'bill_discount_split': (l) => l.bill(doc(discountedSplitBill())),
    'bill_cancelled_reprint': (l) =>
        l.bill(doc(cancelledBill(), reprint: true)),
    'bill_gst': (l) => l.bill(doc(gstBill())),
    'return_slip': (l) => l.returnSlip(slip()),
  };

  for (final width in PaperWidth.values) {
    final layout = ReceiptLayout(width);
    group('${width.name} (${width.columns} columns)', () {
      for (final MapEntry(key: name, value: build) in receipts.entries) {
        test('$name matches its golden', () {
          expectTextGolden(renderText(build(layout)), '${name}_${width.name}');
        });

        test('$name lines are all ${width.columns} wide', () {
          for (final l in build(layout)) {
            expect(textWidth(l.text), width.columns, reason: '"${l.text}"');
          }
        });
      }
    });
  }

  group('content rules', () {
    const layout = ReceiptLayout(PaperWidth.mm80);
    String text(Bill bill, {bool reprint = false}) =>
        renderText(layout.bill(doc(bill, reprint: reprint)));

    test('the total alone is double height and bold', () {
      final tall = layout
          .bill(doc(normalBill()))
          .where((l) => l.doubleHeight)
          .toList();
      expect(tall, hasLength(1));
      expect(tall.single.text, startsWith('TOTAL'));
      expect(tall.single.text.trimRight(), endsWith('₹1,149.00'));
      expect(tall.single.bold, isTrue);
    });

    test('the round-off line prints even at zero (D-010)', () {
      expect(text(normalBill()), contains(RegExp(r'Round off +₹0\.00')));
      expect(
        text(discountedSplitBill()),
        contains(RegExp(r'Round off +-₹0\.07')),
      );
    });

    test('no GST block while taxLines is empty (D-013)', () {
      expect(text(normalBill()), isNot(contains('GST')));
      expect(text(gstBill()), contains('CGST 2.5%'));
    });

    test('REPRINT only when asked; CANCELLED always for a cancelled bill', () {
      expect(text(normalBill()), isNot(contains('REPRINT')));
      expect(text(normalBill(), reprint: true), contains('REPRINT'));
      expect(text(cancelledBill()), contains('CANCELLED'));
      expect(text(cancelledBill()), isNot(contains('REPRINT')));
    });

    test('the time prints in IST', () {
      expect(text(normalBill()), contains('Date: 25-09-2026 14:35'));
    });

    test('amounts use Indian grouping', () {
      expect(text(discountedSplitBill()), contains('₹1,898.97'));
    });

    test('the Rs. fallback keeps amounts right-aligned', () {
      const rs = ReceiptLayout(PaperWidth.mm58, currencySymbol: 'Rs.');
      final lines = rs.bill(doc(discountedSplitBill()));
      final total = lines.singleWhere((l) => l.doubleHeight).text;
      expect(total, endsWith('Rs.1,709.00'));
      expect(renderText(lines), isNot(contains('₹')));
      for (final l in lines) {
        expect(textWidth(l.text), 32);
      }
    });

    test('a flat discount has no percentage', () {
      final t = BillCalculator.compute([
        blackForest1kg,
      ], discount: DiscountInput.flat(const Money.rupees(50)));
      final base = normalBill();
      final bill = Bill(
        id: base.id,
        billNo: base.billNo,
        deviceId: base.deviceId,
        seq: base.seq,
        lines: t.lines,
        subtotal: t.subtotal,
        discount: t.discount,
        taxableValue: t.taxableValue,
        roundOff: t.roundOff,
        total: t.total,
        payments: [Payment(mode: PaymentMode.other, amount: t.total)],
        status: BillStatus.completed,
        servedBy: base.servedBy,
        businessDate: base.businessDate,
        clientCreatedAt: base.clientCreatedAt,
        createdBy: base.createdBy,
      );
      expect(text(bill), contains(RegExp(r'Discount +-₹50\.00')));
      expect(text(bill), contains(RegExp(r'Other +₹800\.00')));
    });

    test('an empty footer adds nothing after the served-by line', () {
      const bare = Location(
        code: 'PTB',
        name: 'Caramel Cottage',
        address: 'Pattambi',
        phone: '0',
        overridePinHash: 'x',
        receiptFooter: ' ',
        nextDeviceNo: 2,
        active: true,
      );
      final lines = layout.bill(ReceiptDocument.fromBill(normalBill(), bare));
      expect(lines.last.text.trim(), 'Served by: Store Manager');
    });
  });
}
