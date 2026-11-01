import 'data.dart';

/// CSV export/import in the desktop app's "Export records" format. The phone
/// writes that format (desktop main.py export) and reads it back as LEGACY
/// REFERENCE; the desktop app itself has no import - movement is phone-side
/// only, by MANUAL file transfer. There is no automatic synchronization.
const recordsCsvHeader = [
  'No', 'Date', 'Customer', 'Mobile', 'Type', 'Total', 'Advance', 'Balance',
  'Return/Delivery', 'Status'
];

String csvCell(Object? v) {
  final s = '${v ?? ''}';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _n(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

/// Every bill as a CSV document in the desktop's exact column layout.
/// Total = items + deposit (the desktop's "grand"); Balance = what is still
/// outstanding on items + deposit.
Future<String> buildRecordsCsv() async {
  final rows = await AppDb.listBills();
  final out = StringBuffer()..writeln(recordsCsvHeader.map(csvCell).join(','));
  for (final r in rows) {
    out.writeln([
      r['bill_no'],
      AppDb.disp(r['bill_date'] as String?),
      r['customer'],
      r['mobile'],
      AppDb.displayType(r),
      _n((r['charges'] as num) + (r['deposit'] as num)),
      _n(r['paid_charges'] as num),
      _n((r['balance_charges'] as num) + (r['deposit_outstanding'] as num)),
      AppDb.disp((r['return_date'] ?? r['event_date']) as String?),
      r['status'],
    ].map(csvCell).join(','));
  }
  return out.toString();
}

class RecordsCsvParse {
  final List<Map<String, Object?>> records;
  final List<String> issues;
  const RecordsCsvParse(this.records, this.issues);
}

const _monthNos = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// '5 Nov 2026' or '05 Nov 2026' -> '2026-11-05'; '-'/empty -> null.
String? parseDispDate(String s) {
  final t = s.trim();
  if (t.isEmpty || t == '-') return null;
  final m = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$').firstMatch(t);
  if (m == null) return null;
  final mon = _monthNos[m.group(2)!];
  if (mon == null) return null;
  return '${m.group(3)}-${mon.toString().padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
}

List<String> _splitCsvLine(String line) {
  final cells = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      cells.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  cells.add(cur.toString());
  return cells;
}

/// Parses the desktop "records.csv" format. Bad rows are rejected and listed
/// in [RecordsCsvParse.issues] (line-numbered) - a bad row never aborts the
/// whole file. A row whose stated balance disagrees with total - advance is
/// REJECTED, never adjusted silently. The Type column is kept verbatim as a
/// display label (the desktop's labels, e.g. "Mixed (Sale + Rental)", do not
/// map onto operational types).
RecordsCsvParse parseRecordsCsv(String csv) {
  final records = <Map<String, Object?>>[];
  final issues = <String>[];
  final lines = csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  for (var ln = 0; ln < lines.length; ln++) {
    final line = lines[ln];
    if (line.trim().isEmpty) continue;
    if (ln == 0 && line.startsWith('No,')) continue; // header
    final c = _splitCsvLine(line);
    final at = 'line ${ln + 1}';
    if (c.length < 10) {
      issues.add('$at: expected 10 columns, found ${c.length} - skipped');
      continue;
    }
    final billNo = c[0].trim();
    final dateIso = parseDispDate(c[1]);
    final total = double.tryParse(c[5].trim());
    final advance = double.tryParse(c[6].trim());
    final balance = double.tryParse(c[7].trim());
    if (billNo.isEmpty || dateIso == null || total == null || advance == null || balance == null) {
      issues.add('$at: unparseable No/date/amount ("${c[0]}", "${c[1]}") - skipped');
      continue;
    }
    if ((total - advance - balance).abs() > 1) {
      // A row whose stated figures disagree must not silently become a
      // computed balance that differs from the source: reject it.
      issues.add('$at: $billNo balance $balance does not equal total $total - advance $advance - rejected, fix the CSV row first');
      continue;
    }
    records.add({
      'bill_no': billNo,
      'customer': c[2].trim(),
      'mobile': c[3].trim(),
      'type_label': c[4].trim(),
      'bill_date': dateIso,
      'return_date': parseDispDate(c[8]),
      'total': total,
      'advance': advance,
      'balance': balance,
      'status': c[9].trim(),
    });
  }
  if (records.isEmpty && issues.isEmpty) {
    issues.add('no records found in the file');
  }
  return RecordsCsvParse(records, issues);
}
