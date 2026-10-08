import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    ApiService.testClient?.close();
    ApiService.testClient = null;
  });
  String trace(String line, String route) => jsonEncode({
    'lineaId': line,
    'rutaId': route,
    'puntos': [
      [-31.4, -64.2],
    ],
    'paradas': [
      {'codigo': '123', 'nombre': 'Parada', 'lat': -31.4, 'lon': -64.2},
    ],
  });

  test(
    'Concurrent route requests share network and fresh cache stays local',
    () async {
      int calls = 0;
      final gate = Completer<void>();
      ApiService.testClient = MockClient((r) async {
        calls++;
        await gate.future;
        return http.Response(trace('70', '211'), 200);
      });
      final loads = List.generate(
        20,
        (_) => ApiService.fetchTraza('70', '211', 422),
      );
      gate.complete();
      final results = await Future.wait(loads);
      expect(results.every((r) => r?.rutaId == '211'), isTrue);
      expect(calls, 1);
      await ApiService.fetchTraza('70', '211', 422);
      expect(calls, 1);
    },
  );

  test(
    'Corrupt and mismatched routes cannot poison persistent cache',
    () async {
      SharedPreferences.setMockInitialValues({
        'cache_traza_full_v2_422_70_211': 'broken',
      });
      ApiService.testClient = MockClient(
        (r) async => http.Response(trace('99', 'wrong'), 200),
      );
      expect(await ApiService.fetchTraza('70', '211', 422), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache_traza_full_v2_422_70_211'), isNull);
    },
  );

  test('Malformed line response preserves the last valid catalog', () async {
    final valid = jsonEncode({
      'lineas': [
        {'id': '70', 'nombre': '70', 'clienteId': 422, 'rutas': []},
      ],
    });
    SharedPreferences.setMockInitialValues({'cache_lineas': valid});
    ApiService.testClient = MockClient(
      (r) async => http.Response('{"error":"offline"}', 200),
    );
    expect((await ApiService.fetchLineas()).single.id, '70');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cache_lineas'), valid);
  });
}
