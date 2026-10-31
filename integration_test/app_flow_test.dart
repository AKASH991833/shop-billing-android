import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shop_billing/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create a sale bill through the real UI and see it saved',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Home renders with the section cards (no chart).
    expect(find.text('START WORK'), findsOneWidget);
    expect(find.text('Invoice'), findsWidgets);

    // Open New Bill from the Home card.
    await tester.tap(find.text('New Bill').first);
    await tester.pumpAndSettle();
    expect(find.text('Order Type'), findsOneWidget);

    // The item fields are below the fold in the form's ListView: scroll
    // them into view first (offscreen children are not built).
    await tester.scrollUntilVisible(find.text('Item name'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final itemField = find.ancestor(
        of: find.text('Item name'), matching: find.byType(TextFormField));
    expect(itemField, findsWidgets);
    await tester.enterText(itemField.first, 'CI Test Saree');
    final rateField = find.ancestor(
        of: find.text('Rate'), matching: find.byType(TextFormField));
    await tester.enterText(rateField.first, '500');
    await tester.pumpAndSettle();

    // Save and land on the bill detail.
    await tester.ensureVisible(find.text('Save Bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Bill'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('CI Test Saree'), findsWidgets);
    expect(find.textContaining('500'), findsWidgets);

    // Back to Home: the bill appears under recent entries.
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('START WORK'), findsOneWidget);
    expect(find.textContaining('RECENT ENTRIES'), findsOneWidget);
    expect(find.textContaining('500'), findsWidgets);
  });
}
