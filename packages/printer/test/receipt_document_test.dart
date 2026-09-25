import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/src/receipt/receipt_document.dart';

import 'fixtures.dart';

void main() {
  group('ReceiptDocument.fromBill', () {
    test('copies the header, meta, lines and totals', () {
      final bill = normalBill();
      final doc = ReceiptDocument.fromBill(bill, pilotLocation);

      expect(doc.header.name, pilotLocation.name);
      expect(doc.header.address, pilotLocation.address);
      expect(doc.header.phone, pilotLocation.phone);
      expect(doc.billNo, 'PTB-D01-000123');
      expect(doc.servedBy, 'Store Manager');
      expect(doc.footer, pilotLocation.receiptFooter);

      expect(doc.lines, hasLength(2));
      final jar = doc.lines[1];
      expect(jar.name, redVelvetJar.name);
      expect(jar.qty, 2);
      expect(jar.unitPrice, const Money(14950));
      expect(jar.amount, const Money(29900));

      expect(doc.subtotal, const Money(114900));
      expect(doc.discount, isNull);
      expect(doc.roundOff, bill.roundOff);
      expect(doc.total, const Money.rupees(1149));
      expect(doc.reprint, isFalse);
      expect(doc.isCancelled, isFalse);
    });

    test('prints the time in IST whatever the instant zone', () {
      final doc = ReceiptDocument.fromBill(normalBill(), pilotLocation);
      final ist = doc.issuedAtIst;
      expect(ist.isUtc, isTrue);
      expect(
        [ist.year, ist.month, ist.day, ist.hour, ist.minute],
        [2026, 9, 25, 14, 35],
      );
    });

    test('shows cash tendered and change', () {
      final doc = ReceiptDocument.fromBill(normalBill(), pilotLocation);
      expect(doc.payments.single.mode, PaymentMode.cash);
      expect(doc.cashTendered, const Money.rupees(1200));
      expect(doc.change, const Money.rupees(51));
    });

    test('keeps a discount, a round-off and a split payment', () {
      final bill = discountedSplitBill();
      final doc = ReceiptDocument.fromBill(bill, pilotLocation);

      expect(doc.discount!.type, DiscountType.pct);
      expect(doc.discount!.value, 10);
      expect(doc.discount!.amount, bill.discount!.amount);
      expect(doc.roundOff.isZero, isFalse, reason: 'fixture must round');
      expect(doc.subtotal - doc.discount!.amount + doc.roundOff, doc.total);

      expect(doc.payments.map((p) => p.mode), [
        PaymentMode.upi,
        PaymentMode.cash,
      ]);
      expect(doc.payments.first.ref, '426912345678');
      expect(doc.change, const Money.rupees(50));
    });

    test('has no cash block when nothing was tendered', () {
      final doc = ReceiptDocument.fromBill(gstBill(), pilotLocation);
      expect(doc.cashTendered, isNull);
      expect(doc.change, isNull);
    });

    test('has no GST block while taxLines is empty (D-013)', () {
      final doc = ReceiptDocument.fromBill(normalBill(), pilotLocation);
      expect(doc.gst, isNull);
    });

    test('has a GST block once the bill has tax lines', () {
      const withGstin = Location(
        code: 'PTB',
        name: 'Caramel Cottage',
        address: 'Pattambi',
        phone: '0',
        gstin: '32ABCDE1234F1Z5',
        overridePinHash: 'x',
        receiptFooter: '',
        nextDeviceNo: 2,
        active: true,
      );
      final bill = gstBill();
      final gst = ReceiptDocument.fromBill(bill, withGstin).gst!;
      expect(gst.gstin, '32ABCDE1234F1Z5');
      expect(gst.taxableValue, bill.taxableValue);
      expect(gst.lines.single.rate, 5);
      expect(gst.lines.single.tax, const Money(4250));
    });

    test('marks a reprint', () {
      final doc = ReceiptDocument.fromBill(
        normalBill(),
        pilotLocation,
        reprint: true,
      );
      expect(doc.reprint, isTrue);
      expect(doc.isCancelled, isFalse);
    });

    test('a cancelled bill always carries the banner and its reason', () {
      for (final reprint in [false, true]) {
        final doc = ReceiptDocument.fromBill(
          cancelledBill(),
          pilotLocation,
          reprint: reprint,
        );
        expect(doc.isCancelled, isTrue);
        expect(doc.cancellation!.reason, 'Wrong item billed');
        expect(doc.reprint, reprint);
      }
    });
  });

  group('ReturnSlipDocument.fromReturn', () {
    test('shows the original bill, returned lines and refunds', () {
      final bill = discountedSplitBill();
      final ret = partialReturn(bill);
      final slip = ReturnSlipDocument.fromReturn(ret, bill, pilotLocation);

      expect(slip.header.name, pilotLocation.name);
      expect(slip.returnId, 'D01-R000007');
      expect(slip.originalBillNo, 'PTB-D01-000124');
      expect(slip.reason, 'Damaged in transit');
      expect(slip.footer, pilotLocation.receiptFooter);

      expect(slip.lines.map((l) => l.name), [redVelvetJar.name, plumCake.name]);
      expect(slip.lines.map((l) => l.qty), [1, 1]);
      expect(slip.lines.map((l) => l.amount), ret.lines.map((l) => l.amount));
      expect(slip.refundTotal, ret.refundTotal);
      expect(slip.refundTotal.isWholeRupees, isTrue);
      expect(slip.refunds.single.amount, ret.refundTotal);

      final ist = slip.issuedAtIst;
      expect([ist.day, ist.hour, ist.minute], [26, 11, 2]);
    });
  });
}
