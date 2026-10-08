import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/journey_controller.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'bus_marker.dart';
import 'offline_map_layer.dart';

class JourneyMap extends StatefulWidget {
  final JourneyController journey;
  final MapController controller;
  final List<Parada> savedPlaces;
  final void Function(LatLng) onPointPicked;
  final void Function(Parada) onDestinationSelected;
  final void Function(String) onMessage;
  const JourneyMap({
    super.key,
    required this.journey,
    required this.controller,
    required this.savedPlaces,
    required this.onPointPicked,
    required this.onDestinationSelected,
    required this.onMessage,
  });
  @override
  State<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<JourneyMap> {
  Object? _polylineKey;
  List<Polyline> _cachedPolylines = [];
  List<Polyline> _mapPolylines() {
    final key = (
      widget.journey.trace,
      widget.journey.pickup,
      widget.journey.dropoff,
      widget.journey.origin,
      widget.journey.destination,
      widget.journey.line,
      widget.journey.inTrip,
      widget.journey.planned,
    );
    if (key == _polylineKey) return _cachedPolylines;
    final routes = <(List<LatLng>, Color)>[];
    if (widget.journey.inTrip &&
        widget.journey.trace != null &&
        widget.journey.pickup != null &&
        widget.journey.dropoff != null) {
      routes.add((
        widget.journey.routePoints,
        widget.journey.line?.color ?? blue,
      ));
    } else if (!widget.journey.planned && widget.journey.trace != null) {
      routes.add((
        widget.journey.trace!.puntos,
        widget.journey.line?.color ?? blue,
      ));
    }
    _polylineKey = key;
    return _cachedPolylines = [
      for (final route in routes) ...[
        Polyline(points: route.$1, strokeWidth: 7, color: Colors.white),
        Polyline(points: route.$1, strokeWidth: 4, color: route.$2),
      ],
      if (widget.journey.pickup != null)
        Polyline(
          points: [widget.journey.origin, widget.journey.pickup!.position],
          strokeWidth: 3,
          color: blue,
          pattern: StrokePattern.dashed(segments: [6, 5]),
        ),
      if (widget.journey.inTrip &&
          widget.journey.dropoff != null &&
          widget.journey.destination != null)
        Polyline(
          points: [
            widget.journey.dropoff!.position,
            widget.journey.destination!.position,
          ],
          strokeWidth: 3,
          color: const Color(0xFF00A281),
          pattern: StrokePattern.dashed(segments: [6, 5]),
        ),
    ];
  }

  Widget _stopPin(String label, Color color) => Tooltip(
    message: label,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x22003366), blurRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.signpost_rounded, color: color, size: 23),
    ),
  );

  Widget _pin(String label, Color color) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: Colors.white, width: 3),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [BoxShadow(color: Color(0x22003366), blurRadius: 10)],
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        height: 1,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FlutterMap(
    mapController: widget.controller,
    options: MapOptions(
      initialCenter: widget.journey.origin,
      initialZoom: 14,
      backgroundColor: const Color(0xFFEDEBE4),
      onTap: (_, point) => widget.onPointPicked(point),
    ),
    children: [
      const OfflineMapLayer(),
      if (!widget.journey.offline)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.bondicba.app',
        ),
      PolylineLayer(polylines: _mapPolylines()),
      MarkerLayer(
        markers: [
          if (widget.journey.hasOrigin)
            Marker(
              point: widget.journey.origin,
              width: 38,
              height: 38,
              child: _pin('A', blue),
            ),
          if (widget.journey.destination != null)
            Marker(
              point: widget.journey.destination!.position,
              width: 38,
              height: 38,
              child: _pin('B', const Color(0xFF00A281)),
            ),
          ...widget.savedPlaces.map(
            (p) => Marker(
              point: p.position,
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: p.nombre,
                icon: const Icon(Icons.bookmark, color: blue),
                onPressed: () {
                  widget.onDestinationSelected(p);
                },
              ),
            ),
          ),
          if (widget.journey.pickup != null)
            Marker(
              point: widget.journey.pickup!.position,
              width: 40,
              height: 40,
              child: _stopPin(
                'Subida · ${widget.journey.pickup!.nombre}',
                blue,
              ),
            ),
          if (widget.journey.inTrip && widget.journey.dropoff != null)
            Marker(
              point: widget.journey.dropoff!.position,
              width: 40,
              height: 40,
              child: _stopPin(
                'Bajada · ${widget.journey.dropoff!.nombre}',
                const Color(0xFF00A281),
              ),
            ),
          ...widget.journey.tripStops
              .where(
                (p) =>
                    p.codigo != widget.journey.pickup?.codigo &&
                    p.codigo != widget.journey.dropoff?.codigo,
              )
              .take(widget.journey.lightMode ? 0 : 80)
              .map(
                (p) => Marker(
                  point: p.position,
                  width: 18,
                  height: 18,
                  child: GestureDetector(
                    onTap: () {
                      widget.onMessage('Parada: ${p.nombre}');
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: widget.journey.line?.color ?? blue,
                          width: 2,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ...widget.journey.visibleBuses
              .where(
                (b) =>
                    widget.journey.arrivalVehicle == null ||
                    b.coche == widget.journey.arrivalVehicle,
              )
              .map(
                (b) => Marker(
                  point: b.position,
                  width: 65,
                  height: 68,
                  alignment: const Alignment(0, .38),
                  child: GestureDetector(
                    onTap: () {
                      widget.journey.trackVehicle(b.coche);
                      widget.onMessage(
                        'Línea ${b.linea} · interno ${b.coche} · ubicación aproximada sobre el recorrido${b.isPredictive ? " · sin conexión" : ""}.',
                      );
                    },
                    child: BusMarker(
                      line: b.linea,
                      color: widget.journey.line?.color ?? blue,
                      selected: widget.journey.tracked?.coche == b.coche,
                    ),
                  ),
                ),
              ),
        ],
      ),
    ],
  );
}
