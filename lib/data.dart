import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// SQLite data layer. Port of the desktop billing schema, with two deliberate
/// upgrades: payments are purpose-tagged (CHARGES vs DEPOSIT) at entry, and
/// deposits track the collected amount explicitly - so charge receivable,
/// outstanding deposit and deposit held are always three separate numbers.
class AppDb {
  static Database? _db;
  static Future<Database>? _opening;

  /// Test helper: close and drop the cached connection so the next [open]
  /// reopens the database file (simulates an app restart).
  static Future<void> debugClose() async {
    await _db?.close();
    _db = null;
  }

  static Future<Database> open() async {
    if (_db != null && _db!.isOpen) return _db!;
    if (_opening != null) return _opening!;
    _opening = _openInner();
    try {
      _db = await _opening!;
    } finally {
      _opening = null;
    }
    return _db!;
  }

  static Future<Database> _openInner() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(p.join(dir, 'shop.db'), version: 1,
        onCreate: (db, v) async {
      final b = db.batch();
      b.execute(
          "CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL DEFAULT '', mobile TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)");
      b.execute(
          "CREATE TABLE bills(id INTEGER PRIMARY KEY AUTOINCREMENT, bill_no TEXT UNIQUE NOT NULL, customer_id INTEGER NOT NULL REFERENCES customers(id), type TEXT NOT NULL CHECK(type IN ('SALE','RENTAL','WEDDING')), bill_date TEXT NOT NULL, event_date TEXT, return_date TEXT, returned_at TEXT, created_at TEXT NOT NULL)");
      b.execute(
          "CREATE TABLE bill_items(id INTEGER PRIMARY KEY AUTOINCREMENT, bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE, description TEXT NOT NULL, colour TEXT NOT NULL DEFAULT '', details TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL DEFAULT 'SALE' CHECK(kind IN ('SALE','RENTAL','ORDER')), qty REAL NOT NULL DEFAULT 1, days REAL NOT NULL DEFAULT 1, rate REAL NOT NULL DEFAULT 0, amount REAL NOT NULL)");
      b.execute(
          "CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT, bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE, paid_at TEXT NOT NULL, amount REAL NOT NULL, mode TEXT NOT NULL DEFAULT 'Cash', purpose TEXT NOT NULL DEFAULT 'CHARGES' CHECK(purpose IN ('CHARGES','DEPOSIT')), note TEXT NOT NULL DEFAULT '')");
      b.execute(
          "CREATE TABLE deposits(id INTEGER PRIMARY KEY AUTOINCREMENT, bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE, amount REAL NOT NULL, collected_amount REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'HELD' CHECK(status IN ('HELD','REFUNDED','PARTIALLY_REFUNDED')), refunded_amount REAL NOT NULL DEFAULT 0, deduction REAL NOT NULL DEFAULT 0, deduction_note TEXT NOT NULL DEFAULT '', refunded_at TEXT)");
      b.execute(
          "CREATE TABLE inventory(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL DEFAULT '', total_qty REAL NOT NULL DEFAULT 0, sale_price REAL, rent_rate_day REAL, active INTEGER NOT NULL DEFAULT 1)");
      b.execute("CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)");
      await b.commit(noResult: true);
    });
    return _db!;
  }

  static String todayIso() =>
      DateTime.now().toLocal().toIso8601String().substring(0, 10);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String disp(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final d = DateTime.parse(iso);
      return '${d.day} ${_months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  static String _now() => DateTime.now().toLocal().toIso8601String();

  static Future<int> _nextBillNo(Database db) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM bills');
    return ((r.first['n'] as int?) ?? 0) + 1;
  }

  /// Customer name/mobile/address all optional; blank customers stay distinct
  /// walk-in records (same rule as the desktop app).
  static Future<int> _addCustomer(
      Database db, String name, String mobile, String address) async {
    name = name.trim();
    mobile = mobile.trim();
    address = address.trim();
    if (name.isNotEmpty && mobile.isNotEmpty) {
      final rows = await db.rawQuery(
          'SELECT id FROM customers WHERE name=? AND mobile=? ORDER BY id LIMIT 1',
          [name, mobile]);
      if (rows.isNotEmpty) {
        if (address.isNotEmpty) {
          await db.rawUpdate(
              'UPDATE customers SET address=? WHERE id=?', [address, rows.first['id']]);
        }
        return rows.first['id'] as int;
      }
    }
    return await db.rawInsert(
        'INSERT INTO customers(name,mobile,address,created_at) VALUES(?,?,?,?)',
        [name, mobile, address, _now()]);
  }

  /// items: {description, colour, details, kind(SALE|RENTAL|ORDER), qty, days, rate}
  /// advance: payment toward CHARGES. depositAgreed/depositCollected track the
  /// refundable security deposit explicitly - never mixed into revenue.
  static Future<int> addBill({
    required String customerName,
    String mobile = '',
    String address = '',
    required String type,
    required String billDate,
    String? eventDate,
    String? returnDate,
    required List<Map<String, Object?>> items,
    double advance = 0,
    String advanceMode = 'Cash',
    double depositAgreed = 0,
    double depositCollected = 0,
  }) async {
    final db = await open();
    if (items.isEmpty) throw ArgumentError('Add at least one item');
    if (depositCollected > depositAgreed + 1e-9) {
      throw ArgumentError('Deposit collected cannot exceed the agreed deposit');
    }
    late int billId;
    await db.transaction((txn) async {
      final cid = await _addCustomerIn(txn, customerName, mobile, address);
      final no = (await _nextBillNoIn(txn)).toString().padLeft(3, '0');
      billId = await txn.rawInsert(
          'INSERT INTO bills(bill_no,customer_id,type,bill_date,event_date,return_date,created_at) VALUES(?,?,?,?,?,?,?)',
          [no, cid, type, billDate, eventDate, returnDate, _now()]);
      for (final it in items) {
        final kind = it['kind'] as String;
        final qty = (it['qty'] as num).toDouble();
        final days = kind == 'RENTAL' ? (it['days'] as num).toDouble() : 1.0;
        final rate = (it['rate'] as num).toDouble();
        final amt = kind == 'RENTAL' ? qty * days * rate : qty * rate;
        await txn.rawInsert(
            'INSERT INTO bill_items(bill_id,description,colour,details,kind,qty,days,rate,amount) VALUES(?,?,?,?,?,?,?,?,?)',
            [
              billId,
              it['description'] as String,
              (it['colour'] as String?) ?? '',
              (it['details'] as String?) ?? '',
              kind,
              qty,
              days,
              rate,
              amt
            ]);
      }
      if (advance > 0) {
        await txn.rawInsert(
            'INSERT INTO payments(bill_id,paid_at,amount,mode,purpose) VALUES(?,?,?,?,?)',
            [billId, _now(), advance, advanceMode, 'CHARGES']);
      }
      if (depositAgreed > 0) {
        await txn.rawInsert(
            'INSERT INTO deposits(bill_id,amount,collected_amount) VALUES(?,?,?)',
            [billId, depositAgreed, depositCollected]);
        if (depositCollected > 0) {
          await txn.rawInsert(
              'INSERT INTO payments(bill_id,paid_at,amount,mode,purpose) VALUES(?,?,?,?,?)',
              [billId, _now(), depositCollected, advanceMode, 'DEPOSIT']);
        }
      }
    });
    return billId;
  }

  static Future<int> _addCustomerIn(
      Transaction txn, String name, String mobile, String address) async {
    name = name.trim();
    mobile = mobile.trim();
    address = address.trim();
    if (name.isNotEmpty && mobile.isNotEmpty) {
      final rows = await txn.rawQuery(
          'SELECT id FROM customers WHERE name=? AND mobile=? ORDER BY id LIMIT 1',
          [name, mobile]);
      if (rows.isNotEmpty) {
        if (address.isNotEmpty) {
          await txn.rawUpdate(
              'UPDATE customers SET address=? WHERE id=?', [address, rows.first['id']]);
        }
        return rows.first['id'] as int;
      }
    }
    return await txn.rawInsert(
        'INSERT INTO customers(name,mobile,address,created_at) VALUES(?,?,?,?)',
        [name, mobile, address, _now()]);
  }

  static Future<int> _nextBillNoIn(Transaction txn) async {
    final r = await txn.rawQuery('SELECT COUNT(*) AS n FROM bills');
    return ((r.first['n'] as int?) ?? 0) + 1;
  }

  static const _billQuery = """
SELECT b.id, b.bill_no, b.type, b.bill_date, b.customer_id, b.event_date, b.return_date, b.returned_at,
       c.name AS customer, c.mobile, c.address AS customer_address,
       IFNULL((SELECT SUM(amount) FROM bill_items WHERE bill_id=b.id),0) AS charges,
       IFNULL((SELECT SUM(amount) FROM payments WHERE bill_id=b.id AND purpose='CHARGES'),0) AS paid_charges,
       IFNULL((SELECT SUM(amount) FROM deposits WHERE bill_id=b.id),0) AS deposit,
       IFNULL((SELECT SUM(collected_amount) FROM deposits WHERE bill_id=b.id),0) AS deposit_collected,
       IFNULL((SELECT SUM(refunded_amount) FROM deposits WHERE bill_id=b.id),0) AS deposit_refunded,
       IFNULL((SELECT SUM(deduction) FROM deposits WHERE bill_id=b.id),0) AS deposit_deduction,
       IFNULL((SELECT GROUP_CONCAT(DISTINCT kind) FROM bill_items WHERE bill_id=b.id),'') AS kinds
FROM bills b JOIN customers c ON c.id=b.customer_id
""";

  /// Three separate money views of a bill: charge receivable, outstanding
  /// deposit to collect, and deposit actually held (refundable).
  static Map<String, Object?> totals(Map<String, Object?> r) {
    final charges = (r['charges'] as num).toDouble();
    final paidCharges = (r['paid_charges'] as num).toDouble();
    final deposit = (r['deposit'] as num).toDouble();
    final collected = (r['deposit_collected'] as num).toDouble();
    final refunded = (r['deposit_refunded'] as num).toDouble();
    final deduction = (r['deposit_deduction'] as num).toDouble();
    return {
      'charges': charges,
      'paid_charges': paidCharges,
      'balance_charges': charges - paidCharges,
      'deposit': deposit,
      'deposit_outstanding': deposit - collected,
      'deposit_held': collected - refunded - deduction,
      'total_to_pay': charges + (deposit - collected),
      // Raw deposit fields re-emitted as doubles: SQLite IFNULL(SUM(...),0)
      // returns INTEGER when no deposit rows exist, and callers cast to double.
      'deposit_collected': collected,
      'deposit_refunded': refunded,
      'deposit_deduction': deduction,
    };
  }

  static String displayType(Map<String, Object?> r) {
    final kinds = ((r['kinds'] as String?) ?? '')
        .split(',')
        .where((k) => k.isNotEmpty)
        .toSet();
    if (kinds.length <= 1) {
      final t = (r['type'] as String?) ?? '';
      return t.isEmpty ? '' : t[0] + t.substring(1).toLowerCase();
    }
    return 'Mixed';
  }

  static Future<List<Map<String, Object?>>> listBills({String? typeFilter}) async {
    final db = await open();
    final rows = await db.rawQuery(
        _billQuery +
            (typeFilter != null ? ' WHERE b.type=?' : '') +
            ' ORDER BY b.bill_date DESC, b.bill_no DESC',
        typeFilter != null ? [typeFilter] : null);
    return rows.map((r) {
      final m = Map<String, Object?>.from(r)..addAll(totals(r));
      final bal = (m['balance_charges'] as double) + (m['deposit_outstanding'] as double);
      final paid = (m['paid_charges'] as double) + (m['deposit_collected'] as double);
      var status = bal <= 0 ? 'Paid' : (paid > 0 ? 'Advance' : 'Unpaid');
      if (((r['kinds'] as String?) ?? '').contains('RENTAL') &&
          r['return_date'] != null &&
          r['returned_at'] == null) {
        status = 'Active';
      }
      m['status'] = status;
      return m;
    }).toList();
  }

  static Future<Map<String, Object?>?> getBill(int id) async {
    final db = await open();
    final rows = await db.rawQuery('$_billQuery WHERE b.id=?', [id]);
    if (rows.isEmpty) return null;
    final m = Map<String, Object?>.from(rows.first)..addAll(totals(rows.first));
    return m;
  }

  static Future<List<Map<String, Object?>>> billItems(int billId) async {
    final db = await open();
    return db.rawQuery(
        'SELECT * FROM bill_items WHERE bill_id=? ORDER BY id', [billId]);
  }

  static Future<List<Map<String, Object?>>> billPayments(int billId) async {
    final db = await open();
    return db.rawQuery(
        'SELECT * FROM payments WHERE bill_id=? ORDER BY paid_at DESC, id DESC',
        [billId]);
  }

  /// Later payment against a bill, purpose-tagged at entry. Charges payments are
  /// capped at the remaining charge balance; deposit payments at the outstanding
  /// deposit. No inferred allocation.
  static Future<void> addPayment(int billId, double amount, String mode,
      {String purpose = 'CHARGES'}) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive');
    final db = await open();
    final bill = await getBill(billId);
    if (bill == null) throw ArgumentError('Bill not found');
    if (purpose == 'DEPOSIT') {
      final out = bill['deposit_outstanding'] as double;
      if (amount > out + 1e-9) {
        throw ArgumentError(
            'Payment exceeds the outstanding deposit of ${out.round()}');
      }
      await db.rawUpdate(
          'UPDATE deposits SET collected_amount = collected_amount + ? WHERE bill_id=?',
          [amount, billId]);
    } else {
      final bal = bill['balance_charges'] as double;
      if (amount > bal + 1e-9) {
        throw ArgumentError(
            'Payment exceeds the remaining balance of ${bal.round()}');
      }
    }
    await db.rawInsert(
        'INSERT INTO payments(bill_id,paid_at,amount,mode,purpose) VALUES(?,?,?,?,?)',
        [billId, _now(), amount, mode, purpose]);
  }

  /// Marks garments physically back. Does NOT touch the deposit - the refund is
  /// a separate money event via recordDepositRefund (same rule as desktop).
  static Future<void> markReturned(int billId, String returnedAt) async {
    final db = await open();
    await db.rawUpdate('UPDATE bills SET returned_at=? WHERE id=?',
        [returnedAt, billId]);
  }

  static Future<void> recordDepositRefund(int billId, double refundAmount,
      {double deduction = 0, String note = ''}) async {
    final db = await open();
    final rows = await db
        .rawQuery('SELECT * FROM deposits WHERE bill_id=?', [billId]);
    if (rows.isEmpty) throw ArgumentError('No deposit on this bill');
    final dep = rows.first;
    if ((dep['status'] as String) == 'REFUNDED') {
      throw ArgumentError('Deposit already settled - no second refund');
    }
    final held = (dep['collected_amount'] as num).toDouble() -
        (dep['refunded_amount'] as num).toDouble() -
        (dep['deduction'] as num).toDouble();
    if (refundAmount + deduction > held + 1e-9) {
      throw ArgumentError(
          'Refund + deduction exceeds the held deposit of ${held.round()}');
    }
    final settled =
        refundAmount + deduction >= held - 1e-9 ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
    await db.rawUpdate(
        'UPDATE deposits SET status=?, refunded_amount=refunded_amount+?, deduction=deduction+?, deduction_note=?, refunded_at=? WHERE bill_id=?',
        [settled, refundAmount, deduction, note, _now(), billId]);
  }

  static Future<Map<String, double>> dashboard() async {
    final bills = await listBills();
    final today = todayIso();
    double sales = 0, rentOrder = 0, pending = 0;
    final db = await open();
    for (final b in bills) {
      pending += (b['balance_charges'] as double);
    }
    final todayIds = bills
        .where((b) => b['bill_date'] == today)
        .map((b) => b['id'] as int)
        .toList();
    if (todayIds.isNotEmpty) {
      final ph = List.filled(todayIds.length, '?').join(',');
      final rows = await db.rawQuery(
          'SELECT kind, SUM(amount) AS s FROM bill_items WHERE bill_id IN ($ph) GROUP BY kind',
          todayIds);
      for (final r in rows) {
        final k = r['kind'] as String;
        final s = (r['s'] as num).toDouble();
        if (k == 'SALE') {
          sales += s;
        } else {
          rentOrder += s;
        }
      }
    }
    final depRows = await db.rawQuery(
        "SELECT IFNULL(SUM(collected_amount - refunded_amount - deduction),0) AS h FROM deposits WHERE status != 'REFUNDED'");
    final held = (depRows.first['h'] as num).toDouble();
    return {'sales': sales, 'rent_order': rentOrder, 'pending': pending, 'deposits': held};
  }

  static Future<List<Map<String, Object?>>> rentalsDue(
      {int withinDays = 7}) async {
    final db = await open();
    final today = todayIso();
    final limit = DateTime.now()
        .add(Duration(days: withinDays))
        .toLocal()
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(
        """SELECT bi.description, bi.qty, b.id AS bill_id, b.bill_no, b.return_date, c.name AS customer
FROM bill_items bi JOIN bills b ON b.id=bi.bill_id JOIN customers c ON c.id=b.customer_id
WHERE bi.kind='RENTAL' AND b.returned_at IS NULL AND b.return_date IS NOT NULL
  AND b.return_date >= ? AND b.return_date <= ?
ORDER BY b.return_date""",
        [today, limit]);
  }

  static Future<List<Map<String, Object?>>> activeRentals() async {
    final db = await open();
    return db.rawQuery(
        """SELECT bi.description, bi.qty, bi.days, bi.rate, b.id AS bill_id, b.bill_no, b.return_date, c.name AS customer,
       IFNULL((SELECT SUM(d.collected_amount - d.refunded_amount - d.deduction) FROM deposits d WHERE d.bill_id=b.id AND d.status != 'REFUNDED'),0) AS deposit_held
FROM bill_items bi JOIN bills b ON b.id=bi.bill_id JOIN customers c ON c.id=b.customer_id
WHERE bi.kind='RENTAL' AND b.returned_at IS NULL
ORDER BY b.return_date IS NULL, b.return_date""");
  }

  static Future<List<Map<String, Object?>>> listInventory() async {
    final db = await open();
    final items = await db
        .rawQuery('SELECT * FROM inventory WHERE active=1 ORDER BY name');
    final today = todayIso();
    final out = <Map<String, Object?>>[];
    for (final it in items) {
      final rented = await db.rawQuery(
          """SELECT IFNULL(SUM(bi.qty),0) AS q FROM bill_items bi JOIN bills b ON b.id=bi.bill_id
WHERE bi.kind='RENTAL' AND bi.description=? AND b.returned_at IS NULL
  AND (b.return_date IS NULL OR b.return_date >= ?)""",
          [it['name'], today]);
      out.add(Map<String, Object?>.from(it)
        ..['rented_out'] = (rented.first['q'] as num).toDouble());
    }
    return out;
  }

  static Future<int> addInventoryItem(String name, String category,
      double totalQty, double? salePrice, double? rentRateDay) async {
    final db = await open();
    return db.rawInsert(
        'INSERT INTO inventory(name,category,total_qty,sale_price,rent_rate_day) VALUES(?,?,?,?,?)',
        [name.trim(), category, totalQty, salePrice, rentRateDay]);
  }

  static Future<List<Map<String, Object?>>> listCustomers() async {
    final db = await open();
    return db.rawQuery(
        """SELECT c.*, (SELECT COUNT(*) FROM bills b WHERE b.customer_id=c.id) AS bill_count,
       IFNULL((SELECT SUM(bi.amount) FROM bill_items bi JOIN bills b ON b.id=bi.bill_id WHERE b.customer_id=c.id),0)
         - IFNULL((SELECT SUM(py.amount) FROM payments py JOIN bills b ON b.id=py.bill_id WHERE b.customer_id=c.id AND py.purpose='CHARGES'),0) AS charges_due
FROM customers c ORDER BY c.id DESC""");
  }

  static Future<Map<String, double>> report(String fromIso, String toIso) async {
    final db = await open();
    final rows = await db.rawQuery(
        """SELECT bi.kind, SUM(bi.amount) AS s FROM bill_items bi JOIN bills b ON b.id=bi.bill_id
WHERE b.bill_date >= ? AND b.bill_date <= ? GROUP BY bi.kind""",
        [fromIso, toIso]);
    double sales = 0, rentOrder = 0;
    for (final r in rows) {
      final s = (r['s'] as num).toDouble();
      if (r['kind'] == 'SALE') {
        sales += s;
      } else {
        rentOrder += s;
      }
    }
    final coll = await db.rawQuery(
        "SELECT IFNULL(SUM(amount),0) AS c FROM payments WHERE purpose='CHARGES' AND paid_at >= ? AND paid_at <= ?",
        ['${fromIso}T00:00:00', '${toIso}T23:59:59']);
    final bills = await listBills();
    double pending = 0;
    for (final b in bills) {
      pending += (b['balance_charges'] as double);
    }
    final dep = await db.rawQuery(
        "SELECT IFNULL(SUM(collected_amount - refunded_amount - deduction),0) AS h FROM deposits WHERE status != 'REFUNDED'");
    return {
      'sales': sales,
      'rent_order': rentOrder,
      'collected': (coll.first['c'] as num).toDouble(),
      'pending': pending,
      'deposits_held': (dep.first['h'] as num).toDouble()
    };
  }

  static Future<String> setting(String key, {String fallback = ''}) async {
    final db = await open();
    final r = await db
        .rawQuery('SELECT value FROM settings WHERE key=?', [key]);
    if (r.isEmpty) return fallback;
    return (r.first['value'] as String?) ?? fallback;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await open();
    await db.rawInsert(
        'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [key, value]);
  }
}
