import 'package:flutter/material.dart';
import 'ui.dart';
import 'data.dart';
import 'main.dart';
import 'new_bill.dart';
import 'misc.dart';
import 'invoice.dart';

class HomePage extends StatefulWidget {
  final void Function(int billId) onOpenBill;
  final void Function(int tab) onGo;
  const HomePage({super.key, required this.onOpenBill, required this.onGo});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, double> stats = const {};
  List<Map<String, Object?>> due = const [];
  List<Map<String, Object?>> recent = const [];

  @override
  @override
  void initState() {
    super.initState();
    AppDb.dataRevision.addListener(_onDataChanged);
    _load();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    AppDb.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AppDb.dashboard();
    final d = await AppDb.rentalsDue();
    final bills = await AppDb.listBills();
    if (!mounted) return;
    setState(() {
      stats = s;
      due = d;
      recent = bills.take(3).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.zero, children: [
        brandHeader(),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                _stat("Today's Sales", money(stats['sales'] ?? 0), kNavy),
                _stat('Rental & Orders', money(stats['rent_order'] ?? 0), kNavy),
                _stat('Balance Due', money(stats['pending'] ?? 0), kRed),
                _stat('Deposits Held', money(stats['deposits'] ?? 0), kGreen),
              ],
            ),
            sectionTitle('START WORK'),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 0.95,
              children: [
                _act(Icons.note_add_outlined, 'New Bill', () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const NewBillPage()));
                  _load();
                }),
                _act(Icons.receipt_long_outlined, 'Bills', () => widget.onGo(1)),
                _act(Icons.keyboard_return, 'Returns', () => widget.onGo(3)),
                _act(Icons.inventory_2_outlined, 'Stock', () => _push(const StockPage())),
                _act(Icons.people_outline, 'Customers', () => _push(const CustomersPage())),
                _act(Icons.bar_chart, 'Reports', () => _push(const ReportsPage())),
                _act(Icons.receipt_long, 'Invoice', _pickInvoice),
                _act(Icons.settings_outlined, 'Settings', () => _push(const SettingsPage())),
              ],
            ),
            sectionTitle('RETURNS DUE \u00B7 NEXT 7 DAYS'),
            if (due.isEmpty)
              infoRow(const Text('No rentals due in the next 7 days',
                  style: TextStyle(color: kSoft)), const SizedBox()),
            ...due.map((r) => infoRow(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['description']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(
                      '${(r['customer'] as String).isEmpty ? 'Walk-in' : r['customer']} \u00B7 due ${AppDb.disp(r['return_date'] as String?)}',
                      style: const TextStyle(fontSize: 12, color: kSoft)),
                ]),
                pill('due', const Color(0xFFFBF3DD), const Color(0xFF8A6508)))),
            sectionTitle('RECENT ENTRIES'),
            ...recent.map((b) => InkWell(
                onTap: () => widget.onOpenBill(b['id'] as int),
                child: infoRow(
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          'Invoice ${b['bill_no']} \u00B7 ${(b['customer'] as String).isEmpty ? 'Walk-in' : b['customer']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('${AppDb.displayType(b)} \u00B7 ${b['status']}',
                          style: const TextStyle(fontSize: 12, color: kSoft)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(money(b['charges'] as double),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      statusPill(b['status'] as String),
                    ])))),
          ]),
        ),
      ]),
    );
  }

  Future<void> _pickInvoice() async {
    final recent = (await AppDb.listBills()).take(10).toList();
    if (!mounted) return;
    if (recent.isEmpty) {
      toast(context, 'No bills yet - create a bill first');
      return;
    }
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            sectionTitle('Open invoice'),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final b in recent)
                  Card(
                    child: ListTile(
                      title: Text(b['bill_no'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${(b['customer'] as String).isEmpty ? 'Walk-in' : b['customer']} \u00B7 ${AppDb.disp(b['bill_date'] as String?)} \u00B7 ${money(b['total_to_pay'] as double)}'),
                      trailing: const Icon(Icons.receipt_long, color: kMaroon),
                      onTap: () async {
                        final id = b['id'] as int;
                        final bill = await AppDb.getBill(id);
                        final items = await AppDb.billItems(id);
                        if (!ctx.mounted || bill == null) return;
                        Navigator.pop(ctx);
                        Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) =>
                                    InvoicePage(bill: bill, items: items)));
                      },
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _push(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) => _load());
  }

  Widget _stat(String label, String value, Color color) => Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10.5, color: kSoft, letterSpacing: 0.4)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      ]));

  Widget _act(IconData icon, String label, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(13)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: kNavy, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: kNavy)),
          ])));
}
