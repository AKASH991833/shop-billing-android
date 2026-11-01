// Audit of the New Bill live totals card against LEDGER MEANINGS (review
// follow-up): the advance and deposit fields are money being RECEIVED at
// save time, so no line may imply already-paid money is still due.
//   Items Total          = sum of line amounts (rental = qty x days x rate)
//   Total incl. deposit  = Items Total + Deposit received  (obligation base)
//   Receiving now        = Advance + Deposit received      (cash at save)
//   Balance Due (items)  = Items Total - Advance            (remaining)
// Deposit money is refundable and never counted as items revenue. The form
// collects the full deposit at billing (agreed == collected here);
// partially-collected deposit ledgers are pinned in the data-layer tests.
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
    // The form is a lazy ListView: on the default 800x600 test surface the
    // totals card is below the fold and never builds. Enlarge the surface so
    // the whole form is laid out and findable.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
    expect(find.text('₹2,000'), findsOneWidget); // Deposit received
    expect(find.text('₹8,500'), findsOneWidget); // Total incl. deposit
    expect(find.text('₹3,000'), findsOneWidget); // Receiving now
    expect(find.text('₹5,500'), findsOneWidget); // Balance Due (items)
    expect(find.text('Total incl. deposit'), findsOneWidget);
    expect(find.text('Receiving now (advance + deposit)'), findsOneWidget);
    expect(find.text('Deposit received (refundable, not revenue)'),
        findsOneWidget);
    // The ambiguous "collect again" label must not come back.
    expect(find.text('To Collect Now'), findsNothing);
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

    expect(find.text('₹1,950'), findsWidgets); // Items Total == Total incl. deposit
    expect(find.text('₹500'), findsOneWidget); // Receiving now (advance only)
    expect(find.text('₹1,450'), findsOneWidget); // Balance Due (items)
  });

  testWidgets('fully paid bill: receiving equals total, balance is zero',
      (tester) async {
    final st = await pumpForm(tester);
    final lines = st.lines as List<LineForm>;
    lines.clear();
    lines.add(line('SALE', '3', '1', '650')); // 1950
    st.advance.text = '1950';
    st.deposit.text = '0';
    st.setState(() {});
    await tester.pump();

    expect(find.text('₹1,950'), findsWidgets); // total == receiving now
    expect(find.text('₹0'), findsWidgets); // deposit line + balance due
    expect(find.text('Balance Due (items)'), findsOneWidget);
  });
}
