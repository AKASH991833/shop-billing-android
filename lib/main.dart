import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'ui.dart';
import 'home.dart';
import 'bills.dart';
import 'new_bill.dart';
import 'returns.dart';
import 'misc.dart';

class Brand {
  final String shopName, tagline, categories, motto, phone, email, address;
  const Brand(this.shopName, this.tagline, this.categories, this.motto,
      this.phone, this.email, this.address);

  static Brand value = const Brand('My Shop', 'BILLING & RENTAL MANAGER',
      'RETAIL | RENTAL | ORDERS', '', '', '', '');

  static Future<void> load() async {
    try {
      final s = await rootBundle.loadString('assets/brand.json');
      final j = jsonDecode(s) as Map<String, dynamic>;
      String g(String k) => (j[k] as String?) ?? '';
      value = Brand(
          g('shop_name').isEmpty ? 'My Shop' : g('shop_name'),
          g('tagline'),
          g('categories'),
          g('motto'),
          g('phone'),
          g('email'),
          g('address'));
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Brand.load();
  runApp(const BillingApp());
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${Brand.value.shopName} Billing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          scaffoldBackgroundColor: kBg,
          colorScheme: ColorScheme.fromSeed(seedColor: kNavy, primary: kNavy),
          appBarTheme: const AppBarTheme(
              backgroundColor: kNavy,
              foregroundColor: Colors.white,
              elevation: 0)),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int tab = 0;
  final billsKey = GlobalKey<BillsPageState>();
  final returnsKey = GlobalKey<ReturnsPageState>();

  void go(int i) {
    setState(() => tab = i);
    if (i == 1) billsKey.currentState?.reload();
    if (i == 3) returnsKey.currentState?.reload();
  }

  void openBill(int billId) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BillDetailPage(billId: billId)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onOpenBill: openBill, onGo: go),
      BillsPage(key: billsKey, onOpenBill: openBill),
      const SizedBox(),
      ReturnsPage(key: returnsKey, onOpenBill: openBill),
      const MorePage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: SizedBox(
          height: 60,
          child: Row(children: [
            _navItem(0, Icons.home_outlined, 'Home'),
            _navItem(1, Icons.receipt_long_outlined, 'Bills'),
            Expanded(
                child: Center(
                    child: FloatingActionButton(
              onPressed: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NewBillPage()));
                setState(() {});
              },
              backgroundColor: kMaroon,
              child: const Icon(Icons.add, color: Colors.white),
            ))),
            _navItem(3, Icons.keyboard_return, 'Returns'),
            _navItem(4, Icons.more_horiz, 'More'),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final on = tab == i;
    return Expanded(
        child: InkWell(
      onTap: () => go(i),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 21, color: on ? kNavy : kSoft),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: on ? kNavy : kSoft)),
      ]),
    ));
  }
}

Widget brandHeader() => Container(
    width: double.infinity,
    color: kNavy,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichText(
          text: TextSpan(
              style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.white),
              children: [
            TextSpan(text: Brand.value.shopName.toUpperCase()),
          ])),
      if (Brand.value.tagline.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(Brand.value.tagline,
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 2.5,
                    color: Color(0xFFB9C4DD)))),
    ]));
