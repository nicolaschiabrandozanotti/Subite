import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/offline_basemap.dart';

class OfflineMapLayer extends StatefulWidget {
  const OfflineMapLayer({super.key});
  @override
  State<OfflineMapLayer> createState() => _OfflineMapLayerState();
}

class _OfflineMapLayerState extends State<OfflineMapLayer> {
  final _map = OfflineBasemap.load();
  LatLngBounds? _loadedBounds;
  int? _zoomLevel;
  List<MapFeature> _features = [];
  List<Polyline> _roads = [];
  List<Polygon> _parks = [];
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
        final visible = camera.visibleBounds;
        final rebuild =
            _zoomLevel != camera.zoom.floor() ||
            _loadedBounds == null ||
            !_loadedBounds!.contains(visible.southWest) ||
            !_loadedBounds!.contains(visible.northEast);
        if (rebuild) {
          final latMargin = (visible.north - visible.south) * .5;
          final lonMargin = (visible.east - visible.west) * .5;
          _loadedBounds = LatLngBounds(
            LatLng(visible.south - latMargin, visible.west - lonMargin),
            LatLng(visible.north + latMargin, visible.east + lonMargin),
          );
          _zoomLevel = camera.zoom.floor();
          _features = snapshot.data!.visibleFeatures(_loadedBounds!).toList();
          _roads = [];
          _parks = [];
        }
        final roads = _roads;
        final parks = _parks;
        final labels = <Marker>[];
        final names = <String>{};
        final cells = <String>{};
        for (final feature in _features) {
          final major = _major.contains(feature.kind);
          if (camera.zoom < 13 &&
              !major &&
              feature.kind != 'water' &&
              feature.kind != 'park') {
            continue;
          }
          if (feature.kind == 'park') {
            if (rebuild && feature.points.length >= 3) {
              parks.add(
                Polygon(points: feature.points, color: const Color(0xFFD7E6CD)),
              );
            }
            continue;
          }
          if (rebuild) {
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
                borderStrokeWidth: 0,
                borderColor: const Color(0xFFD1CEC5),
              ),
            );
          }
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
            PolygonLayer(polygons: parks, simplificationTolerance: 1.5),
            PolylineLayer(polylines: roads, simplificationTolerance: 1.5),
            MarkerLayer(markers: labels),
          ],
        );
      },
    );
  }
}
