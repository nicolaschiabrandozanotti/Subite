import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/offline_basemap.dart';

class OfflineMapLayer extends StatefulWidget {
  const OfflineMapLayer({super.key});
  @override
  State<OfflineMapLayer> createState() => _OfflineMapLayerState();
}

class _OfflineMapLayerState extends State<OfflineMapLayer> {
  final _map = OfflineBasemap.load();
  static const _major = {
    'motorway',
    'trunk',
    'primary',
    'secondary',
    'tertiary',
    'motorway_link',
    'trunk_link',
    'primary_link',
    'secondary_link',
  };

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return FutureBuilder<OfflineBasemap>(
      future: _map,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: Text(
              snapshot.hasError
                  ? 'No se pudo abrir el mapa local'
                  : 'Abriendo mapa local…',
            ),
          );
        }
        final roads = <Polyline>[];
        final parks = <Polygon>[];
        final labels = <Marker>[];
        final names = <String>{};
        final cells = <String>{};
        for (final feature in snapshot.data!.features) {
          if (!feature.bounds.isOverlapping(camera.visibleBounds)) continue;
          final major = _major.contains(feature.kind);
          if (camera.zoom < 13 &&
              !major &&
              feature.kind != 'water' &&
              feature.kind != 'park') {
            continue;
          }
          if (feature.kind == 'park') {
            if (feature.points.length >= 3) {
              parks.add(
                Polygon(points: feature.points, color: const Color(0xFFD7E6CD)),
              );
            }
            continue;
          }
          roads.add(
            Polyline(
              points: feature.points,
              strokeWidth: feature.kind == 'water'
                  ? 3
                  : major
                  ? 3.5
                  : 1.5,
              color: feature.kind == 'water'
                  ? const Color(0xFF9ACEDB)
                  : major
                  ? const Color(0xFFFFE4AD)
                  : Colors.white,
              borderStrokeWidth: feature.kind == 'water' ? 0 : .5,
              borderColor: const Color(0xFFD1CEC5),
            ),
          );
          if (camera.zoom < 14 ||
              feature.name.isEmpty ||
              labels.length >= 35 ||
              (!major && camera.zoom < 16)) {
            continue;
          }
          final point = feature.points[feature.points.length ~/ 2];
          if (!camera.visibleBounds.contains(point)) continue;
          final screen = camera.latLngToScreenOffset(point);
          final cell =
              '${(screen.dx / 140).floor()}:${(screen.dy / 45).floor()}';
          if (names.contains(feature.name) || cells.contains(cell)) continue;
          names.add(feature.name);
          cells.add(cell);
          labels.add(
            Marker(
              point: point,
              width: 145,
              height: 22,
              child: IgnorePointer(
                child: Text(
                  feature.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF655F53),
                    shadows: [Shadow(color: Colors.white, blurRadius: 3)],
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(
          children: [
            PolygonLayer(polygons: parks),
            PolylineLayer(polylines: roads),
            MarkerLayer(markers: labels),
          ],
        );
      },
    );
  }
}
