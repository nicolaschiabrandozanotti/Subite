import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import 'journey_planner.dart';

class PredictiveEngine {
  // Fixed approximation, not a measured speed: 18 km/h = 5 m/s.
  static const double urbanSpeedMetersPerSec = 5.0;
  static final Distance distanceCalc = const Distance();

  static List<Coche> calculatePredictiveBuses({
    required List<Coche> lastKnownBuses,
    required DateTime snapshotTime,
    required Traza? traza,
    DateTime? now,
  }) {
    if (lastKnownBuses.isEmpty) return [];

    final elapsedSeconds = max(
      0,
      (now ?? DateTime.now()).difference(snapshotTime).inSeconds,
    );
    final elapsedMinutes = (elapsedSeconds / 60).floor();

    // Stop at the route end; never invent another lap or reset old positions.

    final polyline = traza?.puntos ?? [];
    final distanceToAdvance = elapsedSeconds * urbanSpeedMetersPerSec;

    return lastKnownBuses
        .where(
          (bus) =>
              polyline.length >= 2 &&
              JourneyPlanner.progress(bus.position, polyline) != null,
        )
        .map((bus) {
          // Advance from the projected position, not the nearest route vertex.
          double remaining =
              JourneyPlanner.progress(bus.position, polyline)! +
              distanceToAdvance;
          int currentIdx = 0;

          while (currentIdx < polyline.length - 1) {
            final p1 = polyline[currentIdx];
            final p2 = polyline[currentIdx + 1];
            final segDist = distanceCalc.as(LengthUnit.Meter, p1, p2);

            if (remaining >= segDist) {
              remaining -= segDist;
              currentIdx++;
            } else {
              final ratio = remaining / max(segDist, 1.0);
              final lat = p1.latitude + (p2.latitude - p1.latitude) * ratio;
              final lon = p1.longitude + (p2.longitude - p1.longitude) * ratio;

              // Heading in radians
              final dLon = p2.longitude - p1.longitude;
              final dLat = p2.latitude - p1.latitude;
              final heading = atan2(dLon, dLat);

              return Coche(
                coche: bus.coche,
                linea: bus.linea,
                sentido: bus.sentido,
                lat: lat,
                lon: lon,
                curso: heading,
                demora:
                    'Estimación · dato de hace $elapsedMinutes min · incertidumbre alta',
                rampa: bus.rampa,
                ultimaActualizacion: bus.ultimaActualizacion,
                isPredictive: true,
              );
            }
          }

          final end = polyline[min(currentIdx, polyline.length - 1)];
          return Coche(
            coche: bus.coche,
            linea: bus.linea,
            sentido: bus.sentido,
            lat: end.latitude,
            lon: end.longitude,
            curso: bus.curso,
            demora:
                'Fin estimado · dato de hace $elapsedMinutes min · no confirmado',
            rampa: bus.rampa,
            ultimaActualizacion: bus.ultimaActualizacion,
            isPredictive: true,
          );
        })
        .toList();
  }
}
