import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/journey_planner.dart';

void main() {
  final route = Ruta(id: 'r', sentido: 'I', nombre: 'Ida', longitud: '');
  final line = Linea(
    id: 'l',
    nombre: '70',
    grupo: '',
    colorHex: '',
    clienteId: 1,
    clienteNombre: '',
    rutas: [route],
  );
  Parada stop(String id, double lat) =>
      Parada(codigo: id, nombre: id, lat: lat, lon: -64.18);
  final a = stop('a', -31.42), b = stop('b', -31.40);
  final trace = Traza(
    lineaId: 'l',
    rutaId: 'r',
    colorHex: '',
    puntos: [a.position, b.position],
    paradas: [b, a],
  );
  test('Uses geometry direction even when stop array is reversed', () {
    final trip = JourneyPlanner.find(
      line,
      route,
      trace,
      a.position,
      b.position,
    );
    expect(trip?.boarding.codigo, 'a');
    expect(trip?.alighting.codigo, 'b');
  });
  test('Rejects wrong direction and a forced stop after destination', () {
    expect(
      JourneyPlanner.find(line, route, trace, b.position, a.position),
      isNull,
    );
    expect(
      JourneyPlanner.find(
        line,
        route,
        trace,
        a.position,
        b.position,
        boardingCode: 'b',
      ),
      isNull,
    );
  });
  test('Rejects excessive walking and missing geometry', () {
    expect(
      JourneyPlanner.find(
        line,
        route,
        trace,
        const LatLng(-31.50, -64.18),
        b.position,
      ),
      isNull,
    );
    final empty = Traza(
      lineaId: 'l',
      rutaId: 'r',
      colorHex: '',
      puntos: [],
      paradas: [a, b],
    );
    expect(
      JourneyPlanner.find(line, route, empty, a.position, b.position),
      isNull,
    );
  });
  test(
    'Selected route excludes travel before boarding and after alighting',
    () {
      final middle = LatLng(-31.41, -64.18);
      final geometry = Traza(
        lineaId: 'l',
        rutaId: 'r',
        colorHex: '',
        puntos: [a.position, middle, b.position],
        paradas: [a, b],
      );
      final start = stop('start', -31.419), end = stop('end', -31.401);
      final segment = JourneyPlanner.segment(geometry, start, end);
      expect(segment.first, start.position);
      expect(segment.last, end.position);
      expect(segment, contains(middle));
      expect(segment, isNot(contains(a.position)));
      expect(segment, isNot(contains(b.position)));
    },
  );
}
