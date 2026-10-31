import 'package:flutter/material.dart';
import 'ui.dart';
import 'data.dart';

class ReturnsPage extends StatefulWidget {
  final void Function(int billId) onOpenBill;
  const ReturnsPage({super.key, required this.onOpenBill});
  @override
  State<ReturnsPage> createState() => ReturnsPageState();
}

class ReturnsPageState extends State<ReturnsPage> {
  List<Map<String, Object?>> active = const [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final rows = await AppDb.activeRentals();
    if (!mounted) return;
    setState(() => active = rows);
  }

  @override
  Widget build(BuildContext context) {
    final today = AppDb.todayIso();
    final overdue = active
        .where((r) =>
            (r['return_date'] as String?) != null &&
            (r['return_date'] as String).compareTo(today) < 0)
        .toList();
    final upcoming = active
        .where((r) =>
            (r['return_date'] as String?) == null ||
            (r['return_date'] as String).compareTo(today) >= 0)
        .toList();
    return Column(children: [
      Container(
          width: double.infinity,
          color: kNavy,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: const Text('Returns',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700))),
      Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
        if (overdue.isNotEmpty)
          sectionTitle('OVERDUE'),
        ...overdue.map((r) => _row(r, overdueItem: true)),
        sectionTitle('ACTIVE RENTALS \u00B7 NOT YET RETURNED'),
        if (upcoming.isEmpty)
          infoRow(const Text('Nothing out on rent right now',
              style: TextStyle(color: kSoft)), const SizedBox()),
        ...upcoming.map((r) => _row(r)),
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Marking a return only records the garments coming back. The deposit refund is recorded separately, with any deduction for damage or late fees.',
                style: TextStyle(fontSize: 11.5, color: kSoft))),
      ])),
    ]);
  }

  Widget _row(Map<String, Object?> r, {bool overdueItem = false}) {
    final cust = (r['customer'] as String).isEmpty ? 'Walk-in' : r['customer'];
    final held = (r['deposit_held'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['description']}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text(
              '$cust \u00B7 Invoice ${r['bill_no']} \u00B7 due ${AppDb.disp(r['return_date'] as String?)}'
              '${held > 0 ? ' \u00B7 deposit ${money(held)} held' : ''}',
              style: const TextStyle(fontSize: 12, color: kSoft)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (overdueItem)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: pill('OVERDUE', const Color(0xFFFDEAEA), kRed)),
          TextButton(
              onPressed: () => _markReturned(r),
              child: const Text('Mark returned')),
        ]),
      ]),
    );
  }

  Future<void> _markReturned(Map<String, Object?> r) async {
    await AppDb.markReturned(r['bill_id'] as int, AppDb.todayIso());
    if (!mounted) return;
    toast(context,
        'Bill ${r['bill_no']} marked returned. Deposit is still HELD - record the refund from the bill.');
    reload();
  }
}
