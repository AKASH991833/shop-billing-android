import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_billing/data.dart';
import 'package:shop_billing/records_csv.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('shopdb_csv');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
  });

  test('export matches the desktop records format and reconciles', () async {
    await AppDb.addBill(
        customerName: 'CSV Check',
        mobile: '9000000001',
        type: 'WEDDING',
        billDate: '2026-10-20',
        returnDate: '2026-10-25',
        items: const [
          {'description': 'Saree', 'kind': 'RENTAL', 'qty': 1, 'days': 2, 'rate': 1000},
          {'description': 'Blouse', 'kind': 'SALE', 'qty': 1, 'rate': 500},
        ],
        advance: 700,
        depositAgreed: 1000,
        depositCollected: 1000);
    final csv = await buildRecordsCsv();
    final lines = csv.trim().split('\n');
    expect(lines.first,
        'No,Date,Customer,Mobile,Type,Total,Advance,Balance,Return/Delivery,Status');
    // Desktop semantics: total = charges 2500 + deposit 1000 = 3500;
    // advance = ALL received = 700 charge + 1000 deposit = 1700;
    // balance = 3500 - 1700 = 1800. The row must reconcile.
    final parsed = parseRecordsCsv(csv);
    expect(parsed.issues, isEmpty, reason: csv);
    final rec =
        parsed.records.firstWhere((r) => r['customer'] == 'CSV Check');
    expect(rec['total'], 3500.0);
    expect(rec['advance'], 1700.0);
    expect(rec['balance'], 1800.0);
    expect(rec['bill_date'], '2026-10-20');
    expect(rec['return_date'], '2026-10-25');
    expect(rec['type_label'], 'Mixed',
        reason: 'the Type column is kept verbatim as a display label');
  });

  test('import stores legacy reference with EXACT figures and never touches operational data', () async {
    final billsBefore = await AppDb.listBills();
    final from = DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10);
    final reportBefore = await AppDb.report(from, AppDb.todayIso());
    const csv = 'No,Date,Customer,Mobile,Type,Total,Advance,Balance,Return/Delivery,Status\n'
        'IMP-1,05 Oct 2026,Imported Person,9111111111,Sale,1000,400,600,-,Paid\n';
    final parsed = parseRecordsCsv(csv);
    expect(parsed.issues, isEmpty);
    expect(parsed.records.first['bill_date'], '2026-10-05',
        reason: 'zero-padded desktop dates must parse');

    final r1 = await AppDb.importLegacyRecords(parsed.records);
    expect(r1['added'], 1);
    final r2 = await AppDb.importLegacyRecords(parseRecordsCsv(csv).records);
    expect(r2['added'], 0);
    expect(r2['duplicates'], 1);

    final legacy = await AppDb.legacyRecords();
    final row = legacy.firstWhere((x) => x['bill_no'] == 'IMP-1');
    expect(row['total'], 1000.0);
    expect(row['advance'], 400.0);
    expect(row['balance'], 600.0);
    expect(row['type_label'], 'Sale');

    // Operational data is provably untouched: same bills, same report totals.
    expect((await AppDb.listBills()).length, billsBefore.length);
    expect(await AppDb.report(from, AppDb.todayIso()), reportBefore,
        reason: 'legacy imports must not enter revenue/payment/deposit reports');
  });

  test('parse: quoted cells, unpadded dates, unknown types and bad rows are reported', () {
    final p = parseRecordsCsv(
        'No,Date,Customer,Mobile,Type,Total,Advance,Balance,Return/Delivery,Status\n'
        'X1,5 Nov 2026,"Kumar, R",,Wedding,2000,0,2000,10 Nov 2026,Open\n'
        'X2,garbage-date,Bad Row,,AlienType,10,0,10,-,Open\n'
        'X3,6 Nov 2026,Reconciles Badly,,Sale,1000,0,500,-,Open\n');
    expect(p.records.length, 1,
        reason: 'only the valid row survives; bad-date and balance-mismatch rows are rejected');
    expect(p.records.first['customer'], 'Kumar, R');
    expect(p.records.first['bill_date'], '2026-11-05');
    expect(p.records.first['return_date'], '2026-11-10');
    expect(p.issues.any((i) => i.contains('unparseable')), isTrue);
    expect(p.issues.any((i) => i.contains('does not equal') && i.contains('rejected')), isTrue,
        reason: 'a stated balance that disagrees must be rejected, never adjusted');
  });
}
