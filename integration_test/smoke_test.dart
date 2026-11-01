import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shop_billing/data.dart';
import 'package:shop_billing/main.dart' as app;

// Android-runtime smoke suite (runs on the emulator job, real ART).
// Labels: taps/keyboard go through the Flutter engine on a real Android
// runtime - NOT adb-input native touch. handleAppLifecycleStateChanged is an
// engine-delivered lifecycle event - the OS-level background/resume gate is
// exercised separately at the end via SystemNavigator.pop + adb relaunch in
// the workflow script (diagnostic evidence, preserved in artifacts).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(String name) async {
    try {
      await binding.takeScreenshot(name);
    } catch (e) {
      print('SMOKE screenshot $name unsupported here: $e');
    }
  }

  testWidgets('smoke: home renders on the Android runtime', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text('START WORK'), findsOneWidget);
    await shot('01_home');
  });

  testWidgets('smoke: sale bill saves through the real UI', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await tester.tap(find.text('New Bill').first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Order Type'), findsOneWidget);

    final nameField = find.ancestor(
        of: find.text('Walk-in customer'), matching: find.byType(TextField));
    expect(nameField, findsOneWidget);
    await tester.tap(nameField.first);
    await tester.pumpAndSettle();
    await tester.enterText(nameField.first, 'Smoke Customer');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Item name'), 120,
        scrollable: find.byType(Scrollable).first);
    final itemField = find.ancestor(
        of: find.text('Item name'), matching: find.byType(TextField));
    await tester.enterText(itemField.first, 'Smoke Saree');
    final rateField = find.ancestor(
        of: find.text('Rate'), matching: find.byType(TextField));
    await tester.enterText(rateField.first, '750');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.scrollUntilVisible(find.text('Save Bill'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await shot('02_before_save');
    await tester.tap(find.text('Save Bill'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Diagnostics BEFORE assertions: distinguish tap dispatch vs validation
    // rejection vs DB write failure.
    final snack = find.byType(SnackBar).evaluate().isNotEmpty;
    final backBtn = find.byType(BackButton).evaluate().isNotEmpty;
    final stillForm = find.text('Save Bill').evaluate().isNotEmpty;
    final bills = await AppDb.listBills();
    print('SMOKE after-save: snackbar=$snack backButton=$backBtn '
        'stillOnForm=$stillForm dbBills=${bills.length}');
    await shot('03_after_save');
    expect(stillForm, isFalse, reason: 'tap did not leave the form');
    final mine = bills.where(
        (b) => (b['customer'] as String).contains('Smoke Customer'));
    expect(mine, isNotEmpty, reason: 'no bill row after save');
    expect(mine.first['charges'], 750.0);
  });

  testWidgets('smoke: app lock gates launch and pause/resume', (tester) async {
    await AppDb.setPassword('smoke-lock-99');
    app.main(); // fresh launch WITH a password set
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text('Locked'), findsOneWidget,
        reason: 'launch gate must engage when a password exists');
    await shot('04_lock_screen');

    await tester.enterText(find.byType(TextField).first, 'smoke-lock-99');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('START WORK'), findsOneWidget,
        reason: 'correct password must unlock');

    // Engine-delivered pause (labeled: not an OS event) must re-arm the gate.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Locked'), findsOneWidget,
        reason: 'pause must re-arm the gate');

    // Unlock again so the OS-background path starts from an unlocked state.
    await tester.enterText(find.byType(TextField).first, 'smoke-lock-99');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('START WORK'), findsOneWidget);

    // Real OS background, LAST: the workflow relaunches via adb monkey and
    // screencaps; lock gate on resume is checked from the UI XML dump.
    await SystemNavigator.pop();
    await Future<void>.delayed(const Duration(seconds: 3));
  });
}
