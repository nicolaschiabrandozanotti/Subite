import 'package:flutter_test/flutter_test.dart';
import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/arrival_positions.dart';

void main() {
  final stop = Parada(
    codigo: 'CE53',
    nombre: 'Av Olmos',
    lat: -31.41373,
    lon: -64.182875,
  );
  final route = Ruta(id: '211', sentido: 'I', nombre: '', longitud: '');
  final line = Linea(
    id: '70',
    nombre: '70',
    grupo: '',
    colorHex: '',
    clienteId: 422,
    clienteNombre: '',
    rutas: [route],
  );
  final item = <String, dynamic>{
    'coche': '562',
    'linea': '70',
    'ruta': '211',
    'cliente': 422,
    'a': [-31.41373, -64.182875, -31.411196, -64.19158],
  };
  test(
    'Arrival retains official internal and GPS rather than stop coordinates',
    () {
      final bus = arrivalPositions([item, item], stop, line, route).single;
      expect(bus.coche, 562);
      expect(bus.lat, -31.411196);
      expect(bus.lon, -64.19158);
      expect(bus.isPredictive, isFalse);
    },
  );
  test('Rejects other route, stop, malformed or missing coordinates', () {
    for (final change in [
      {'ruta': '212'},
      {'cliente': 421},
      {
        'a': [0, 0, -31.4, -64.2],
      },
      {
        'a': [1, 2],
      },
      {'a': null},
    ]) {
      expect(
        arrivalPositions(
          [
            {...item, ...change},
          ],
          stop,
          line,
          route,
        ),
        isEmpty,
      );
    }
  });
}
