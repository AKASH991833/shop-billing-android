import 'package:flutter/material.dart';

const kNavy = Color(0xFF1E2A4A);
const kNavy2 = Color(0xFF2A3A5F);
const kSoft = Color(0xFF5B6B8C);
const kBg = Color(0xFFF4F6FB);
const kLine = Color(0xFFE3E8F2);
const kMaroon = Color(0xFF7D0D30);
const kGold = Color(0xFFB8860B);
const kGreen = Color(0xFF1E7D46);
const kRed = Color(0xFFB3261E);

/// Indian digit grouping: 178350 -> 1,78,350
String money(num v) {
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
  return '${neg ? '-' : ''}\u20B9$s';
}

Widget sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Text(t,
        style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: kSoft)));

Widget infoRow(Widget left, Widget right) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kLine),
        borderRadius: BorderRadius.circular(12)),
    child:
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: left), right]));

Widget pill(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)));

Widget typePill(String type) {
  switch (type) {
    case 'SALE':
      return pill('SALE', const Color(0xFFE6ECF9), kNavy);
    case 'RENTAL':
      return pill('RENTAL', const Color(0xFFFBF3DD), const Color(0xFF8A6508));
    default:
      return pill('WEDDING', const Color(0xFFF9E7E5), kMaroon);
  }
}

Widget statusPill(String status) {
  switch (status) {
    case 'Paid':
      return pill('PAID', const Color(0xFFE3F2E3), kGreen);
    case 'Active':
      return pill('ACTIVE', const Color(0xFFFBF3DD), const Color(0xFF8A6508));
    default:
      return pill(status.toUpperCase(), const Color(0xFFFDEAEA), kRed);
  }
}

InputDecoration fieldDec([String? hint]) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kLine)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kLine)));

Widget fieldLabel(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 0, 5),
    child: Text(t,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: kSoft)));

void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: Text(msg), behavior: SnackBarBehavior.floating));
}
