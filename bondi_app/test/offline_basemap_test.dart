import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bondi_app/services/raster_map.dart';
import 'package:bondi_app/widgets/offline_map_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Raster package has a complete contiguous index and valid PNG tiles',
    () async {
      final manifest = jsonDecode(
        await File('assets/maps/cordoba.tiles.json').readAsString(),
      );
      final bytes = await File('assets/maps/cordoba.tiles').readAsBytes();
      final index = manifest['tiles'] as Map<String, dynamic>;
      expect(index.length, 4962);
      expect(manifest['minZoom'], 10);
      expect(manifest['maxZoom'], 16);
      var offset = 0;
      for (final entry in index.values) {
        expect(entry[0], offset);
        final length = entry[1] as int;
        expect(bytes.sublist(offset, offset + 8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        offset += length;
      }
      expect(offset, bytes.length);
    },
  );
  testWidgets(
    'Local raster map displays packaged PNGs without network or street geometry',
    (tester) async {
      final loaded = await tester.runAsync(
        () => RasterMap.load(directory: Directory("assets/maps")),
      );
      expect(loaded, isNotNull);
      final controller = MapController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              mapController: controller,
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
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(layer.tileProvider, isA<RasterMap>());
      expect(layer.urlTemplate, isNull);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.byType(PolygonLayer), findsNothing);
      expect(tester.takeException(), isNull);
      controller.move(const LatLng(-31.43, -64.19), 16);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
