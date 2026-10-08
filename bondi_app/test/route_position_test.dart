import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bondi_app/services/route_position.dart';

void main() {
  final route = [const LatLng(-31.4, -64.2), const LatLng(-31.42, -64.2)];
  test('Aligns small lateral drift without changing original coordinates', () {
    const original = LatLng(-31.41, -64.1998);
    final adjusted = routePosition(original, route)!;
    expect(adjusted.longitude, -64.2);
    expect(adjusted.latitude, closeTo(-31.41, .000001));
    expect(original.longitude, -64.1998);
  });
  test(
    'Rejects remote coordinates and missing geometry; retains route points',
    () {
      expect(routePosition(const LatLng(-31.41, -64.199), route), isNull);
      expect(routePosition(route.first, []), isNull);
      expect(
        routePosition(route.first, route)!.longitude,
        route.first.longitude,
      );
    },
  );
}
