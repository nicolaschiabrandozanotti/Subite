import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/journey_controller.dart';
import '../services/journey_planner.dart';
import '../services/arrival_positions.dart';
import '../theme/app_theme.dart';
import 'journey_stop_timeline.dart';

class JourneyResultsPanel extends StatelessWidget {
  final JourneyController journey;
  final Position? position;
  final void Function(LatLng, double) onFocusPoint;
  final void Function(DirectJourney) onChooseTrip;
  final VoidCallback onShowBuses,
      onPreferences,
      onSaveDestination,
      onOpenOffline,
      onReconnect;
  const JourneyResultsPanel({
    super.key,
    required this.journey,
    this.position,
    required this.onFocusPoint,
    required this.onChooseTrip,
    required this.onShowBuses,
    required this.onPreferences,
    required this.onSaveDestination,
    required this.onOpenOffline,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) => _journeyResults();

  String _arrivalLabel(Map<String, dynamic> arrival) {
    final seconds = journey.arrivalSeconds(arrival);
    if (seconds == null) return 'Horario sin confirmar';
    if (seconds < 60) return 'Llegando';
    return 'En ${(seconds / 60).ceil()} min';
  }

  List<Map<String, dynamic>> _sortedArrivals(
    Iterable<Map<String, dynamic>> arrivals,
  ) => arrivals.toList()
    ..sort(
      (a, b) => (journey.arrivalSeconds(a) ?? 99999).compareTo(
        journey.arrivalSeconds(b) ?? 99999,
      ),
    );

  Widget _selectedTripPanel() {
    final arrivals = _sortedArrivals(
      journey.arrivals.where(
        (a) =>
            journey.line != null &&
            journey.route != null &&
            arrivalMatchesRoute(a, journey.line!, journey.route!),
      ),
    );
    final buses = journey.visibleBuses;
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: journey.line?.color ?? blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Línea ${journey.line?.nombre ?? ""}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Actualizar llegadas',
                onPressed: () async {
                  await journey.refresh();
                },
                icon: const Icon(Icons.refresh, color: blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Subís en ${journey.pickup?.nombre ?? "la parada"}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Bajás en ${journey.dropoff?.nombre ?? "tu destino"}',
            style: const TextStyle(fontSize: 14, color: ink),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                if (buses.isNotEmpty) {
                  onShowBuses();
                } else if (journey.pickup != null) {
                  onFocusPoint(journey.pickup!.position, 16);
                }
              },
              icon: Icon(
                buses.isNotEmpty
                    ? Icons.directions_bus
                    : Icons.signpost_outlined,
              ),
              label: Text(
                buses.isNotEmpty
                    ? 'Ver colectivos y parada'
                    : 'Ver parada de subida',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            journey.offline ? 'Posiciones estimadas' : 'Próximos colectivos',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (journey.offline)
            Text(
              journey.preparedTrip?.positionsAt == null
                  ? 'Mapa y recorrido disponibles sin conexión.'
                  : 'Datos de hace ${DateTime.now().difference(journey.preparedTrip!.positionsAt!).inMinutes.clamp(0, 99999)} min · avance supuesto a 18 km/h · no son en vivo.',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          if (!journey.offline && arrivals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                journey.arrivalError ??
                    'Todavía no hay llegadas para esta línea.',
                style: const TextStyle(color: Colors.blueGrey),
              ),
            ),
          if (journey.offline && buses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Este viaje no tiene ubicaciones de colectivos guardadas.',
              ),
            ),
          if (!journey.offline)
            ...arrivals.map((arrival) {
              final id = int.tryParse('${arrival['coche']}');
              final matches = buses.where((b) => b.coche == id);
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.directions_bus,
                    color: journey.line?.color ?? blue,
                  ),
                  title: Text(
                    _arrivalLabel(arrival),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: blue,
                    ),
                  ),
                  subtitle: Text(
                    'Interno ${arrival['coche']}${arrival['dist_parada'] != null ? " · ${arrival['dist_parada']} m a la parada" : ""}${matches.isEmpty ? " · ubicación pendiente" : ""}',
                  ),
                  trailing: Icon(
                    journey.arrivalVehicle == id
                        ? Icons.check_circle
                        : Icons.chevron_right,
                    color: blue,
                  ),
                  onTap: id == null
                      ? null
                      : () {
                          journey.trackVehicle(id);
                          if (journey.tracked != null) {
                            onFocusPoint(journey.tracked!.position, 15);
                          }
                        },
                ),
              );
            }),
          if (journey.offline)
            ...buses.map(
              (bus) => Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.directions_bus,
                    color: journey.line?.color ?? blue,
                  ),
                  title: Text('Interno ${bus.coche}'),
                  subtitle: Text(bus.demora),
                  onTap: () {
                    journey.trackVehicle(bus.coche);
                    onFocusPoint(bus.position, 15);
                  },
                ),
              ),
            ),
          if (journey.arrivalVehicle != null)
            TextButton(
              onPressed: () => journey.trackVehicle(null),
              child: const Text('Mostrar todos los colectivos'),
            ),
          if (!journey.offline && journey.tripOptions.length > 1)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Otras líneas que te llevan'),
              children: [_journeyResults(comparisonOnly: true)],
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Paradas hasta tu bajada'),
            subtitle: Text('${journey.tripStops.length} paradas en este tramo'),
            children: [
              JourneyStopTimeline(
                stops: journey.tripStops,
                trace: journey.trace,
                position: position,
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Opciones del viaje'),
            children: [
              if (!journey.offline)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: journey.prepareOffline,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Preparar viaje sin datos'),
                  ),
                ),
              if (journey.preparedTrip != null && !journey.offline)
                TextButton(
                  onPressed: onOpenOffline,
                  child: const Text('Abrir viaje sin datos'),
                ),
              if (journey.offline)
                TextButton(
                  onPressed: onReconnect,
                  child: const Text('Salir del modo sin datos'),
                ),
              TextButton.icon(
                onPressed: onPreferences,
                icon: const Icon(Icons.tune),
                label: const Text('Cambiar preferencias'),
              ),
              TextButton.icon(
                onPressed: onSaveDestination,
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('Guardar destino'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _journeyResults({bool comparisonOnly = false}) {
    if (journey.inTrip && !comparisonOnly) return _selectedTripPanel();
    if (!journey.planned || journey.offline) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (journey.planning) ...[
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Buscando cómo llegar…'),
          ),
          TextButton(
            onPressed: () {
              journey.cancelPlanning();
            },
            child: const Text('Cancelar búsqueda'),
          ),
        ],
        if (!journey.planning && journey.tripOptions.isNotEmpty) ...[
          if (!comparisonOnly) ...[
            const Text(
              'Compará líneas y paradas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const Text('Buscando la mejor llegada para tu caminata…'),
            if (journey.planningFailed > 0)
              Text(
                'Algunas líneas no están disponibles. Podés volver a buscar.',
              ),
            const SizedBox(height: 12),
            const Text(
              'COMPARÁ LÍNEAS Y PARADAS',
              style: TextStyle(color: blue, fontWeight: FontWeight.w700),
            ),
          ],
          SizedBox(
            height: 280,
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                scrollDirection: Axis.horizontal,
                children: journey.tripOptions.map((trip) {
                  final arrivals =
                      (journey.arrivalsByStop[trip.boarding.codigo] ??
                              <Map<String, dynamic>>[])
                          .where(
                            (a) =>
                                arrivalMatchesRoute(a, trip.line, trip.route),
                          )
                          .toList();
                  arrivals.sort(
                    (a, b) => (journey.arrivalSeconds(a) ?? 99999).compareTo(
                      journey.arrivalSeconds(b) ?? 99999,
                    ),
                  );
                  return Container(
                    width: constraints.maxWidth >= 1000
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth >= 650
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth * .9),
                    margin: const EdgeInsets.only(right: 12, top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pale,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SingleChildScrollView(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.directions_bus,
                          color: trip.line.color,
                        ),
                        title: Text(
                          'Línea ${trip.line.nombre}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.route.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Subís: ${trip.boarding.nombre}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Caminata: ${trip.walkStart.round()} m · aprox. ${(trip.walkStart / 72).ceil()} min',
                              ),
                              Text('Bajás: ${trip.alighting.nombre}'),
                              const SizedBox(height: 8),
                              Text(
                                journey.arrivalStopErrors.contains(
                                      trip.boarding.codigo,
                                    )
                                    ? 'Llegadas sin confirmar'
                                    : !journey.arrivalsByStop.containsKey(
                                        trip.boarding.codigo,
                                      )
                                    ? 'Consultando llegadas…'
                                    : (arrivals.isEmpty
                                          ? 'Todavía no hay próximas llegadas disponibles'
                                          : arrivals
                                                .map(
                                                  (a) =>
                                                      '${_arrivalLabel(a)} · interno ${a['coche']}${a['dist_parada'] != null ? " · ${a['dist_parada']} m" : ""}',
                                                )
                                                .join('\n')),
                                style: const TextStyle(
                                  color: blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text(
                                'Llegadas estimadas',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Icon(
                          journey.inTrip && journey.route?.id == trip.route.id
                              ? Icons.check_circle
                              : Icons.chevron_right,
                          color: blue,
                        ),
                        onTap: () => onChooseTrip(trip),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
