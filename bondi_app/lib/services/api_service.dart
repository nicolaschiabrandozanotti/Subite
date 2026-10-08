import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'predictive_engine.dart';

class ApiService {
  static Future<List<Map<String, dynamic>>> fetchArrivals(String stop) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/arrivals')
              .replace(queryParameters: {'stop': stop}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Arrivals unavailable');
    final data = jsonDecode(response.body);
    if (data['err'] != null &&
        data['err'].toString() != '0' &&
        data['err'].toString() != '' &&
        data['err'] != false)
      throw Exception('Upstream error');
    final raw = data['proximos_arribos'];
    if (raw is! List) throw Exception('Unexpected arrivals');
    return raw.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  // Can be set to local server IP, emulator host (10.0.2.2) or public server
  static const String baseUrl = String.fromEnvironment(
    'BONDI_API_URL',
    defaultValue: 'http://192.168.0.87:3001/api',
  );

  // In-memory cache
  static Traza? _cachedTraza;
  static List<Coche> _lastKnownBuses = [];
  static DateTime? _lastSnapshotTime;

  // 1. Fetch Lineas (Offline-first)
  static Future<List<Linea>> asyncFetchLineas() async {
    return fetchLineas();
  }

  static Future<List<Linea>> fetchLineas() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cache_lineas');

    // 1. Try network
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/lineas'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawLines = data['lineas'] as List? ?? [];
        await prefs.setString('cache_lineas', res.body);
        return rawLines
            .map((l) => Linea.fromJson(l as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      // ignore network errors and fallback to cache
    }

    // 2. Fallback to cached lines
    if (cached != null) {
      final data = jsonDecode(cached);
      final rawLines = data['lineas'] as List? ?? [];
      return rawLines
          .map((l) => Linea.fromJson(l as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  // 2. Fetch Traza & Paradas
  static Future<Traza?> fetchTraza(
    String lineaId,
    String rutaId,
    int clienteId, {
    bool refreshCached = true,
  }) async {
    final cacheKey = 'cache_traza_full_v2_${clienteId}_${lineaId}_$rutaId';
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);

    if (cached != null) {
      _cachedTraza = Traza.fromJson(jsonDecode(cached));
      // fetch fresh in background
      if (refreshCached)
        _refreshTrazaInBackground(lineaId, rutaId, clienteId, cacheKey);
      return _cachedTraza;
    }

    try {
      final res = await http
          .get(
            Uri.parse(
              '$baseUrl/traza?linea=$lineaId&ruta=$rutaId&cliente=$clienteId',
            ),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await prefs.setString(cacheKey, res.body);
        _cachedTraza = Traza.fromJson(data);
        return _cachedTraza;
      }
    } catch (_) {}

    return null;
  }

  static void _refreshTrazaInBackground(
    String lineaId,
    String rutaId,
    int clienteId,
    String cacheKey,
  ) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              '$baseUrl/traza?linea=$lineaId&ruta=$rutaId&cliente=$clienteId',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, res.body);
      }
    } catch (_) {}
  }

  // 3. Fetch Live or Predictive Buses
  static Future<Map<String, dynamic>> fetchCoches({
    required String rutaId,
    required int clienteId,
    required String lineaNombre,
    required Traza? traza,
    bool offline = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'last_coches_$rutaId';

    // 1. Try real GPS from network
    if (!offline)
      try {
        final res = await http
            .get(
              Uri.parse(
                '$baseUrl/coches?ruta=$rutaId&cliente=$clienteId&linea=$lineaNombre',
              ),
            )
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final raw = data['coches'] as List? ?? [];
          final coches = raw
              .map((c) => Coche.fromJson(c as Map<String, dynamic>))
              .toList();

          // Save last known snapshot
          _lastKnownBuses = coches;
          _lastSnapshotTime = DateTime.now();

          await prefs.setString(
            cacheKey,
            jsonEncode({
              'coches': coches.map((c) => c.toJson()).toList(),
              'timestamp': _lastSnapshotTime!.millisecondsSinceEpoch,
            }),
          );

          return {'coches': coches, 'isPredictive': false};
        }
      } catch (_) {
        // Network failed or offline
      }

    // 2. Offline: Use Predictive Engine from local snapshot
    String? rawCached = prefs.getString(cacheKey);
    if (rawCached != null) {
      try {
        final data = jsonDecode(rawCached);
        final rawList = data['coches'] as List? ?? [];
        final ts = DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] as int,
        );
        final cachedBuses = rawList
            .map((c) => Coche.fromJson(c as Map<String, dynamic>))
            .toList();

        final projected = PredictiveEngine.calculatePredictiveBuses(
          lastKnownBuses: cachedBuses,
          snapshotTime: ts,
          traza: traza ?? _cachedTraza,
        );

        return {'coches': projected, 'isPredictive': true};
      } catch (_) {}
    }

    return {'coches': <Coche>[], 'isPredictive': true};
  }
}
