import 'package:latlong2/latlong.dart';

import '../models/models.dart';

class DirectJourney {
  final Linea line;
  final Ruta route;
  final Traza trace;
  final Parada boarding;
  final Parada alighting;
  final double walkStart;
  final double walkEnd;
  DirectJourney(
    this.line,
    this.route,
    this.trace,
    this.boarding,
    this.alighting,
    this.walkStart,
    this.walkEnd,
  );
  double get walking => walkStart + walkEnd;
}

/// Finds direct trips only. Walking distances are straight-line estimates.
/// Route geometry establishes direction; API stop array order is not assumed.
class JourneyPlanner {
  static final _distance = Distance();

  static List<LatLng> segment(Traza trace, Parada boarding, Parada alighting) {
    final start = progress(boarding.position, trace.puntos);
    final end = progress(alighting.position, trace.puntos);
    if (start == null || end == null || end <= start) return [];
    final points = <LatLng>[boarding.position];
    double traveled = 0;
    for (var i = 1; i < trace.puntos.length; i++) {
      traveled += _distance(trace.puntos[i - 1], trace.puntos[i]);
      if (traveled > start && traveled < end) points.add(trace.puntos[i]);
    }
    points.add(alighting.position);
    return points;
  }

  static double? progress(LatLng location, List<LatLng> points) {
    if (points.length < 2) return null;
    double traveled = 0, nearest = double.infinity, result = 0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final length = _distance(a, b);
      final divisor = dx * dx + dy * dy;
      final t = divisor == 0
          ? 0.0
          : (((location.longitude - a.longitude) * dx +
                        (location.latitude - a.latitude) * dy) /
                    divisor)
                .clamp(0.0, 1.0);
      final projected = LatLng(a.latitude + dy * t, a.longitude + dx * t);
      final separation = _distance(location, projected);
      if (separation < nearest) {
        nearest = separation;
        result = traveled + length * t;
      }
      traveled += length;
    }
    // Discard stops outside the supplied geometry rather than guessing direction.
    return nearest > 100 ? null : result;
  }

  static DirectJourney? find(
    Linea line,
    Ruta route,
    Traza trace,
    LatLng origin,
    LatLng destination, {
    String? boardingCode,
  }) {
    final ordered = <(Parada, double)>[];
    for (final stop in trace.paradas) {
      // Far stops cannot be either endpoint; avoid projecting every stop onto
      // hundreds of geometry segments on a low-end phone.
      if (_distance(origin, stop.position) > 800 &&
          _distance(destination, stop.position) > 800) {
        continue;
      }
      final position = progress(stop.position, trace.puntos);
      if (position != null) ordered.add((stop, position));
    }
    DirectJourney? best;
    for (final start in ordered) {
      if (boardingCode != null && start.$1.codigo != boardingCode) continue;
      final before = _distance(origin, start.$1.position);
      if (before > 800) continue;
      for (final end in ordered) {
        if (end.$2 <= start.$2 + 50) continue;
        final after = _distance(destination, end.$1.position);
        if (after > 800) continue;
        final candidate = DirectJourney(
          line,
          route,
          trace,
          start.$1,
          end.$1,
          before,
          after,
        );
        if (best == null ||
            candidate.walkStart < best.walkStart ||
            (candidate.walkStart == best.walkStart &&
                candidate.walkEnd < best.walkEnd)) {
          best = candidate;
        }
      }
    }
    return best;
  }
}
