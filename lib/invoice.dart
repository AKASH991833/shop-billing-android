import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'ui.dart';
import 'data.dart';
import 'main.dart';
import 'invoice_pdf.dart';

/// On-screen A4-style invoice preview in the same maroon/gold style as the
/// desktop bills. The PDF action shares a real A4 document (system share /
/// print sheet) built by invoice_pdf.dart with bundled Noto fonts so Hindi
/// and other Unicode names render truthfully.

Map<String, pw.Font>? _pdfFonts;

/// Bundled Noto Sans (+ Devanagari fallback) for PDF output, loaded once.
Future<Map<String, pw.Font>> loadPdfFonts() async {
  final cached = _pdfFonts;
  if (cached != null) return cached;
  final fonts = <String, pw.Font>{};
  try {
    fonts['regular'] =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    fonts['bold'] =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    fonts['italic'] =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'));
    fonts['devanagari'] = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'));
  } catch (_) {
    // Font assets missing: the PDF builder will refuse non-Latin-1 text
    // explicitly instead of emitting corrupted output.
  }
  _pdfFonts = fonts;
  return fonts;
}
class InvoicePage extends StatelessWidget {
  final Map<String, Object?> bill;
  final List<Map<String, Object?>> items;
  final Map<String, String> shop;
  const InvoicePage(
      {super.key, required this.bill, required this.items, this.shop = const {}});

