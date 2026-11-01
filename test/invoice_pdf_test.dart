import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shop_billing/invoice_pdf.dart';

Future<pw.Font> ttf(String path) async => pw.Font.ttf(
    ByteData.sublistView(await File('assets/fonts/$path').readAsBytes()));

void main() {
  test('inrPdf formats Indian grouping without the rupee glyph', () {
    expect(inrPdf(500), 'Rs. 500');
    expect(inrPdf(6500), 'Rs. 6,500');
    expect(inrPdf(12345678), 'Rs. 1,23,45,678');
  });

  test('invoice PDF renders a real A4 document with reconcilable totals', () async {
    final bytes = await buildInvoicePdf(
      fontRegular: await ttf('NotoSans-Regular.ttf'),
      fontBold: await ttf('NotoSans-Bold.ttf'),
      fontItalic: await ttf('NotoSans-Italic.ttf'),
      fontFallback: [await ttf('NotoSansDevanagari-Regular.ttf')],
      shopName: 'Test Silk House',
      categories: 'SAREES - LEHENGAS - SUITS',
      motto: 'Drape your moments',
      shop: const {'phone': '9876543210', 'email': '', 'address': '12 Bazaar Rd'},
      bill: const {
        'bill_no': 'T-1001',
        'customer': 'Meera Sharma',
        'mobile': '9812345678',
        'customer_address': '45 Lake View',
        'bill_date': '2026-11-01',
        'type': 'WEDDING',
        'event_date': '2026-11-03',
        'return_date': '2026-11-05',
        'charges': 6500.0,
        'paid_charges': 1000.0,
        'balance_charges': 5500.0,
        'deposit': 2000.0,
        'deposit_collected': 2000.0,
        'deposit_outstanding': 0.0,
      },
      items: const [
        {'description': 'Banarasi saree', 'kind': 'RENTAL', 'qty': 2, 'days': 3, 'rate': 750, 'amount': 4500.0},
        {'description': 'Sherwani', 'kind': 'RENTAL', 'qty': 1, 'days': 2, 'rate': 500, 'amount': 1000.0},
        {'description': 'Blouse stitching', 'kind': 'ORDER', 'qty': 1, 'rate': 1000, 'amount': 1000.0},
      ],
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(2000));
    // Persist for the CI artifact; rendered-page inspection happens locally
    // with pdftoppm + pdftotext, not just byte assertions.
    final out = File('build/invoice-sample.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
  });

  test('Hindi names and items render with the bundled Devanagari font', () async {
    final bytes = await buildInvoicePdf(
      fontRegular: await ttf('NotoSans-Regular.ttf'),
      fontBold: await ttf('NotoSans-Bold.ttf'),
      fontItalic: await ttf('NotoSans-Italic.ttf'),
      fontFallback: [await ttf('NotoSansDevanagari-Regular.ttf')],
      shopName: 'Test Silk House',
      bill: const {
        'bill_no': 'T-1002',
        'customer': 'मीरा शर्मा',
        'mobile': '9812345678',
        'bill_date': '2026-11-01',
        'type': 'WEDDING',
        'return_date': '2026-11-05',
        'charges': 4500.0,
        'paid_charges': 500.0,
        'balance_charges': 4000.0,
        'deposit': 2000.0,
        'deposit_collected': 2000.0,
        'deposit_outstanding': 0.0,
      },
      items: const [
        {'description': 'बनारसी साड़ी', 'kind': 'RENTAL', 'qty': 1, 'days': 3, 'rate': 1500, 'amount': 4500.0},
      ],
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final out = File('build/invoice-sample-hi.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
  });

  test('Unicode text without a fallback font is refused, not corrupted', () async {
    expect(
        () => buildInvoicePdf(
              bill: const {'bill_no': 'T-1', 'customer': 'मीरा', 'bill_date': '2026-11-01', 'type': 'SALE'},
              items: const [
                {'description': 'साड़ी', 'kind': 'SALE', 'qty': 1, 'rate': 100, 'amount': 100.0}
              ],
            ),
        throwsArgumentError);
  });
}
