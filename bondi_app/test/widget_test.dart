import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/main.dart';

void main() {
  testWidgets('Mobile search opens before selecting travel preferences', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BondiApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('INICIO'), findsOneWidget);
    expect(find.text('DESTINO'), findsOneWidget);
    await tester.tap(find.byTooltip('Bancá Subite'));
    await tester.pumpAndSettle();
    expect(find.text('nicochiabrando'), findsOneWidget);
    expect(find.text('0000003100012189129203'), findsOneWidget);
    expect(find.text('Nicolás Chiabrando Zanotti'), findsOneWidget);
    Navigator.of(tester.element(find.text('Bancá Subite'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('¿Desde dónde salís?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('¿Desde dónde salís?'), findsNWidgets(2));
    await tester.tap(find.text('Elegir un punto en el mapa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tocá el mapa: origen'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('¿A dónde querés ir?'), findsOneWidget);

    await tester.tap(find.text('¿A dónde querés ir?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Elegir un punto en el mapa'), findsOneWidget);

    await tester.tap(find.text('Elegir un punto en el mapa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tocá el mapa: destino'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Guardados creates named journeys with both endpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BondiApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Guardados'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tus viajes guardados'), findsOneWidget);
    await tester.tap(find.text('Crear viaje').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Crear viaje guardado'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Guardar viaje'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Alerts requires a target and distinguishes bus ETA from proximity',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const BondiApp());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Alertas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Viajá con un aviso'), findsOneWidget);
      expect(find.text('Antes de que llegue el bondi'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Ya estoy arriba · Activar aviso',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
