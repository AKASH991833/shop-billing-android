// Regression for the run-17 review finding: the printed invoice totals must
// reconcile arithmetically and keep charges and deposits on separate,
// clearly-labelled bases - no mixed-base "To Collect" and no invented
// business policy ("deposit refunded on safe return").
//
// Mixed settlement fixture: items 6500 (rental 4500 + sale 800 + order 1200),
// advance paid 1000, deposit agreed 5000 with 2000 collected.
//   6500 - 1000 = 5500 items balance
//   5000 - 2000 = 3000 deposit outstanding
//   5500 + 3000 = 8500 total outstanding
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_billing/invoice.dart';

Map<String, Object?> bill({
  required double charges,
  required double paidCharges,
  required double deposit,
  required double depositCollected,
  String type = 'WEDDING',
  String? returnDate,
}) =>
    {
      'bill_no': '001',
      'customer': 'Meera Sharma',
      'customer_id': 1,
      'mobile': '98000111222',
      'type': type,
      'bill_date': '2026-11-01',
      'return_date': returnDate,
      'charges': charges,
      'paid_charges': paidCharges,
      'balance_charges': charges - paidCharges,
      'deposit': deposit,
      'deposit_collected': depositCollected,
      'deposit_outstanding': deposit - depositCollected,
      'total_to_pay': charges + (deposit - depositCollected),
    };

void main() {
  testWidgets('mixed settlement: charges and deposits reconcile on separate bases',
      (tester) async {
    final b = bill(
        charges: 6500,
        paidCharges: 1000,
        deposit: 5000,
        depositCollected: 2000,
        returnDate: '2026-11-01');
    final items = <Map<String, Object?>>[
      {'description': 'Banarasi lehenga rental', 'kind': 'RENTAL', 'qty': 1.0, 'days': 3.0, 'rate': 1500.0, 'amount': 4500.0},
      {'description': 'Dupatta', 'kind': 'SALE', 'qty': 2.0, 'days': 1.0, 'rate': 400.0, 'amount': 800.0},
      {'description': 'Blouse stitching', 'kind': 'ORDER', 'qty': 1.0, 'days': 1.0, 'rate': 1200.0, 'amount': 1200.0},
    ];
    await tester.pumpWidget(MaterialApp(home: InvoicePage(bill: b, items: items)));
    await tester.pump();

    // Charges basis: total / paid / balance.
    expect(find.textContaining('Items Total ₹6,500'), findsOneWidget);
    expect(find.textContaining('Paid ₹1,000'), findsOneWidget);
    expect(find.textContaining('Balance ₹5,500'), findsOneWidget);
    // Deposit basis: agreed / collected / outstanding.
    expect(find.textContaining('Deposit (refundable) ₹5,000'), findsOneWidget);
    expect(find.textContaining('Collected ₹2,000'), findsOneWidget);
    expect(find.textContaining('Outstanding ₹3,000'), findsOneWidget);
    // Single reconciled grand total: 5500 + 3000.
    expect(find.textContaining('Total Outstanding ₹8,500'), findsOneWidget);
    // The ambiguous mixed-base label is gone, and no invented return policy.
    expect(find.textContaining('To Collect'), findsNothing);
    expect(find.textContaining('safe return'), findsNothing);
    expect(find.textContaining('security deposit (refundable)'), findsOneWidget);
  });

  testWidgets('plain sale without deposit shows only the charges basis',
      (tester) async {
    final b = bill(
        charges: 1950, paidCharges: 500, deposit: 0, depositCollected: 0,
        type: 'SALE');
    final items = <Map<String, Object?>>[
      {'description': 'Cotton saree', 'kind': 'SALE', 'qty': 3.0, 'days': 1.0, 'rate': 650.0, 'amount': 1950.0},
    ];
    await tester.pumpWidget(MaterialApp(home: InvoicePage(bill: b, items: items)));
    await tester.pump();

    expect(find.textContaining('Items Total ₹1,950'), findsOneWidget);
    expect(find.textContaining('Paid ₹500'), findsOneWidget);
    expect(find.textContaining('Balance ₹1,450'), findsOneWidget);
    expect(find.textContaining('Deposit'), findsNothing);
    expect(find.textContaining('Total Outstanding'), findsNothing);
    expect(find.textContaining('To Collect'), findsNothing);
  });
}
