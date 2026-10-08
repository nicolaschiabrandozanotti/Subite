import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/main.dart';
import 'package:bondi_app/widgets/bus_marker.dart';
import 'package:bondi_app/widgets/offline_map_layer.dart';
import 'package:bondi_app/services/raster_map.dart';
import 'package:flutter_map/flutter_map.dart';

void main() {
  testWidgets('Offline trip renders its saved bus over packaged map tiles', (
    tester,
  ) async {
    await tester.runAsync(
      () => RasterMap.load(directory: Directory("assets/maps")),
    );
    final point = {'codigo': 'a', 'nombre': 'Casa', 'lat': -31.4, 'lon': -64.2};
    final end = {
      'codigo': 'b',
      'nombre': 'Destino',
      'lat': -31.39,
      'lon': -64.2,
    };
    SharedPreferences.setMockInitialValues({
      'offline_trip_v1': jsonEncode({
        'line': {'id': '1', 'nombre': '70', 'rutas': []},
        'route': {'id': '1', 'sentido': 'I'},
        'trace': {
          'puntos': [
            [-31.4, -64.2],
            [-31.39, -64.2],
          ],
          'paradas': [point, end],
        },
        'origin': point,
        'destination': end,
        'boarding': point,
        'alighting': end,
        'savedAt': DateTime.now().toIso8601String(),
        'positionsAt': DateTime.now().toIso8601String(),
        'buses': [
          {'coche': 562, 'linea': '70', 'lat': -31.4, 'lon': -64.2},
        ],
      }),
    });
    await tester.pumpWidget(const BondiApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    final open = find.text('Abrir viaje sin datos');
    expect(open.hitTestable(), findsOneWidget);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(BusMarker), findsWidgets);
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
      isA<RasterMap>(),
    );
    expect(find.byType(OfflineMapLayer), findsOneWidget);
    expect(find.textContaining('no son en vivo'), findsOneWidget);
    expect(find.text('COLECTIVOS DEL RECORRIDO'), findsNothing);
    expect(find.text('Opciones del viaje'), findsOneWidget);
    expect(find.text('Paradas hasta tu bajada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Home hides route details until there is a route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BondiApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journey-sheet-handle')), findsNothing);
    expect(find.text('COLECTIVOS DEL RECORRIDO'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Sheet handle expands with a mouse drag', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final point = {'codigo': 'a', 'nombre': 'Casa', 'lat': -31.4, 'lon': -64.2};
    SharedPreferences.setMockInitialValues({
      'offline_trip_v1': jsonEncode({
        'line': {'id': '1', 'nombre': '70', 'rutas': []},
        'route': {'id': '1', 'sentido': 'I'},
        'trace': {'puntos': [], 'paradas': []},
        'origin': point,
        'destination': point,
        'boarding': point,
        'alighting': point,
        'savedAt': DateTime.now().toIso8601String(),
      }),
    });
    await tester.pumpWidget(const BondiApp());
    await tester.pumpAndSettle();
    // A saved offline trip is now opened from the map's quick actions;
    // the details sheet stays hidden until a trip is selected.
    final handle = find.byKey(const ValueKey('journey-sheet-handle'));
    expect(handle, findsNothing);
    await tester.tap(find.text('Abrir viaje sin datos'));
    await tester.pumpAndSettle();
    expect(handle, findsOneWidget);
    final before = tester.getCenter(handle);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: before);
    await mouse.down(before);
    await mouse.moveBy(const Offset(0, -25));
    await tester.pump();
    await mouse.moveBy(const Offset(0, -150));
    await tester.pump();
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getCenter(handle).dy, lessThan(before.dy - 70));
    await tester.pumpWidget(const SizedBox());
  });
}
