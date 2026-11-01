import 'package:flutter/material.dart';
import 'ui.dart';
import 'data.dart';
import 'bills.dart';

class LineForm {
  final item = TextEditingController();
  final colour = TextEditingController();
  final qty = TextEditingController(text: '1');
  final days = TextEditingController(text: '1');
  final rate = TextEditingController(text: '0');
  String kind = 'SALE';

  double get amount {
    final q = double.tryParse(qty.text) ?? 0;
    final d = double.tryParse(days.text) ?? 1;
    final r = double.tryParse(rate.text) ?? 0;
    return kind == 'RENTAL' ? q * d * r : q * r;
  }

  void dispose() {
    item.dispose();
    colour.dispose();
    qty.dispose();
    days.dispose();
    rate.dispose();
  }
}

class NewBillPage extends StatefulWidget {
  const NewBillPage({super.key});
  @override
  State<NewBillPage> createState() => _NewBillPageState();
}

class _NewBillPageState extends State<NewBillPage> {
  final name = TextEditingController();
  final mobile = TextEditingController();
  final address = TextEditingController();
  final advance = TextEditingController(text: '0');
  final deposit = TextEditingController(text: '0');
  String type = 'SALE';
  DateTime? returnDate;
  final lines = <LineForm>[LineForm()];
  List<Map<String, Object?>> inventory = const [];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    AppDb.listInventory().then((v) {
      if (mounted) setState(() => inventory = v);
    });
  }

  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    address.dispose();
    advance.dispose();
    deposit.dispose();
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get itemsTotal => lines.fold(0.0, (s, l) => s + l.amount);
  double get depositVal => double.tryParse(deposit.text) ?? 0;
  double get advanceVal => double.tryParse(advance.text) ?? 0;
  double get balanceDue => itemsTotal - advanceVal < 0 ? 0 : itemsTotal - advanceVal;

  String get derivedType {
    final kinds = lines.map((l) => l.kind).toSet();
    if (kinds.length > 1 || kinds.contains('ORDER')) return 'WEDDING';
    if (kinds.contains('RENTAL')) return 'RENTAL';
    return 'SALE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Bill')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        fieldLabel('Customer (optional)'),
        TextField(controller: name, decoration: fieldDec('Walk-in customer')),
        Row(children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            fieldLabel('Mobile (optional)'),
            TextField(
                controller: mobile,
                keyboardType: TextInputType.phone,
                decoration: fieldDec()),
          ])),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            fieldLabel('Order Type'),
            DropdownButton<String>(
                isExpanded: true,
                value: type,
                items: const [
                  DropdownMenuItem(value: 'SALE', child: Text('SALE')),
                  DropdownMenuItem(value: 'RENTAL', child: Text('RENTAL')),
                  DropdownMenuItem(value: 'WEDDING', child: Text('WEDDING')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'SALE')),
          ])),
        ]),
        fieldLabel('Address (optional)'),
        TextField(
            controller: address,
            maxLines: 2,
            decoration: fieldDec('Only if you want it on the bill')),
        if (type != 'SALE') ...[
          fieldLabel('Return Date'),
          OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate:
                        DateTime.now().add(const Duration(days: 3)));
                if (d != null) setState(() => returnDate = d);
              },
              child: Text(returnDate == null
                  ? 'Pick return date'
                  : AppDb.disp(returnDate!.toIso8601String().substring(0, 10)))),
        ],
        sectionTitle('ITEMS'),
        ...lines.asMap().entries.map((e) => _lineCard(e.key, e.value)),
        OutlinedButton.icon(
            onPressed: () => setState(() => lines.add(LineForm())),
            icon: const Icon(Icons.add),
            label: const Text('Add item')),
        Row(children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            fieldLabel('Advance Paid (\u20B9)'),
            TextField(
                controller: advance,
                keyboardType: TextInputType.number,
                decoration: fieldDec(),
                onChanged: (_) => setState(() {})),
          ])),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            fieldLabel('Security Deposit, refundable (\u20B9)'),
            TextField(
                controller: deposit,
                keyboardType: TextInputType.number,
                decoration: fieldDec(),
                onChanged: (_) => setState(() {})),
          ])),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: kNavy, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            // Ledger-clear preview: every line derivable, paid money never
            // implied as still due (run-17/20 review finding).
            //   Total incl. deposit = items + deposit collected
            //   Receiving now       = advance + deposit collected
            //   Balance due (items) = items - advance
            _t('Items Total', money(itemsTotal)),
            _t('Deposit collected (refundable, not revenue)', money(depositVal)),
            const Divider(color: Colors.white24),
            _t('Total incl. deposit', money(itemsTotal + depositVal), strong: true),
            _t('Receiving now (advance + deposit)', money(advanceVal + depositVal)),
            _t('Balance Due (items)', money(balanceDue), due: true),
          ]),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50)),
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving...' : 'Save Bill')),
        const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
                'Customer details are optional. Rental lines are Qty \u00D7 Days \u00D7 Rate/Day. The deposit is collected and held separately - it is never counted as sales.',
                style: TextStyle(fontSize: 11.5, color: kSoft))),
      ]),
    );
  }

  Widget _t(String label, String value, {bool strong = false, bool due = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: strong ? 15 : 13.5,
                        fontWeight:
                            strong ? FontWeight.w700 : FontWeight.w400))),
            Text(value,
                style: TextStyle(
                    color: due ? const Color(0xFFFFD9A8) : Colors.white,
                    fontSize: strong ? 16 : 13.5,
                    fontWeight:
                        (strong || due) ? FontWeight.w700 : FontWeight.w400)),
          ]));

  Widget _lineCard(int index, LineForm l) {
    final names = inventory.map((i) => i['name'] as String).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Item ${index + 1}',
              style: const TextStyle(fontSize: 12, color: kSoft, fontWeight: FontWeight.w700)),
          if (lines.length > 1)
            InkWell(
                onTap: () => setState(() {
                      lines.removeAt(index).dispose();
                    }),
                child: const Text('Remove',
                    style: TextStyle(
                        color: kRed, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
        // Breathing room so the always-floating "Item name" label does not
        // collide with the "Item N" heading above it (run 17 pixel finding).
        const SizedBox(height: 10),
        Autocomplete<String>(
          optionsBuilder: (v) => v.text.isEmpty
              ? names
              : names.where(
                  (n) => n.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: (sel) {
            l.item.text = sel;
            final inv = inventory.firstWhere((i) => i['name'] == sel,
                orElse: () => const {});
            if (inv.isNotEmpty) {
              setState(() {
                if (l.kind == 'RENTAL' && inv['rent_rate_day'] != null) {
                  l.rate.text = (inv['rent_rate_day'] as num).toStringAsFixed(0);
                } else if (l.kind != 'RENTAL' && inv['sale_price'] != null) {
                  l.rate.text = (inv['sale_price'] as num).toStringAsFixed(0);
                }
              });
            }
          },
          fieldViewBuilder:
              (ctx, controller, focus, onSubmitted) {
            if (controller.text != l.item.text) controller.text = l.item.text;
            controller.addListener(() => l.item.text = controller.text);
            return TextField(
                controller: controller,
                focusNode: focus,
                decoration: fieldDec(null, 'Item name'));
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: DropdownButton<String>(
                  isExpanded: true,
                  value: l.kind,
                  items: const [
                    DropdownMenuItem(value: 'SALE', child: Text('Sale')),
                    DropdownMenuItem(value: 'RENTAL', child: Text('Rental')),
                    DropdownMenuItem(value: 'ORDER', child: Text('Order')),
                  ],
                  onChanged: (v) => setState(() => l.kind = v ?? 'SALE'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: l.colour, decoration: fieldDec(null, 'Colour (optional)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: l.qty,
                  keyboardType: TextInputType.number,
                  decoration: fieldDec(null, 'Qty'),
                  onChanged: (_) => setState(() {}))),
          if (l.kind == 'RENTAL') ...[
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: l.days,
                    keyboardType: TextInputType.number,
                    decoration: fieldDec(null, 'Days'),
                    onChanged: (_) => setState(() {}))),
          ],
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: l.rate,
                  keyboardType: TextInputType.number,
                  decoration:
                      fieldDec(null, l.kind == 'RENTAL' ? 'Rate/Day' : 'Rate'),
                  onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(
              child: InputDecorator(
                  decoration: fieldDec(null, 'Amount'),
                  child: Text(money(l.amount),
                      style: const TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]),
    );
  }

  Future<void> _save() async {
    final items = <Map<String, Object?>>[];
    for (final l in lines) {
      if (l.item.text.trim().isEmpty) continue;
      items.add({
        'description': l.item.text.trim(),
        'colour': l.colour.text.trim(),
        'kind': l.kind,
        'qty': double.tryParse(l.qty.text) ?? 1,
        'days': double.tryParse(l.days.text) ?? 1,
        'rate': double.tryParse(l.rate.text) ?? 0,
      });
    }
    if (items.isEmpty) {
      toast(context, 'Add at least one item');
      return;
    }
    setState(() => saving = true);
    try {
      final id = await AppDb.addBill(
        customerName: name.text,
        mobile: mobile.text,
        address: address.text,
        type: derivedType,
        billDate: AppDb.todayIso(),
        returnDate: type == 'SALE'
            ? null
            : returnDate?.toIso8601String().substring(0, 10),
        items: items,
        advance: advanceVal,
        depositAgreed: depositVal,
        depositCollected: depositVal,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => BillDetailPage(billId: id)));
    } catch (e) {
      if (mounted) {
        toast(context, e.toString().replaceFirst('Invalid argument(s): ', ''));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
