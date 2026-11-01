import 'package:flutter/material.dart';
import 'ui.dart';
import 'data.dart';
import 'invoice.dart';

class BillsPage extends StatefulWidget {
  final void Function(int billId) onOpenBill;
  const BillsPage({super.key, required this.onOpenBill});
  @override
  State<BillsPage> createState() => BillsPageState();
}

class BillsPageState extends State<BillsPage> {
  String filter = 'All';
  List<Map<String, Object?>> bills = const [];

  @override
  @override
  void initState() {
    super.initState();
    AppDb.dataRevision.addListener(_onDataChanged);
    reload();
  }

  void _onDataChanged() {
    if (mounted) reload();
  }

  @override
  void dispose() {
    AppDb.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> reload() async {
    final rows = await AppDb.listBills(
        typeFilter: filter == 'All' ? null : filter);
    if (!mounted) return;
    setState(() => bills = rows);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      brandHeaderMini(),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in ['All', 'SALE', 'RENTAL', 'WEDDING'])
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f == 'All' ? 'All' : f[0] + f.substring(1).toLowerCase()),
                    selected: filter == f,
                    onSelected: (_) {
                      setState(() => filter = f);
                      reload();
                    },
                  )),
          ]),
        ),
      ),
      Expanded(
          child: bills.isEmpty
              ? const Center(
                  child: Text('No bills yet. Tap + to make the first one.',
                      style: TextStyle(color: kSoft)))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: bills.length,
                  itemBuilder: (_, i) {
                    final b = bills[i];
                    final cust = (b['customer'] as String).isEmpty
                        ? 'Walk-in #${b['customer_id']}'
                        : b['customer'] as String;
                    return InkWell(
                        onTap: () => widget.onOpenBill(b['id'] as int),
                        child: infoRow(
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Invoice ${b['bill_no']} \u00B7 $cust',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14)),
                              Text(
                                  '${AppDb.displayType(b)} \u00B7 ${AppDb.disp(b['bill_date'] as String?)} \u00B7 Charges ${money(b['charges'] as double)}',
                                  style: const TextStyle(fontSize: 12, color: kSoft)),
                            ]),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              typePill(b['type'] as String),
                              const SizedBox(height: 4),
                              statusPill(b['status'] as String),
                            ])));
                  })),
    ]);
  }

  Widget brandHeaderMini() => Container(
      width: double.infinity,
      color: kNavy,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: const Text('Bills',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)));
}

