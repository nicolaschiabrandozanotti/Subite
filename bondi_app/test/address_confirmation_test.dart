import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:bondi_app/screens/journey_screen.dart';
import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/place_search_service.dart';

void main() {
  testWidgets('Unverified height requires choosing a map point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reference = Parada(
      codigo: 'street',
      nombre: 'Nevado 1054',
      lat: -31.43527,
      lon: -64.2165,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfirmAddressPoint(
            suggestion: PlaceSuggestion(
              reference,
              'Parque Capital',
              requiresMap: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Usar este punto'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Altura sin verificar'), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byType(FlutterMap)) + const Offset(30, 30),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Usar este punto'),
          )
          .onPressed,
      isNotNull,
    );
    expect(reference.lat, -31.43527);
    await tester.pumpWidget(const SizedBox());
  });
}

