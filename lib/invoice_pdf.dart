import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'data.dart';

/// Indian-grouped money for PDF output. The built-in PDF fonts are Latin-1
/// only and carry no rupee glyph, so PDFs print "Rs." until a Unicode TTF is
/// bundled - on-screen widgets keep using the rupee glyph.
String inrPdf(num v) {
  final neg = v < 0;
  var s = v.abs().round().toString();
  if (s.length > 3) {
    final last = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last';
  }
  return '${neg ? '-' : ''}Rs. $s';
}

String _g(Object? v) {
  if (v == null) return '';
  final n = v as num;
  return n % 1 == 0 ? n.toInt().toString() : n.toString();
}

/// Bundled Unicode fonts for invoice PDFs plus their glyph coverage. The
/// coverage set lets the builder REFUSE characters that would otherwise
/// render as silent tofu boxes (e.g. Bengali/Tamil/Urdu with only the
/// Devanagari fallback bundled).
class PdfFontBundle {
  const PdfFontBundle(
      {this.regular,
      this.bold,
      this.italic,
      this.fallback = const [],
      this.coverage = const {}});
  final pw.Font? regular;
  final pw.Font? bold;
  final pw.Font? italic;
  final List<pw.Font> fallback;

  /// Union of codepoints covered by [regular] and [fallback] (from
  /// TtfParser.charToGlyphIndexMap).
  final Set<int> coverage;
  bool get hasFonts => regular != null;
}

/// Codepoints a TTF covers (TtfParser is public API exported by package:pdf).
Set<int> ttfCoverage(ByteData data) =>
    TtfParser(data).charToGlyphIndexMap.keys.toSet();

const _navy = PdfColor.fromInt(0xFF16324F);
const _maroon = PdfColor.fromInt(0xFF7D0D30);
const _gold = PdfColor.fromInt(0xFF8A6508);
const _soft = PdfColor.fromInt(0xFF5D6F82);
const _line = PdfColor.fromInt(0xFFD8E0EA);
const _headBg = PdfColor.fromInt(0xFFEEF2F7);