class BillDetailPage extends StatefulWidget {
  final int billId;
  const BillDetailPage({super.key, required this.billId});
  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  Map<String, Object?>? bill;
  List<Map<String, Object?>> items = const [];
  List<Map<String, Object?>> payments = const [];

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
    final b = await AppDb.getBill(widget.billId);
    final it = await AppDb.billItems(widget.billId);
    final py = await AppDb.billPayments(widget.billId);
    if (!mounted) return;
    setState(() {
      bill = b;
      items = it;
      payments = py;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = bill;
    return Scaffold(
      appBar: AppBar(title: Text('Invoice ${b?['bill_no'] ?? ''}')),
      body: b == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              infoRow(
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        (b['customer'] as String).isEmpty
                            ? 'Walk-in #${b['customer_id']}'
                            : b['customer'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                        '${AppDb.displayType(b)} \u00B7 ${AppDb.disp(b['bill_date'] as String?)}'
                        '${(b['return_date'] as String?) != null ? ' \u00B7 return by ${AppDb.disp(b['return_date'] as String?)}' : ''}',
                        style: const TextStyle(fontSize: 12, color: kSoft)),
                  ]),
                  statusPill((b['status'] as String?) ?? _statusOf(b))),
              sectionTitle('ITEMS'),
              ...items.map((it) => infoRow(
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it['description'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(
                        it['kind'] == 'RENTAL'
                            ? 'Rental \u00B7 ${(it['qty'] as num).round()} \u00D7 ${(it['days'] as num).round()} days \u00D7 ${money(it['rate'] as num)}/day'
                            : '${it['kind'] == 'ORDER' ? 'Order' : 'Sale'} \u00B7 ${(it['qty'] as num).round()} \u00D7 ${money(it['rate'] as num)}',
                        style: const TextStyle(fontSize: 12, color: kSoft)),
                  ]),
                  Text(money(it['amount'] as num),
                      style: const TextStyle(fontWeight: FontWeight.w700)))),
              sectionTitle('SETTLEMENT'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: kNavy, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  _tRow('Items Total', money(b['charges'] as double)),
                  if ((b['deposit'] as double) > 0) ...[
                    _tRow('Security Deposit (refundable, not revenue)',
                        money(b['deposit'] as double)),
                    _tRow('Deposit collected / held',
                        money(b['deposit_held'] as double)),
                    if ((b['deposit_outstanding'] as double) > 0)
                      _tRow('Deposit still to collect',
                          money(b['deposit_outstanding'] as double)),
                  ],
                  const Divider(color: Colors.white24),
                  _tRow('Paid towards items', money(b['paid_charges'] as double)),
                  _tRow('Balance Due (items)', money(b['balance_charges'] as double),
                      strong: true),
                ]),
              ),
              if (payments.isNotEmpty) ...[
                sectionTitle('PAYMENTS'),
                ...payments.map((py) => infoRow(
                    Text(
                        '${money(py['amount'] as num)} \u00B7 ${py['mode']} \u00B7 ${py['purpose'] == 'DEPOSIT' ? 'deposit' : 'items'}',
                        style: const TextStyle(fontSize: 13)),
                    Text(AppDb.disp((py['paid_at'] as String).substring(0, 10)),
                        style: const TextStyle(fontSize: 12, color: kSoft)))),
              ],
              const SizedBox(height: 12),
              if ((b['balance_charges'] as double) > 0 ||
                  (b['deposit_outstanding'] as double) > 0)
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kNavy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _recordPayment,
                    child: const Text('Record Payment')),
              const SizedBox(height: 8),
              OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: () async {
                    final shop = await AppDb.shopContact();
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            InvoicePage(bill: b, items: items, shop: shop)));
                  },
                  child: const Text('View Invoice')),
            ]),
    );
  }

  String _statusOf(Map<String, Object?> b) {
    final bal = (b['balance_charges'] as double) + (b['deposit_outstanding'] as double);
    final paid = (b['paid_charges'] as double) + (b['deposit_collected'] as double);
    var st = bal <= 0 ? 'Paid' : (paid > 0 ? 'Advance' : 'Unpaid');
    if (((b['kinds'] as String?) ?? '').contains('RENTAL') &&
        b['return_date'] != null && b['returned_at'] == null) st = 'Active';
    return st;
  }

  Widget _tRow(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: strong ? 15 : 13.5,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400))),
        Text(value,
            style: TextStyle(
                color: strong ? const Color(0xFFFFD9A8) : Colors.white,
                fontSize: strong ? 16 : 13.5,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
      ]));

  Future<void> _recordPayment() async {
    final b = bill!;
    final amt = TextEditingController();
    String mode = 'Cash';
    String purpose = (b['balance_charges'] as double) > 0 ? 'CHARGES' : 'DEPOSIT';
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setD) => AlertDialog(
                  title: const Text('Record Payment'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButton<String>(
                        isExpanded: true,
                        value: purpose,
                        items: [
                          if ((b['balance_charges'] as double) > 0)
                            DropdownMenuItem(
                                value: 'CHARGES',
                                child: Text(
                                    'Towards items (due ${money(b['balance_charges'] as double)})')),
                          if ((b['deposit_outstanding'] as double) > 0)
                            DropdownMenuItem(
                                value: 'DEPOSIT',
                                child: Text(
                                    'Deposit (to collect ${money(b['deposit_outstanding'] as double)})')),
                        ],
                        onChanged: (v) => setD(() => purpose = v ?? purpose)),
                    const SizedBox(height: 10),
                    TextField(
                        controller: amt,
                        keyboardType: TextInputType.number,
                        decoration: fieldDec('Amount')),
                    const SizedBox(height: 10),
                    DropdownButton<String>(
                        isExpanded: true,
                        value: mode,
                        items: const [
                          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                          DropdownMenuItem(value: 'Card', child: Text('Card')),
                          DropdownMenuItem(
                              value: 'Bank Transfer',
                              child: Text('Bank Transfer')),
                        ],
                        onChanged: (v) => setD(() => mode = v ?? mode)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save')),
                  ],
                )));
    if (ok != true) return;
    final v = double.tryParse(amt.text) ?? 0;
    try {
      await AppDb.addPayment(widget.billId, v, mode, purpose: purpose);
      if (mounted) toast(context, 'Payment recorded');
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Invalid argument(s): ', ''));
    }
    _load();
  }
}
