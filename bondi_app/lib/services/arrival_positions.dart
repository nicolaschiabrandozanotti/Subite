import 'package:latlong2/latlong.dart';

import '../models/models.dart';

bool arrivalMatchesRoute(Map<String, dynamic> item, Linea line, Ruta route) =>
    '${item['linea']}' == line.id &&
    '${item['ruta']}' == route.id &&
    '${item['cliente']}' == '${line.clienteId}';

/// Stop-arrival `a` is [stop latitude, stop longitude, vehicle latitude,
/// vehicle longitude], verified against the official vehicle GPS response.
List<Coche> arrivalPositions(
  List<Map<String, dynamic>> arrivals,
  Parada stop,
  Linea line,
  Ruta route,
) {
  final seen = <int>{};
  final buses = <Coche>[];
  for (final item in arrivals) {
    if (!arrivalMatchesRoute(item, line, route)) {
      continue;
    }
    final id = int.tryParse('${item['coche']}');
    final a = item['a'];
    if (id == null || id <= 0 || a is! List || a.length != 4) continue;
    final coords = a.map((v) => double.tryParse('$v')).toList();
    if (coords.any((v) => v == null || !v.isFinite)) continue;
    final lat = coords[2]!, lon = coords[3]!;
    if (lat.abs() > 90 || lon.abs() > 180 || lat == 0 || lon == 0) continue;
    if (coords[0]!.abs() > 90 || coords[1]!.abs() > 180) continue;
    if (const Distance()(stop.position, LatLng(coords[0]!, coords[1]!)) > 30) {
      continue;
    }
    if (!seen.add(id)) continue;
    buses.add(
      Coche(
        coche: id,
        linea: line.nombre,
        sentido: '${item['sentido'] ?? route.sentido}',
        lat: lat,
        lon: lon,
        curso: 0,
        demora: '${item['proximo'] ?? ''}',
        rampa: item['rampa'] == 1 || item['rampa'] == '1',
      ),
    );
  }
  return buses;
}
