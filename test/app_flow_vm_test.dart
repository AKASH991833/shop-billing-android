// Full create-bill flow driven through the real widgets on the CI runner
// (VM widget test, no emulator). Verifies UI interaction AND final DB state.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_billing/data.dart';
import 'package:shop_billing/main.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('shopdb_flow');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    await Brand.load();
  });

  Future<void> settle(WidgetTester tester, [int times = 15]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('create a sale bill through the UI and see it saved', (tester) async {
    // Real-async zone for the same FakeAsync/FFI reason (see golden test).
    await tester.runAsync(() async {
    await tester.binding.setSurfaceSize(const Size(412, 892));
    await tester.pumpWidget(const BillingApp());
    await settle(tester);
    print('CHECKPOINT: app pumped');

    // Home renders with section cards (no chart).
    expect(find.text('START WORK'), findsOneWidget);

    // Open New Bill from the Home card.
    await tester.tap(find.text('New Bill').first);
    await settle(tester);
    expect(find.text('Order Type'), findsOneWidget);
    print('CHECKPOINT: new bill page open');

    // Fill the customer name.
    final nameField = find.ancestor(
        of: find.text('Walk-in customer'),
        matching: find.byType(TextField));
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField.first, 'VM Flow Customer');
    print('CHECKPOINT: name entered');

    // Scroll the item fields into view and fill them.
    await tester.scrollUntilVisible(find.text('Item name'), 120,
        scrollable: find.byType(Scrollable).first);
    await settle(tester, 3);
    final itemField = find.ancestor(
        of: find.text('Item name'), matching: find.byType(TextField));
    await tester.enterText(itemField.first, 'VM Flow Saree');
    final rateField = find.ancestor(
        of: find.text('Rate'), matching: find.byType(TextField));
    await tester.enterText(rateField.first, '750');
    await settle(tester, 3);
    print('CHECKPOINT: item+rate entered');

    // Save and land on the bill detail. The button is a lazy ListView
    // child, so scroll it into existence first (ensureVisible cannot).
    await tester.scrollUntilVisible(find.text('Save Bill'), 250,
        scrollable: find.byType(Scrollable).first);
    await settle(tester, 3);
    print('CHECKPOINT: save button visible, tapping');
    await tester.tap(find.text('Save Bill'));
    print('CHECKPOINT: tapped, settling');
    await settle(tester);
    print('CHECKPOINT: settled after save');
    expect(find.textContaining('VM Flow Saree'), findsWidgets);

    // DB state: the bill exists with the right amount.
    print('CHECKPOINT: querying DB');
    final bills = await AppDb.listBills();
    print('CHECKPOINT: DB returned ' + bills.length.toString() + ' bills');
    final mine = bills.firstWhere(
        (b) => (b['customer'] as String).contains('VM Flow Customer'),
        orElse: () => const {});
    expect(mine, isNotEmpty);
    expect(mine['charges'], 750.0);
    expect(mine['balance_charges'], 750.0);

    // Back to Home: recent entries show the new bill.
    print('CHECKPOINT: going back');
    await tester.pageBack();
    await settle(tester);
    print('CHECKPOINT: back home');
    expect(find.text('START WORK'), findsOneWidget);
    expect(find.textContaining('RECENT ENTRIES'), findsOneWidget);
    expect(find.textContaining('750'), findsWidgets);
    });
  });
}