/// A4 invoice PDF mirroring the desktop invoice layout, with the phone's
/// reconcilable totals labels (charges - paid = balance; deposit tracked
/// separately). Neutral deposit wording only: no damage/late-fee or
/// refund-policy sentences - the owner records any adjustment himself.
Future<Uint8List> buildInvoicePdf({
  required Map<String, Object?> bill,
  required List<Map<String, Object?>> items,
  Map<String, String> shop = const {},
  String shopName = 'Shop',
  String categories = '',
  String motto = '',
  PdfFontBundle? fonts,
}) async {
  // Unicode safety: the built-in PDF fonts are Latin-1 only. Any character
  // beyond Latin-1 (customer, item, or shop text) REQUIRES bundled Unicode
  // fonts that actually cover it - otherwise refuse explicitly instead of
  // emitting dropped glyphs or tofu boxes.
  bool needsUnicode(String s) => s.runes.any((r) => r > 0xFF);
  final allText = [
    shopName, categories, motto,
    ...shop.values,
    bill['customer'] as String? ?? '',
    bill['mobile'] as String? ?? '',
    bill['customer_address'] as String? ?? '',
    for (final i in items) i['description'] as String? ?? '',
  ];
  if (allText.any(needsUnicode)) {
    if (fonts == null || !fonts.hasFonts || fonts.fallback.isEmpty) {
      throw ArgumentError(
          'Invoice text contains characters beyond Latin-1 but no Unicode fonts were provided - refusing to emit a corrupted PDF.');
    }
    for (final s in allText) {
      for (final r in s.runes) {
        if (r > 0xFF && !fonts.coverage.contains(r)) {
          throw ArgumentError(
              "Invoice text contains '${String.fromCharCode(r)}' (U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}), which the bundled PDF fonts do not cover - refusing to emit a corrupted PDF. Bundle a Noto font for that script before printing it.");
        }
      }
    }
  }
  final rental = items.where((i) => i['kind'] == 'RENTAL').toList();
  final flat = items.where((i) => i['kind'] != 'RENTAL').toList();
  final cust = (bill['customer'] as String? ?? '').isEmpty
      ? 'Walk-in customer'
      : bill['customer'] as String;
  final mobile = bill['mobile'] as String? ?? '';
  final custAddr = bill['customer_address'] as String? ?? '';
  final contact = [shop['phone'] ?? '', shop['email'] ?? '', shop['address'] ?? '']
      .where((v) => v.trim().isNotEmpty)
      .join('  |  ');
  final charges = (bill['charges'] as num? ?? 0).toDouble();
  final paid = (bill['paid_charges'] as num? ?? 0).toDouble();
  final balance = (bill['balance_charges'] as num? ?? 0).toDouble();
  final deposit = (bill['deposit'] as num? ?? 0).toDouble();
  final depCollected = (bill['deposit_collected'] as num? ?? 0).toDouble();
  final depOutstanding = (bill['deposit_outstanding'] as num? ?? 0).toDouble();
  final returnDate = bill['return_date'] as String?;
  final eventDate = bill['event_date'] as String?;

  pw.Widget band(String text, PdfColor bg) => pw.Container(
      width: double.infinity,
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: pw.Text(text,
          style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              letterSpacing: 1)));

  pw.Widget itemsTable(List<Map<String, Object?>> rows, bool rentalCols, int start) {
    final headers =
        rentalCols ? ['S.No', 'Description', 'Qty', 'Days', 'Rate/Day', 'Amount'] : ['S.No', 'Description', 'Qty', 'Rate', 'Amount'];
    final data = <List<String>>[
      for (var n = 0; n < rows.length; n++)
        [
          '${start + n}',
          rows[n]['description'] as String? ?? '',
          _g(rows[n]['qty']),
          if (rentalCols) _g(rows[n]['days']),
          inrPdf(rows[n]['rate'] as num? ?? 0),
          inrPdf(rows[n]['amount'] as num? ?? 0),
        ]
    ];
    return pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        border: pw.TableBorder.all(color: _line),
        headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold, fontSize: 9, color: _navy),
        headerDecoration: const pw.BoxDecoration(color: _headBg),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellPadding: const pw.EdgeInsets.all(4),
        cellAlignments: {
          0: pw.Alignment.center,
          2: pw.Alignment.center,
          if (rentalCols) 3: pw.Alignment.center,
          headers.length - 2: pw.Alignment.centerRight,
          headers.length - 1: pw.Alignment.centerRight,
        });
  }

  pw.Widget totalRow(String label, num value,
          {bool strong = false, PdfColor? color}) =>
      pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text('$label  ',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: color)),
            pw.SizedBox(
                width: 90,
                child: pw.Text(inrPdf(value),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight:
                            strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                        color: color))),
          ]));

  final doc = pw.Document();
  final theme = (fonts == null || !fonts.hasFonts)
      ? null
      : pw.ThemeData.withFont(
          base: fonts.regular!,
          bold: fonts.bold ?? fonts.regular!,
          italic: fonts.italic ?? fonts.regular!,
          fontFallback: fonts.fallback);
  doc.addPage(pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Center(
                child: pw.Column(children: [
              pw.Text(shopName.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 2,
                      color: _navy)),
              if (categories.isNotEmpty)
                pw.Text(categories,
                    style: const pw.TextStyle(fontSize: 7, letterSpacing: 2, color: _soft)),
              if (motto.isNotEmpty)
                pw.Text(motto,
                    style: pw.TextStyle(
                        fontSize: 8, fontStyle: pw.FontStyle.italic, color: _gold)),
              if (contact.isNotEmpty)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(contact,
                        style: const pw.TextStyle(fontSize: 8, color: _soft))),
            ])),
            pw.Divider(color: _navy, thickness: 1),
            pw.SizedBox(height: 4),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('BILLED TO',
                        style: const pw.TextStyle(fontSize: 8, color: _soft)),
                    pw.Text(cust,
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    if (mobile.isNotEmpty)
                      pw.Text('Mo: $mobile', style: const pw.TextStyle(fontSize: 9)),
                    if (custAddr.isNotEmpty)
                      pw.Text(custAddr, style: const pw.TextStyle(fontSize: 9)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text('Invoice No. ${bill['bill_no']}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${AppDb.disp(bill['bill_date'] as String?)}',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Type: ${AppDb.displayType(bill)}',
                        style: const pw.TextStyle(fontSize: 9)),
                    if (eventDate != null)
                      pw.Text('Event: ${AppDb.disp(eventDate)}',
                          style: const pw.TextStyle(fontSize: 9)),
                    if (returnDate != null)
                      pw.Text('Return: ${AppDb.disp(returnDate)}',
                          style: const pw.TextStyle(fontSize: 9)),
                  ]),
                ]),
            pw.SizedBox(height: 8),
            if (rental.isNotEmpty) ...[
              band('RENTAL ITEMS - charged per day', _navy),
              itemsTable(rental, true, 1),
              pw.SizedBox(height: 6),
            ],
            if (flat.isNotEmpty) ...[
              band(rental.isEmpty ? 'ITEMS' : 'SALE & ORDER ITEMS', _maroon),
              itemsTable(flat, false, rental.length + 1),
            ],
            pw.SizedBox(height: 8),
            totalRow('Items Total', charges),
            totalRow('Paid', paid),
            totalRow('Balance Due (items)', balance, strong: true, color: _navy),
            if (deposit > 0) ...[
              totalRow('Deposit (refundable, not revenue)', deposit),
              totalRow('Deposit collected', depCollected),
              totalRow('Deposit outstanding', depOutstanding),
              totalRow('Total Outstanding (items + deposit)', balance + depOutstanding,
                  strong: true, color: _maroon),
            ],
            if (rental.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                  'Rental items are to be returned by ${returnDate != null ? AppDb.disp(returnDate) : 'the agreed date'}.',
                  style: const pw.TextStyle(fontSize: 8, color: _soft)),
            ],
            pw.Spacer(),
            pw.Center(
                child: pw.Text('Thank you for your business!',
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: _navy))),
          ])));
  return doc.save();
}
