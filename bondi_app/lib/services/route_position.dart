import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Visual alignment only. Never changes the original vehicle coordinate or ETA.
LatLng? routePosition(
  LatLng location,
  List<LatLng> route, {
  double maxDistance = 40,
}) {
  if (route.length < 2) return null;
  final scale = math.cos(location.latitude * math.pi / 180);
  double nearest = double.infinity;
  LatLng? result;
  for (var i = 1; i < route.length; i++) {
    final a = route[i - 1], b = route[i];
    final dx = (b.longitude - a.longitude) * scale;
    final dy = b.latitude - a.latitude;
    final divisor = dx * dx + dy * dy;
    final t = divisor == 0
        ? 0.0
        : (((location.longitude - a.longitude) * scale * dx +
                      (location.latitude - a.latitude) * dy) /
                  divisor)
              .clamp(0.0, 1.0);
    final projected = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
    final distance = const Distance()(location, projected);
    if (distance < nearest) {
      nearest = distance;
      result = projected;
    }
  }
  return nearest <= maxDistance ? result : null;
}
