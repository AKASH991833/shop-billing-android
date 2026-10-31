import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_billing/data.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('shopdb_test');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
  });

  Future<Map<String, Object?>> bill(int id) async => (await AppDb.getBill(id))!;

  test('deposit lifecycle: collect, caps, return, refund, restart', () async {
    // 1 rental (2 days x 1000) + 1 order (1500) = 3500 charges.
    // Deposit agreed 5000, only 2000 collected at billing.
    final id = await AppDb.addBill(
      customerName: 'Test Customer',
      type: 'WEDDING',
      billDate: AppDb.todayIso(),
      returnDate: AppDb.todayIso(),
      items: [
        {'description': 'Lehenga rental', 'kind': 'RENTAL', 'qty': 1, 'days': 2, 'rate': 1000},
        {'description': 'Blouse stitching', 'kind': 'ORDER', 'qty': 1, 'rate': 1500},
      ],
      advance: 500,
      depositAgreed: 5000,
      depositCollected: 2000,
    );
    var b = await bill(id);
    expect(b['charges'], 3500.0);
    expect(b['paid_charges'], 500.0);
    expect(b['balance_charges'], 3000.0);
    expect(b['deposit'], 5000.0);
    expect(b['deposit_collected'], 2000.0);
    expect(b['deposit_outstanding'], 3000.0);
    expect(b['deposit_held'], 2000.0);
    expect(b['total_to_pay'], 6500.0);

    // Overpaying charges is rejected.
    expect(AppDb.addPayment(id, 3001, 'Cash'), throwsArgumentError);
    // Depositing more than agreed at billing is rejected.
    expect(
        AppDb.addBill(
            customerName: '',
            type: 'SALE',
            billDate: AppDb.todayIso(),
            items: [
              {'description': 'X', 'kind': 'SALE', 'qty': 1, 'rate': 10}
            ],
            depositAgreed: 100,
            depositCollected: 101),
        throwsArgumentError);

    // Collect the outstanding deposit later, capped.
    expect(AppDb.addPayment(id, 3001, 'UPI', purpose: 'DEPOSIT'),
        throwsArgumentError);
    await AppDb.addPayment(id, 3000, 'UPI', purpose: 'DEPOSIT');
    b = await bill(id);
    expect(b['deposit_collected'], 5000.0);
    expect(b['deposit_outstanding'], 0.0);
    expect(b['deposit_held'], 5000.0);
    // Any further deposit payment is rejected.
    expect(AppDb.addPayment(id, 1, 'Cash', purpose: 'DEPOSIT'),
        throwsArgumentError);

    // Paying the charge balance exactly is fine.
    await AppDb.addPayment(id, 3000, 'Cash');
    b = await bill(id);
    expect(b['balance_charges'], 0.0);

    // Marking garments returned does NOT touch the deposit.
    await AppDb.markReturned(id, AppDb.todayIso());
    b = await bill(id);
    expect(b['deposit_held'], 5000.0);
    expect(b['deposit_refunded'], 0.0);

    // Refund with a damage deduction consumes the held amount exactly.
    await AppDb.recordDepositRefund(id, 4500, deduction: 500, note: 'minor damage');
    b = await bill(id);
    expect(b['deposit_held'], 0.0);
    // A second refund is rejected.
    expect(AppDb.recordDepositRefund(id, 1), throwsArgumentError);

    // Persistence across an app restart (close and reopen the DB file).
    await AppDb.debugClose();
    b = await bill(id);
    expect(b['charges'], 3500.0);
    expect(b['paid_charges'], 3500.0);
    expect(b['deposit_collected'], 5000.0);
    expect(b['deposit_refunded'], 4500.0);
    expect(b['deposit_deduction'], 500.0);
    final items = await AppDb.billItems(id);
    expect(items.length, 2);
    final pays = await AppDb.billPayments(id);
    expect(pays.where((p) => p['purpose'] == 'DEPOSIT').fold<double>(
        0, (a, p) => a + (p['amount'] as num).toDouble()), 5000.0);
  });

  test('partial refund then settlement', () async {
    final id = await AppDb.addBill(
      customerName: 'Rental Only',
      type: 'RENTAL',
      billDate: AppDb.todayIso(),
      returnDate: AppDb.todayIso(),
      items: [
        {'description': 'Sherwani', 'kind': 'RENTAL', 'qty': 1, 'days': 1, 'rate': 800}
      ],
      depositAgreed: 1000,
      depositCollected: 1000,
    );
    await AppDb.recordDepositRefund(id, 400);
    var b = await bill(id);
    expect(b['deposit_held'], 600.0);
    // refund + deduction above the held amount is rejected
    expect(AppDb.recordDepositRefund(id, 500, deduction: 200),
        throwsArgumentError);
    await AppDb.recordDepositRefund(id, 600);
    b = await bill(id);
    expect(b['deposit_held'], 0.0);
  });

  test('walk-in customer with no name or mobile is allowed', () async {
    final id = await AppDb.addBill(
      customerName: '',
      type: 'SALE',
      billDate: AppDb.todayIso(),
      items: [
        {'description': 'Saree', 'kind': 'SALE', 'qty': 1, 'rate': 700}
      ],
    );
    final b = await bill(id);
    expect(b['customer'], '');
    expect(b['charges'], 700.0);
    expect(b['total_to_pay'], 700.0);
  });

  test('rental amount is qty x days x rate', () async {
    final id = await AppDb.addBill(
      customerName: 'Multi Day',
      type: 'RENTAL',
      billDate: AppDb.todayIso(),
      items: [
        {'description': 'Jewellery set', 'kind': 'RENTAL', 'qty': 2, 'days': 3, 'rate': 500}
      ],
    );
    final b = await bill(id);
    expect(b['charges'], 3000.0);
  });
}
