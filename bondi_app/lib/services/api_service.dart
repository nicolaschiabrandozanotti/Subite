import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class ApiService {
  static final http.Client _client = http.Client();
  @visibleForTesting
  static http.Client? testClient;
  static http.Client get _http => testClient ?? _client;
  static final Map<String, Future<Traza?>> _routeLoads = {};
  static final Map<String, Future<void>> _routeRefreshes = {};
  static Future<List<Linea>>? _lineLoad;
  static Future<List<Map<String, dynamic>>> fetchArrivals(String stop) async {
    final response = await _http
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
        data['err'] != false) {
      throw Exception('Upstream error');
    }
    final raw = data['proximos_arribos'];
    if (raw is! List) throw Exception('Unexpected arrivals');
    return raw.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  // Can be set to local server IP, emulator host (10.0.2.2) or public server
  static const String baseUrl = String.fromEnvironment(
    'BONDI_API_URL',
    defaultValue: 'https://subite-backend.onrender.com/api',
  );

  // 1. Fetch Lineas (Offline-first)
  static Future<List<Linea>> fetchLineas() async {
    final existing = _lineLoad;
    if (existing != null) return existing;
    final load = _fetchLineas();
    _lineLoad = load;
    try {
      return await load;
    } finally {
      _lineLoad = null;
    }
  }

  static List<Linea> _decodeLines(String body) {
    final rawLines = jsonDecode(body)['lineas'] as List;
    if (rawLines.isEmpty) throw const FormatException('Empty lines');
    final lines = rawLines
        .map((l) => Linea.fromJson(l as Map<String, dynamic>))
        .toList();
    if (lines.any((l) => l.id.isEmpty || l.nombre.isEmpty)) {
      throw const FormatException('Invalid line');
    }
    return lines;
  }

  static Future<List<Linea>> _fetchLineas() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cache_lineas');
    List<Linea>? savedLines;
    if (cached != null) {
      try {
        savedLines = _decodeLines(cached);
      } catch (_) {
        await prefs.remove('cache_lineas');
        await prefs.remove('cache_lineas_at');
      }
    }
    final savedAt = prefs.getInt('cache_lineas_at') ?? 0;
    if (savedLines != null &&
        DateTime.now().millisecondsSinceEpoch - savedAt <
            const Duration(minutes: 30).inMilliseconds) {
      return savedLines;
    }

    // 1. Try network
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl/lineas'))
          .timeout(Duration(seconds: savedLines == null ? 65 : 5));
      if (res.statusCode == 200) {
        final lines = _decodeLines(res.body);
        await prefs.setString('cache_lineas', res.body);
        await prefs.setInt(
          'cache_lineas_at',
          DateTime.now().millisecondsSinceEpoch,
        );
        return lines;
      }
    } catch (e) {
      // ignore network errors and fallback to cache
    }

    // 2. Fallback to cached lines
    return savedLines ?? [];
  }

  // 2. Fetch Traza & Paradas
  static Future<Traza?> fetchTraza(
    String lineaId,
    String rutaId,
    int clienteId, {
    bool refreshCached = true,
  }) async {
    final key = '${clienteId}_${lineaId}_$rutaId';
    final existing = _routeLoads[key];
    if (existing != null) return existing;
    final load = _fetchTraza(
      lineaId,
      rutaId,
      clienteId,
      refreshCached: refreshCached,
    );
    _routeLoads[key] = load;
    try {
      return await load;
    } finally {
      _routeLoads.remove(key);
    }
  }

  static Traza _decodeTrace(String body, String line, String route) {
    final trace = Traza.fromJson(jsonDecode(body));
    if (trace.lineaId != line ||
        trace.rutaId != route ||
        trace.puntos.isEmpty ||
        trace.paradas.isEmpty) {
      throw const FormatException('Invalid route');
    }
    return trace;
  }

  static Future<Traza?> _fetchTraza(
    String lineaId,
    String rutaId,
    int clienteId, {
    bool refreshCached = true,
  }) async {
    final cacheKey = 'cache_traza_full_v2_${clienteId}_${lineaId}_$rutaId';
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);

    if (cached != null) {
      try {
        final trace = _decodeTrace(cached, lineaId, rutaId);
        // fetch fresh in background
        final saved = prefs.getInt('${cacheKey}_at') ?? 0;
        if (refreshCached &&
            DateTime.now().millisecondsSinceEpoch - saved >
                const Duration(days: 1).inMilliseconds) {
          _refreshTrazaInBackground(lineaId, rutaId, clienteId, cacheKey);
        }
        return trace;
      } catch (_) {
        await prefs.remove(cacheKey);
        await prefs.remove('${cacheKey}_at');
      }
    }

    try {
      final res = await _http
          .get(
            Uri.parse(
              '$baseUrl/traza?linea=$lineaId&ruta=$rutaId&cliente=$clienteId',
            ),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final trace = _decodeTrace(res.body, lineaId, rutaId);
        await prefs.setString(cacheKey, res.body);
        await prefs.setInt(
          '${cacheKey}_at',
          DateTime.now().millisecondsSinceEpoch,
        );
        return trace;
      }
    } catch (_) {}

    return null;
  }

  static Future<void> _refreshTrazaInBackground(
    String lineaId,
    String rutaId,
    int clienteId,
    String cacheKey,
  ) async {
    final existing = _routeRefreshes[cacheKey];
    if (existing != null) return existing;
    final refresh = _refreshTraza(lineaId, rutaId, clienteId, cacheKey);
    _routeRefreshes[cacheKey] = refresh;
    try {
      await refresh;
    } finally {
      _routeRefreshes.remove(cacheKey);
    }
  }

  static Future<void> _refreshTraza(
    String lineaId,
    String rutaId,
    int clienteId,
    String cacheKey,
  ) async {
    try {
      final res = await _http
          .get(
            Uri.parse(
              '$baseUrl/traza?linea=$lineaId&ruta=$rutaId&cliente=$clienteId',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        _decodeTrace(res.body, lineaId, rutaId);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, res.body);
        await prefs.setInt(
          '${cacheKey}_at',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {}
  }

}
