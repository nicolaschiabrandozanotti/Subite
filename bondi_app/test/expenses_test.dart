import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/screens/expenses_screen.dart';

void main() {
  testWidgets(
    'Manual paid and free trips persist with cents and month totals',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: ExpensesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar viaje'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '1500,50');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('\$ 1500,50'), findsWidgets);
      await tester.tap(find.text('Registrar viaje'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('2 viajes · 1 gratis'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final entries = jsonDecode(prefs.getString('expenses_v1')!) as List;
      expect(entries.map((e) => e['cents']), containsAll([150050, 0]));
      expect(prefs.getString('expense_fare_v1'), '1500.5');
    },
  );
}
