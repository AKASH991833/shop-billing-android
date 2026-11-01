// Audit of the New Bill live totals card (run-17 review follow-up): with
// nonzero mixed input every figure must stay on a reconcilable basis -
//   Items Total = sum of line amounts (rental = qty x days x rate)
//   To Collect Now = Items Total + Deposit collected
//   Balance Due (items) = Items Total - Advance
// Deposit money is refundable and never counted as items revenue.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_billing/new_bill.dart';

LineForm line(String kind, String qty, String days, String rate) {
  final l = LineForm();
  l.kind = kind;
  l.qty.text = qty;
  l.days.text = days;
  l.rate.text = rate;
  return l;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('shopdb_newbill');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
  });

  Future<dynamic> pumpForm(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: NewBillPage()));
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      }
    });
    return tester.state(find.byType(NewBillPage));
  }

  testWidgets('nonzero mixed bill: 6500 + 2000 = 8500, balance 5500',
      (tester) async {
    final st = await pumpForm(tester);
    final lines = st.lines as List<LineForm>;
    lines.clear();
    lines.addAll([
      line('RENTAL', '1', '3', '1500'), // 4500
      line('SALE', '2', '1', '400'), //    800
      line('ORDER', '1', '1', '1200'), // 1200
    ]);
    st.advance.text = '1000';
    st.deposit.text = '2000';
    st.setState(() {});
    await tester.pump();

    expect(find.text('₹6,500'), findsOneWidget); // Items Total
    expect(find.text('₹2,000'), findsOneWidget); // Deposit collected
    expect(find.text('₹8,500'), findsOneWidget); // To Collect Now
    expect(find.text('₹1,000'), findsOneWidget); // Advance
    expect(find.text('₹5,500'), findsOneWidget); // Balance Due (items)
    expect(find.text('Deposit collected (refundable, not revenue)'),
        findsOneWidget);
  });

  testWidgets('no-deposit sale: To Collect Now equals items, balance nets advance',
      (tester) async {
    final st = await pumpForm(tester);
    final lines = st.lines as List<LineForm>;
    lines.clear();
    lines.add(line('SALE', '3', '1', '650')); // 1950
    st.advance.text = '500';
    st.deposit.text = '0';
    st.setState(() {});
    await tester.pump();

    expect(find.text('₹1,950'), findsWidgets); // Items Total == To Collect Now
    expect(find.text('₹500'), findsOneWidget); // Advance
    expect(find.text('₹1,450'), findsOneWidget); // Balance Due (items)
  });
}
