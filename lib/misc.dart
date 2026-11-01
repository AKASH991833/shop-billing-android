import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'ui.dart';
import 'data.dart';
import 'main.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, Widget page) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: kLine),
            borderRadius: BorderRadius.circular(12)),
        child: Material(
            color: Colors.transparent,
            child: ListTile(
            leading: Icon(icon, color: kNavy),
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, color: kSoft),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => page)))));
    return Column(children: [
      brandHeader(),
      Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
        row(Icons.inventory_2_outlined, 'Stock & Items', const StockPage()),
        row(Icons.people_outline, 'Customers', const CustomersPage()),
        row(Icons.bar_chart, 'Reports', const ReportsPage()),
        row(Icons.settings_outlined, 'Settings', const SettingsPage()),
      ])),
    ]);
  }
}

class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  List<Map<String, Object?>> items = const [];

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
    final v = await AppDb.listInventory();
    if (!mounted) return;
    setState(() => items = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock & Items')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        if (items.isEmpty)
          infoRow(
              const Text('No items yet - add your first stock item',
                  style: TextStyle(color: kSoft)),
              const SizedBox()),
        ...items.map((it) {
          final rental = it['rent_rate_day'] != null;
          final out = (it['rented_out'] as num?)?.toDouble() ?? 0;
          return infoRow(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it['name'] as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                    rental
                        ? 'Rental \u00B7 ${money(it['rent_rate_day'] as num)}/day'
                        : 'Sale \u00B7 ${money((it['sale_price'] as num?) ?? 0)}',
                    style: const TextStyle(fontSize: 12, color: kSoft)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${(it['total_qty'] as num).round()} pc',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (out > 0)
                  Text('${out.round()} rented out',
                      style: const TextStyle(
                          fontSize: 11, color: kRed, fontWeight: FontWeight.w600)),
              ]));
        }),
        OutlinedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('Add item')),
      ]),
    );
  }

  Future<void> _addItem() async {
    final name = TextEditingController();
    final qty = TextEditingController(text: '1');
    final price = TextEditingController();
    final rent = TextEditingController();
    String cat = 'sale';
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setD) => AlertDialog(
                    title: const Text('Add Item'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: fieldDec('Item name')),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                          isExpanded: true,
                          value: cat,
                          items: const [
                            DropdownMenuItem(
                                value: 'sale', child: Text('For sale')),
                            DropdownMenuItem(
                                value: 'rental', child: Text('For rent')),
                          ],
                          onChanged: (v) => setD(() => cat = v ?? 'sale')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration: fieldDec('Quantity')),
                      const SizedBox(height: 8),
                      if (cat == 'sale')
                        TextField(
                            controller: price,
                            keyboardType: TextInputType.number,
                            decoration: fieldDec('Sale price (\u20B9)'))
                      else
                        TextField(
                            controller: rent,
                            keyboardType: TextInputType.number,
                            decoration: fieldDec('Rent per day (\u20B9)')),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Save')),
                    ])));
    if (ok != true || name.text.trim().isEmpty) return;
    await AppDb.addInventoryItem(
        name.text,
        cat,
        double.tryParse(qty.text) ?? 0,
        cat == 'sale' ? double.tryParse(price.text) : null,
        cat == 'rental' ? double.tryParse(rent.text) : null);
    _load();
  }
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<Map<String, Object?>> customers = const [];

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
    final v = await AppDb.listCustomers();
    if (!mounted) return;
    setState(() => customers = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        if (customers.isEmpty)
          infoRow(
              const Text('No customers yet - they appear from saved bills',
                  style: TextStyle(color: kSoft)),
              const SizedBox()),
        ...customers.map((c) {
          final nm = (c['name'] as String).isEmpty
              ? 'Walk-in #${c['id']}'
              : c['name'] as String;
          final due = (c['charges_due'] as num?)?.toDouble() ?? 0;
          return infoRow(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nm,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                    '${(c['mobile'] as String).isEmpty ? 'no mobile' : c['mobile']} \u00B7 ${c['bill_count']} bill(s)',
                    style: const TextStyle(fontSize: 12, color: kSoft)),
              ]),
              due > 0
                  ? Text('${money(due)} due',
                      style: const TextStyle(
                          color: kRed, fontWeight: FontWeight.w700))
                  : const Text('Clear',
                      style: TextStyle(
                          color: kGreen, fontWeight: FontWeight.w700)));
        }),
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Walk-in bills work without any customer details - a name, mobile or address is saved only when the customer gives it.',
                style: TextStyle(fontSize: 11.5, color: kSoft))),
      ]),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  Map<String, double> r = const {};

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

  void _load() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);
    final to = AppDb.todayIso();
    AppDb.report(from, to).then((v) {
      if (mounted) setState(() => r = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports - This Month')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            _stat('Sales Revenue', money(r['sales'] ?? 0), kNavy),
            _stat('Rental & Order Revenue', money(r['rent_order'] ?? 0), kNavy),
            _stat('Collected', money(r['collected'] ?? 0), kGreen),
            _stat('Balance Due', money(r['pending'] ?? 0), kRed),
          ],
        ),
        sectionTitle('DEPOSITS \u00B7 HELD, NOT REVENUE'),
        infoRow(
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Security deposits held',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text('Refundable \u00B7 not counted as income',
                  style: TextStyle(fontSize: 12, color: kSoft)),
            ]),
            Text(money(r['deposits_held'] ?? 0),
                style: const TextStyle(fontWeight: FontWeight.w700))),
        const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
                'Reports show revenue and collections only. Refundable deposits are always kept separate and are never counted as income. This report shows business activity, not profit.',
                style: TextStyle(fontSize: 11.5, color: kSoft))),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5, color: kSoft, letterSpacing: 0.4)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      ]));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final phone = TextEditingController();
  final email = TextEditingController();
  final address = TextEditingController();
  final motto = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppDb.dataRevision.addListener(_onDataChanged);
    _loadSettings();
  }

  void _onDataChanged() {
    if (mounted) _loadSettings();
  }

  void _loadSettings() {
    () async {
      phone.text = await AppDb.setting('shop_phone');
      email.text = await AppDb.setting('shop_email');
      address.text = await AppDb.setting('shop_address');
      motto.text = await AppDb.setting('shop_motto');
      if (mounted) setState(() {});
    }();
  }

  @override
  void dispose() {
    AppDb.dataRevision.removeListener(_onDataChanged);
    phone.dispose();
    email.dispose();
    address.dispose();
    motto.dispose();
    super.dispose();
  }

  Future<void> _backupNow() async {
    try {
      final r = await AppDb.backupNow();
      if (!mounted) return;
      final name = p.basename(r['path'] as String);
      if (r['verified'] == true) {
        toast(context, 'Backup saved & verified: $name');
        // Offer the share sheet so the backup can leave the phone (Drive,
        // WhatsApp, Files). The local copy stays in app storage either way.
        await SharePlus.instance.share(ShareParams(
            files: [XFile(r['path'] as String)], text: 'Shop backup $name'));
      } else {
        toast(context, 'Backup written but verification FAILED - do not rely on it');
      }
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e');
    }
  }

  Future<void> _restore() async {
    final pick = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['db']);
    final path = pick?.files.single.path;
    if (path == null || !mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Restore this backup?'),
              content: Text(
                  '${p.basename(path)}\n\nThis replaces ALL current data on this phone. A safety copy of the current data is kept first.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Restore')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    try {
      final r = await AppDb.restoreBackup(path);
      if (!mounted) return;
      toast(
          context,
          r['verified'] == true
              ? 'Backup restored & verified - every screen refreshes automatically.'
              : 'Restore failed verification - your previous data was kept.');
    } catch (e) {
      if (mounted) {
        toast(context, e.toString().replaceFirst('Invalid argument(s): ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        sectionTitle('SHOP PROFILE'),
        fieldLabel('Shop Name'),
        TextField(
            readOnly: true,
            decoration: fieldDec()
                .copyWith(hintText: Brand.value.shopName)),
        const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Set in the app build branding, not editable here.',
                style: TextStyle(fontSize: 11, color: kSoft))),
        fieldLabel('Phone (printed on invoice)'),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: fieldDec('Not set')),
        fieldLabel('Email (printed on invoice)'),
        TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: fieldDec('Not set')),
        fieldLabel('Address (printed on invoice)'),
        TextField(
            controller: address,
            maxLines: 2,
            decoration: fieldDec('Not set')),
        fieldLabel('Footer motto on invoice'),
        TextField(controller: motto, decoration: fieldDec('Not set')),
        const SizedBox(height: 10),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              await AppDb.setSetting('shop_phone', phone.text.trim());
              await AppDb.setSetting('shop_email', email.text.trim());
              await AppDb.setSetting('shop_address', address.text.trim());
              await AppDb.setSetting('shop_motto', motto.text.trim());
              if (mounted) toast(context, 'Settings saved');
            },
            child: const Text('Save Settings')),
        sectionTitle('DATA'),
        infoRow(
            const Text('Backup & restore',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: _backupNow, child: const Text('Back up now')),
              TextButton(
                  onPressed: _restore, child: const Text('Restore')),
            ])),
        infoRow(
            const Text('Sync with desktop software',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Text('Not verified yet',
                style: TextStyle(fontSize: 12, color: kSoft))),
        infoRow(
            const Text('App lock',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Text('Coming soon', style: TextStyle(fontSize: 12, color: kSoft))),
      ]),
    );
  }
}
