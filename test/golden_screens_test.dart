// Visual renders of every screen, produced by the Flutter framework's
// software rasterizer in a VM widget test on the CI runner - NOT Android
// device execution. Fonts are real (Roboto via golden_toolkit), so these
// PNGs show the actual UI layout, colours and text as coded.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_billing/data.dart';
import 'package:shop_billing/main.dart';
import 'package:shop_billing/ui.dart';
import 'package:shop_billing/bills.dart';
import 'package:shop_billing/new_bill.dart';
import 'package:shop_billing/returns.dart';
import 'package:shop_billing/misc.dart';
import 'package:shop_billing/invoice.dart';

Widget wrap(Widget w) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          scaffoldBackgroundColor: kBg,
          colorScheme: ColorScheme.fromSeed(seedColor: kNavy, primary: kNavy),
          appBarTheme: const AppBarTheme(
              backgroundColor: kNavy,
              foregroundColor: Colors.white,
              elevation: 0)),
      home: w,
    );

Future<void> settleShort(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('shopdb_goldens');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    await loadAppFonts();
    // The brand title uses fontFamily 'serif' (the phone's platform serif on
    // a real device). The test renderer has no 'serif' and falls back to Ahem
    // blocks, so register real glyphs under that family name.
    final serif = FontLoader('serif')
      ..addFont(
          rootBundle.load('packages/golden_toolkit/fonts/Roboto-Regular.ttf'));
    await serif.load();
    await Brand.load();
  });

  const phone = Size(412, 892);
  int billId = 0;

  testGoldens('all screens render with seeded shop data', (tester) async {
    // Seed in a real-async zone (FakeAsync would hang the sqflite FFI awaits).
    // screenMatchesGolden manages its own runAsync + pumpAndSettle per shot,
    // which also lets each page's async DB load complete before capture - so
    // no outer runAsync may wrap it (reentrant runAsync is denied).
    await tester.runAsync(() async {
    // Seed: two customers, two bills (one rental with deposit, one sale),
    // one inventory item - enough for every screen to show real content.
    billId = await AppDb.addBill(
      customerName: 'Meera Sharma',
      mobile: '98000111222',
      address: 'Gandhi Chowk',
      type: 'WEDDING',
      billDate: AppDb.todayIso(),
      returnDate: AppDb.todayIso(),
      items: [
        {'description': 'Banarasi lehenga rental', 'colour': 'Maroon', 'details': 'heavy zari', 'kind': 'RENTAL', 'qty': 1, 'days': 3, 'rate': 1500},
        {'description': 'Dupatta', 'kind': 'SALE', 'qty': 2, 'rate': 400},
        {'description': 'Blouse stitching', 'kind': 'ORDER', 'qty': 1, 'rate': 1200},
      ],
      advance: 1000,
      depositAgreed: 5000,
      depositCollected: 2000,
    );
    await AppDb.addBill(
      customerName: '',
      type: 'SALE',
      billDate: AppDb.todayIso(),
      items: [
        {'description': 'Cotton saree', 'kind': 'SALE', 'qty': 3, 'rate': 650},
      ],
      advance: 500,
    );
    await AppDb.addInventoryItem('Banarasi lehenga', 'Lehengas', 4, null, 1500);
    await AppDb.addInventoryItem('Cotton saree', 'Sarees', 25, 650, null);
    });

    final shots = <String, Widget>{
      '01_shell_home': const Shell(),
      '02_new_bill': const NewBillPage(),
      '03_bills_list': Scaffold(body: BillsPage(onOpenBill: (_) {})),
      '04_bill_detail': BillDetailPage(billId: billId),
      '06_returns': Scaffold(body: ReturnsPage(onOpenBill: (_) {})),
      '07_stock': const StockPage(),
      '08_customers': const CustomersPage(),
      '09_reports': const ReportsPage(),
      '10_settings': const SettingsPage(),
      '11_more': const MorePage(),
    };
    // Pump INSIDE a real-async zone: pages load their DB data in initState,
    // and futures created in the fake zone never complete (Home captured with
    // zero stats proved this in run 13). screenMatchesGolden is called after,
    // sequentially - it manages its own runAsync for asset priming + capture.
    for (final e in shots.entries) {
      await tester.runAsync(() async {
        await tester.pumpWidgetBuilder(e.value, wrapper: wrap, surfaceSize: phone);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      await screenMatchesGolden(tester, e.key);
    }

    // Invoice needs the seeded bill + items as plain maps.
    await tester.runAsync(() async {
      final bill = (await AppDb.getBill(billId))!;
      final items = await AppDb.billItems(billId);
      await tester.pumpWidgetBuilder(InvoicePage(bill: bill, items: items),
          wrapper: wrap, surfaceSize: phone);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await screenMatchesGolden(tester, '05_invoice');
  });
}
