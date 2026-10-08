import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bondi_app/services/route_catalog.dart';
import 'package:bondi_app/models/models.dart';

void main() {
  final routes = List.generate(
    9,
    (i) => Ruta(id: '$i', sentido: 'I', nombre: '', longitud: ''),
  );
  final line = Linea(
    id: '1',
    nombre: '1',
    grupo: '',
    colorHex: '',
    clienteId: 1,
    clienteNombre: '',
    rutas: routes,
  );
  test('Catalog bounds concurrency and completes despite errors', () async {
    var running = 0, peak = 0, progress = 0;
    final result = await loadRouteCatalog(
      [line],
      (line, route) async {
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        if (route.id == '2') throw Exception('network');
        return Traza(
          lineaId: line.id,
          rutaId: route.id,
          colorHex: '',
          puntos: [],
          paradas: [],
        );
      },
      keepGoing: () => true,
      onProgress: (done, total) {
        progress = done;
      },
    );
    expect(peak, 3);
    expect(progress, 9);
    expect(result.routes.length, 8);
    expect(result.unavailable, 1);
  });
  test('Canceled catalog stops scheduling work', () async {
    var keep = true, calls = 0;
    await loadRouteCatalog(
      [line],
      (line, route) async {
        calls++;
        keep = false;
        return null;
      },
      keepGoing: () => keep,
      onProgress: (_, _) {},
    );
    expect(calls, 1);
  });
  test('Deadline finishes even if a provider never answers', () async {
    final result = await loadRouteCatalog(
      [line],
      (_, _) => Completer<Traza?>().future,
      keepGoing: () => true,
      onProgress: (_, _) {},
      budget: const Duration(milliseconds: 20),
    );
    expect(result.routes, isEmpty);
    expect(result.unavailable, 9);
  });
}
