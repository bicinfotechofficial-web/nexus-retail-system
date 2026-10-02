import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('CustomerValidator', () {
    test('cleans names', () {
      expect(CustomerValidator.cleanName('  Anita   Nair '), 'Anita Nair');
    });

    test('name rules', () {
      expect(CustomerValidator.nameError('Anita'), isNull);
      expect(CustomerValidator.nameError('   '), isNotNull);
      expect(CustomerValidator.nameError('a' * 60), isNull);
      expect(CustomerValidator.nameError('a' * 61), isNotNull);
      expect(CustomerValidator.nameError('അനിത'), isNull);
    });

    test('cleans pasted numbers', () {
      expect(CustomerValidator.cleanPhone('+91 98765 43210'), '9876543210');
      expect(CustomerValidator.cleanPhone('098765-43210'), '9876543210');
      expect(CustomerValidator.cleanPhone('9876543210'), '9876543210');
    });

    test('mobile rules', () {
      expect(CustomerValidator.phoneError('9876543210'), isNull);
      expect(CustomerValidator.phoneError('+91 6000000000'), isNull);
      expect(CustomerValidator.phoneError(''), isNotNull);
      expect(CustomerValidator.phoneError('987654321'), isNotNull); // 9 digits
      expect(CustomerValidator.phoneError('98765432101'), isNotNull); // 11
      expect(CustomerValidator.phoneError('5876543210'), isNotNull); // starts 5
      expect(CustomerValidator.phoneError('abcdefghij'), isNotNull);
    });

    test('WhatsApp: null means none, otherwise a mobile', () {
      expect(CustomerValidator.whatsappError(null), isNull);
      expect(CustomerValidator.whatsappError('9876543210'), isNull);
      expect(CustomerValidator.whatsappError('123'), isNotNull);
    });
  });

  group('CustomerId', () {
    test('is stable and ignores case and spacing', () {
      final a = CustomerId.of('9876543210', 'Anita Nair');
      expect(a, CustomerId.of('9876543210', '  anita   NAIR '));
      expect(CustomerId.isValid(a), isTrue);
      expect(CustomerId.phoneOf(a), '9876543210');
    });

    test('the same mobile with another name is another customer', () {
      expect(
        CustomerId.of('9876543210', 'Anita'),
        isNot(CustomerId.of('9876543210', 'Sunil')),
      );
    });

    test('the same name on another mobile is another customer', () {
      expect(
        CustomerId.of('9876543210', 'Anita'),
        isNot(CustomerId.of('9876543211', 'Anita')),
      );
    });

    test('works for names in other scripts', () {
      final id = CustomerId.of('9876543210', 'അനിത');
      expect(CustomerId.isValid(id), isTrue);
      expect(id, isNot(CustomerId.of('9876543210', 'സുനിൽ')));
    });

    test('refuses a bad mobile, and rejects bad shapes', () {
      expect(() => CustomerId.of('123', 'A'), throwsArgumentError);
      expect(CustomerId.isValid('9876543210'), isFalse);
      expect(CustomerId.isValid('9876543210_XYZ'), isFalse);
      expect(CustomerId.isValid('98765432_aaaaaaaaaa'), isFalse);
    });
  });

  group('BillCustomer', () {
    test('cleans input and derives the ID', () {
      final c = BillCustomer(
        name: ' Anita  Nair ',
        phone: '+91 98765 43210',
        whatsapp: '98765 43210',
      );
      expect(c.name, 'Anita Nair');
      expect(c.phone, '9876543210');
      expect(c.whatsapp, '9876543210');
      expect(c.id, CustomerId.of('9876543210', 'Anita Nair'));
    });

    test('WhatsApp can be none', () {
      expect(BillCustomer(name: 'A', phone: '9876543210').whatsapp, isNull);
    });

    test('throws on invalid input', () {
      expect(
        () => BillCustomer(name: '', phone: '9876543210'),
        throwsArgumentError,
      );
      expect(
        () => BillCustomer(name: 'A', phone: '12345'),
        throwsArgumentError,
      );
      expect(
        () => BillCustomer(name: 'A', phone: '9876543210', whatsapp: '1'),
        throwsArgumentError,
      );
    });
  });

  group('Bill customer fields', () {
    final totals = BillCalculator.compute([line('p1', 2, 85000)]);

    test('a bill without a customer reads and writes as before', () {
      final b = billFrom(totals);
      expect(b.customer, isNull);
      expect(b.toMap().containsKey('customerId'), isFalse);
      expect(Bill.fromMap(b.id, b.toMap()).customer, isNull);
    });

    test('customer fields round-trip on the bill', () {
      final c = BillCustomer(
        name: 'Anita',
        phone: '9876543210',
        whatsapp: '9123456789',
      );
      final map = {...billFrom(totals).toMap(), ...c.toBillFields()};
      final back = Bill.fromMap('D01-000001', map);
      expect(back.customer?.id, c.id);
      expect(back.customer?.name, 'Anita');
      expect(back.customer?.phone, '9876543210');
      expect(back.customer?.whatsapp, '9123456789');
      expect(back.toMap()['customerWhatsapp'], '9123456789');
    });

    test('a null WhatsApp stays null', () {
      final c = BillCustomer(name: 'Anita', phone: '9876543210');
      final back = Bill.fromMap('D01-000001', {
        ...billFrom(totals).toMap(),
        ...c.toBillFields(),
      });
      expect(back.customer?.whatsapp, isNull);
      expect(back.toMap()['customerWhatsapp'], isNull);
    });

    test('a customerId without the other fields is a format error', () {
      expect(
        () => Bill.fromMap('D01-000001', {
          ...billFrom(totals).toMap(),
          'customerId': '9876543210_aaaaaaaaaa',
        }),
        throwsFormatException,
      );
    });
  });

  group('Customer', () {
    test('first() starts the counters', () {
      final bc = BillCustomer(name: 'Anita', phone: '9876543210');
      final c = Customer.first(
        customer: bc,
        total: const Money.rupees(1700),
        billId: 'D01-000001',
      );
      expect(c.billCount, 1);
      expect(c.totalSpend, const Money.rupees(1700));
      expect(c.lastWriteRef, 'D01-000001');
    });

    test('round-trips, minus server timestamps', () {
      final map = <String, Object?>{
        'name': 'Anita',
        'phone': '9876543210',
        'whatsapp': null,
        'lastBillAt': t0,
        'billCount': 3,
        'totalSpend': 450000,
        'lastWriteRef': 'D01-000009',
      };
      final c = Customer.fromMap('9876543210_aaaaaaaaaa', map);
      expect(c.lastBillAt, t0);
      expect(c.toMap(), {
        for (final e in map.entries)
          if (!Customer.serverTimestampFields.contains(e.key)) e.key: e.value,
      });
    });
  });

  group('WhatsappReceipt', () {
    final bc = BillCustomer(name: 'Anita', phone: '9876543210');

    Bill make(List<CartLine> lines, {BillCustomer? customer}) {
      final t = BillCalculator.compute(lines);
      final b = billFrom(t);
      return Bill.fromMap(b.id, {...b.toMap(), ...?customer?.toBillFields()});
    }

    test('lists lines, total and payment', () {
      final text = WhatsappReceipt.build(
        shopName: 'Caramel Cottage',
        locationName: 'Perinthalmanna',
        bill: make([line('p1', 2, 85000)], customer: bc),
      );
      expect(text, contains('*Caramel Cottage* - Perinthalmanna'));
      expect(text, contains('Bill PTB-D01-000001'));
      expect(text, contains('25-09-2026'));
      expect(text, contains('Hi Anita'));
      expect(text, contains('Item p1 x 2  ₹1,700.00'));
      expect(text, contains('*Total: ₹1,700.00*'));
      expect(text, contains('Cash: ₹1,700.00'));
      expect(text, isNot(contains('Discount')));
      expect(text, isNot(contains('9876543210')), reason: 'no number in text');
    });

    test('works for an old bill with no customer', () {
      final text = WhatsappReceipt.build(
        shopName: 'Caramel Cottage',
        locationName: 'Perinthalmanna',
        bill: make([line('p1', 1, 5000)]),
      );
      expect(text, isNot(contains('Hi ')));
    });

    test('a full bill stays under the length cap', () {
      final lines = [
        for (var i = 0; i < Limits.maxBillLines; i++)
          CartLine(
            productId: 'p$i',
            name: 'A very long cake name that goes on and on and on $i',
            qty: 10,
            unitPrice: const Money(123456),
          ),
      ];
      final text = WhatsappReceipt.build(
        shopName: 'Caramel Cottage',
        locationName: 'Perinthalmanna',
        bill: make(lines, customer: bc),
      );
      expect(text.length, lessThan(WhatsappReceipt.maxLength));
      expect(text, contains('…'));
    });

    test('link opens the customer chat with an encoded text', () {
      final uri = WhatsappReceipt.link('9876543210', 'Bill 1\nTotal ₹10');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919876543210');
      expect(uri.queryParameters['text'], 'Bill 1\nTotal ₹10');
      expect(uri.toString(), contains('%20'));
      expect(uri.toString(), isNot(contains('+')));
    });
  });
}
