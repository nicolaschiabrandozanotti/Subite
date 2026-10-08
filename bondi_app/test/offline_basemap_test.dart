import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bondi_app/services/offline_basemap.dart';
import 'package:bondi_app/widgets/offline_map_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Bundled map contains real Cordoba streets and valid geometry', () async {
    final map = OfflineBasemap.decode(
      await File('assets/maps/cordoba.json.gz').readAsBytes(),
    );
    expect(map.features.length, greaterThan(40000));
    expect(map.features.any((f) => f.name.contains('Chacabuco')), isTrue);
    expect(map.features.any((f) => f.kind == 'park'), isTrue);
    expect(map.features.any((f) => f.kind == 'water'), isTrue);
    expect(map.features.every((f) => f.points.length >= 2), isTrue);
    expect(DateTime.tryParse(map.dataDate), isNotNull);
    for (final bounds in [
      LatLngBounds(const LatLng(-31.43, -64.19), const LatLng(-31.41, -64.17)),
      LatLngBounds(const LatLng(-31.55, -64.35), const LatLng(-31.25, -64.05)),
      LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)),
    ]) {
      final expected = map.features
          .where((f) => f.bounds.isOverlapping(bounds))
          .toList();
      expect(map.visibleFeatures(bounds).toList(), expected);
    }
    final viewport = LatLngBounds(
      const LatLng(-31.43, -64.19),
      const LatLng(-31.41, -64.17),
    );
    final full = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      map.features.where((f) => f.bounds.isOverlapping(viewport)).toList();
    }
    full.stop();
    final indexed = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      map.visibleFeatures(viewport).toList();
    }
    indexed.stop();
    debugPrint(
      'Viewport query 100x: full=${full.elapsedMicroseconds}us indexed=${indexed.elapsedMicroseconds}us, visible=${map.visibleFeatures(viewport).length}/${map.features.length}',
    );
  });
  testWidgets('Local map renders streets without any network tile layer', (
    tester,
  ) async {
    final loaded = await tester.runAsync(() => OfflineBasemap.load());
    expect(loaded!.features, isNotEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(-31.42, -64.18),
              initialZoom: 15,
            ),
            children: const [OfflineMapLayer()],
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsNothing);
    expect(find.textContaining('No se pudo'), findsNothing);

    final roadLayer = find.byWidgetPredicate(
      (widget) => widget is PolylineLayer,
    );
    expect(roadLayer, findsOneWidget);
    final roads = tester.widget<PolylineLayer>(roadLayer);
    expect(roads.polylines, isNotEmpty);
    expect(roads.polylines.length, lessThan(10000));
    await tester.pumpWidget(const SizedBox());
  });
}
