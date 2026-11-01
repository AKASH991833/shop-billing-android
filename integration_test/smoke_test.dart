import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shop_billing/data.dart';
import 'package:shop_billing/main.dart' as app;

// Android-runtime smoke suite (emulator job, real ART).
// Labels: taps/keyboard go through the Flutter engine on a real Android
// runtime - NOT adb-input native touch. handleAppLifecycleStateChanged is an
// engine-delivered lifecycle event, not an OS background. The OS-level
// cold-start and HOME/resume lock checks run separately in
// .github/scripts/lock_relaunch.py via adb (native, outside the engine).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Bounded real-time pumping. pumpAndSettle never settles while a text
  // field has focus - the blinking cursor schedules a frame every ~500 ms
  // forever (the LockScreen autofocus made test 4 hang in run 38).
  Future<void> settle(WidgetTester t, [int secs = 8]) async {
    final end = DateTime.now().add(Duration(seconds: secs));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
    }
  }

  Future<void> shot(String name) async {
    try {
      await binding.takeScreenshot(name);
    } catch (e) {
      print('SMOKE screenshot $name failed: $e');
    }
  }

  // State handshake for the native side: run_smoke.sh polls this file and
  // grabs an adb screencap at each known app state, so real Android pixels
  // exist even when the Flutter tool's screenshot conversion fails.
  Future<void> mark(String state) async {
    print('SMOKE_STATE=$state');
    try {
      File('/sdcard/shop_billing_state.txt').writeAsStringSync(state);
    } catch (e) {
      print('SMOKE state file write failed: $e');
    }
  }

  Future<void> launch(WidgetTester t) async {
    app.main();
    await settle(t, 10);
    // Required before takeScreenshot on this backend (run 37 error).
    await binding.convertFlutterSurfaceToImage();
    await t.pump();
  }

  testWidgets('smoke: home renders on the Android runtime', (tester) async {
    await launch(tester);
    expect(find.text('START WORK'), findsOneWidget);
    await mark('home');
    await shot('01_home');
  });

  testWidgets('smoke: sale bill saves through the real UI', (tester) async {
    await launch(tester);
    await tester.tap(find.text('New Bill').first);
    await settle(tester, 3);
    expect(find.text('Order Type'), findsOneWidget);

    final nameField = find.ancestor(
        of: find.text('Walk-in customer'), matching: find.byType(TextField));
    expect(nameField, findsOneWidget);
    await tester.tap(nameField.first);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.enterText(nameField.first, 'Smoke Customer');
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await tester.scrollUntilVisible(find.text('Item name'), 120,
        scrollable: find.byType(Scrollable).first);
    final itemField = find.ancestor(
        of: find.text('Item name'), matching: find.byType(TextField));
    await tester.enterText(itemField.first, 'Smoke Saree');
    final rateField = find.ancestor(
        of: find.text('Rate'), matching: find.byType(TextField));
    await tester.enterText(rateField.first, '750');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, 2);

    await tester.scrollUntilVisible(find.text('Save Bill'), 250,
        scrollable: find.byType(Scrollable).first);
    await settle(tester, 2);
    await shot('02_before_save');
    await tester.tap(find.text('Save Bill'));
    await settle(tester, 5);

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

  testWidgets('smoke: More page renders on the Android runtime', (tester) async {
    await launch(tester);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await settle(tester, 3);
    expect(find.text('Stock & Items'), findsOneWidget,
        reason: 'More page must show its rows');
    expect(find.text('Settings'), findsWidgets);
    await mark('more');
    await shot('04_more');
  });

  testWidgets('smoke: app lock gates launch and pause/resume', (tester) async {
    // Hard per-subtest budget: a hang here must fail fast with evidence
    // instead of consuming the whole suite window (run 41 lost 11 minutes).
    Future<void> body() async {
      final sw = Stopwatch()..start();
      print('SMOKE lock: setPassword start');
      await AppDb.setPassword('smoke-lock-99');
      print('SMOKE lock: setPassword took ${sw.elapsedMilliseconds}ms');

      sw.reset();
      await launch(tester); // fresh launch WITH a password set
      print('SMOKE lock: relaunch took ${sw.elapsedMilliseconds}ms');
      expect(find.text('Locked'), findsOneWidget,
          reason: 'launch gate must engage when a password exists');
      await mark('lockgate');
      await shot('05_lock_screen');

      sw.reset();
      await tester.enterText(find.byType(TextField).first, 'smoke-lock-99');
      await tester.tap(find.text('Unlock'));
      await settle(tester, 5);
      print('SMOKE lock: verify+unlock took ${sw.elapsedMilliseconds}ms');
      expect(find.text('START WORK'), findsOneWidget,
          reason: 'correct password must unlock');
      await mark('unlocked');
      await shot('06_unlocked_home');

      // Engine-delivered pause (labeled: not an OS event) must re-arm the gate.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester, 2);
      expect(find.text('Locked'), findsOneWidget,
          reason: 'pause must re-arm the gate');

      // Unlock again and finish unlocked; the OS-level cold-start and
      // HOME/resume checks run in lock_relaunch.py against this same device
      // state (password persists in app data).
      await tester.enterText(find.byType(TextField).first, 'smoke-lock-99');
      await tester.tap(find.text('Unlock'));
      await settle(tester, 5);
      expect(find.text('START WORK'), findsOneWidget);
      print('SMOKE lock: subtest complete');
    }

    try {
      await body().timeout(const Duration(minutes: 4));
    } on TimeoutException {
      print('SMOKE lock: TIMEOUT - exceeded the 4-minute subtest budget');
      fail('lock subtest exceeded its 4-minute budget');
    }
  });
}
