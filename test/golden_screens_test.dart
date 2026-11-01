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
          // Harness-only: the test renderer's default font is Ahem (blocks)
          // and fallback per-family is flaky (run 17's More-page tagline).
          // Pin the default family to the loaded Roboto so every capture is
          // deterministic. The app's real default font on-device is the
          // platform default, which stays unverified by these renders.
          fontFamily: 'Roboto',
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
      // Isolated minimal repro for the run-17/18 More-page tagline blocks:
      // the SAME brandHeader widget rendered readable on Home but as blocks
      // on More, with identical ASCII content (DIAG-proven). If this bare
      // capture is readable while 11_more blocks again, the cause is
      // context-dependent in the harness renderer, not the app widget.
      '00_brand_header_bare': brandHeader(),
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
    // zero stats proved this in run 13). Run 16 proved 8 quick pumps inside
    // runAsync are NOT enough either - every data page captured empty and
    // BillDetailPage stayed on its spinner, then screenMatchesGolden's
    // default pumpAndSettle hung on that infinite animation. Fixes:
    //  1. real Future.delayed waits inside runAsync (real event-loop time,
    //     not just yields) so FFI DB futures actually finish;
    //  2. DIAG probes that query the same data directly in the same zone, so
    //     a failure distinguishes "DB unreachable here" from "page load stuck";
    //  3. customPump single-pump on screenMatchesGolden so a still-spinning
    //     page captures honestly instead of timing out the whole run.
    for (final e in shots.entries) {
      await tester.runAsync(() async {
        await tester.pumpWidgetBuilder(e.value, wrapper: wrap, surfaceSize: phone);
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
        }
        final spinner =
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        final errors = find.byType(ErrorWidget).evaluate().length;
        final probe = await AppDb.listBills()
            .timeout(const Duration(seconds: 5), onTimeout: () => const []);
        print('DIAG ${e.key}: spinner=$spinner errorWidgets=$errors '
            'directListBills=${probe.length}');
        if (e.key == '01_shell_home') {
          // Run 17: the More-page tagline captured as block glyphs while the
          // identical Home header rendered fine - print the exact string so
          // the content question (exotic codepoints vs renderer fallback)
          // is settled by evidence.
          print('DIAG brand.tagline="${Brand.value.tagline}" '
              'codes=${Brand.value.tagline.codeUnits}');
        }
        if (e.key == '04_bill_detail') {
          final b = await AppDb.getBill(billId)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          print('DIAG 04 directGetBill(billId=$billId)=' +
              (b == null ? 'NULL/TIMEOUT' : 'FOUND bill_no=${b["bill_no"]}'));
        }
      });
      await screenMatchesGolden(tester, e.key,
          customPump: (t) async => t.pump());
    }

    // Invoice needs the seeded bill + items as plain maps.
    await tester.runAsync(() async {
      final bill = (await AppDb.getBill(billId))!;
      final items = await AppDb.billItems(billId);
      await tester.pumpWidgetBuilder(InvoicePage(bill: bill, items: items),
          wrapper: wrap, surfaceSize: phone);
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
      print('DIAG 05_invoice: spinner=' +
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty.toString());
    });
    await screenMatchesGolden(tester, '05_invoice',
        customPump: (t) async => t.pump());
  });
}