  @override
  Widget build(BuildContext context) {
    final rental = items.where((i) => i['kind'] == 'RENTAL').toList();
    final flat = items.where((i) => i['kind'] != 'RENTAL').toList();
    final cust = (bill['customer'] as String).isEmpty
        ? 'Walk-in #${bill['customer_id']}'
        : bill['customer'] as String;
    final mobile = bill['mobile'] as String? ?? '';
    final contact = [
      shop['phone'] ?? '',
      shop['email'] ?? '',
      shop['address'] ?? ''
    ].where((v) => v.trim().isNotEmpty).join(' \u00B7 ');
    final footerMotto = (shop['motto'] ?? '').trim();
    return Scaffold(
      appBar: AppBar(title: Text('Invoice ${bill['bill_no']}'), actions: [
        IconButton(
            tooltip: 'Share / print PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              final fonts = await loadPdfFonts();
              final bytes = await buildInvoicePdf(
                  bill: bill,
                  items: items,
                  shop: shop,
                  shopName: Brand.value.shopName,
                  categories: Brand.value.categories,
                  motto: Brand.value.motto,
                  fontRegular: fonts['regular'],
                  fontBold: fonts['bold'],
                  fontItalic: fonts['italic'],
                  fontFallback: [
                    if (fonts['devanagari'] != null) fonts['devanagari']!
                  ]);
              await Printing.sharePdf(
                  bytes: bytes, filename: 'Invoice-${bill['bill_no']}.pdf');
            }),
      ]),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kGold, width: 2)),
                  child: Center(
                      child: Text(_monogram(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: kMaroon)))),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                RichText(
                    text: TextSpan(
                        style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: kNavy),
                        text: Brand.value.shopName.toUpperCase())),
                Text(Brand.value.categories,
                    style: const TextStyle(
                        fontSize: 7, letterSpacing: 2, color: kSoft)),
                Text(Brand.value.motto,
                    style: const TextStyle(
                        fontSize: 8,
                        fontStyle: FontStyle.italic,
                        color: kGold)),
              ]),
            ]),
            if (contact.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(contact,
                      style: const TextStyle(fontSize: 9, color: kSoft))),
            Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                    color: kMaroon, borderRadius: BorderRadius.circular(4)),
                child: const Center(
                    child: Text('INVOICE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3)))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Invoice No. ${bill['bill_no']}',
                  style: const TextStyle(fontSize: 10)),
              Text(AppDb.disp(bill['bill_date'] as String?),
                  style: const TextStyle(fontSize: 10)),
              Text('Type: ${AppDb.displayType(bill)}',
                  style: const TextStyle(fontSize: 10)),
            ]),
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                    'BILLED TO: $cust${mobile.isNotEmpty ? ' \u00B7 $mobile' : ''}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600))),
            if (rental.isNotEmpty) ...[
              _band(
                  'RENTAL'
                  '${(bill['return_date'] as String?) != null ? ' \u00B7 return by ${AppDb.disp(bill['return_date'] as String?)}' : ''}'
                  ' \u00B7 security deposit (refundable)',
                  const Color(0xFF8A6508)),
              _table(rental, rentalCols: true),
            ],
            if (flat.isNotEmpty) ...[
              _band(rental.isEmpty ? 'ITEMS' : 'SALE & ORDER', kMaroon),
              _table(flat, rentalCols: false),
            ],
            Align(
                alignment: Alignment.centerRight,
                child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      // Every figure reconciles arithmetically:
                      // charges - paid_charges = balance_charges;
                      // deposit - deposit_collected = deposit_outstanding;
                      // balance_charges + deposit_outstanding = total outstanding.
                      // No mixed-base "To Collect" (run 17 review finding).
                      'Items Total ${money(bill['charges'] as double)} \u00B7 Paid ${money(bill['paid_charges'] as double)} \u00B7 Balance ${money(bill['balance_charges'] as double)}'
                      '${(bill['deposit'] as double) > 0 ? '\nDeposit (refundable) ${money(bill['deposit'] as double)} \u00B7 Collected ${money(bill['deposit_collected'] as double)} \u00B7 Outstanding ${money(bill['deposit_outstanding'] as double)}\nTotal Outstanding ${money((bill['balance_charges'] as double) + (bill['deposit_outstanding'] as double))}' : ''}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 10, height: 1.6),
                    ))),
            Container(
                margin: const EdgeInsets.only(top: 10),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF7D0D30), Color(0xFFA1123F)]),
                    borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10))),
                child: Column(children: [
                  if (footerMotto.isNotEmpty)
                    Text(footerMotto,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontStyle: FontStyle.italic)),
                  Text('Thank you for shopping with ${Brand.value.shopName}!',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  if (Brand.value.motto.isNotEmpty)
                    Text(Brand.value.motto,
                        style: const TextStyle(
                            color: Color(0xFFF3D9A8),
                            fontSize: 7,
                            letterSpacing: 1.6)),
                ])),
          ]),
        ),
        const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
                'PDF export and printing from the phone are not verified yet - this is the on-screen invoice preview.',
                style: TextStyle(fontSize: 11.5, color: kSoft))),
      ]),
    );
  }

  String _monogram() {
    final parts = Brand.value.shopName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'S';
    return parts.take(2).map((w) => w[0].toUpperCase()).join();
  }

  Widget _band(String text, Color color) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: color,
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold)));

  Widget _table(List<Map<String, Object?>> rows, {required bool rentalCols}) {
    return Table(
      border: TableBorder.all(color: const Color(0xFFE7CDD5), width: 0.5),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.4),
      },
      children: [
        TableRow(
            decoration: const BoxDecoration(color: Color(0xFFFBF3F4)),
            children: [
              _th('Description'),
              _th(rentalCols ? 'Days' : 'Qty'),
              _th('Amount'),
            ]),
        ...rows.map((it) => TableRow(children: [
              Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(it['description'] as String,
                      style: const TextStyle(fontSize: 9))),
              Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                      rentalCols
                          ? '${(it['days'] as num).round()}'
                          : '${(it['qty'] as num).round()}',
                      style: const TextStyle(fontSize: 9))),
              Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(money(it['amount'] as num),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 9))),
            ])),
      ],
    );
  }

  Widget _th(String t) => Padding(
      padding: const EdgeInsets.all(4),
      child: Text(t,
          style: const TextStyle(
              fontSize: 8, fontWeight: FontWeight.bold, color: kMaroon)));
}
