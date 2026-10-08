import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class OfflineTrip {
  final Linea line;
  final Ruta route;
  final Traza trace;
  final Parada origin, destination, boarding, alighting;
  final DateTime savedAt;
  final List<Coche> buses;
  final DateTime? positionsAt;
  OfflineTrip(
    this.line,
    this.route,
    this.trace,
    this.origin,
    this.destination,
    this.boarding,
    this.alighting,
    this.savedAt, {
    this.buses = const [],
    this.positionsAt,
  });

  Future<bool> save() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(
      'offline_trip_v1',
      jsonEncode({
        'line': line.toJson(),
        'route': route.toJson(),
        'trace': {
          'lineaId': trace.lineaId,
          'rutaId': trace.rutaId,
          'color': trace.colorHex,
          'puntos': trace.puntos.map((p) => [p.latitude, p.longitude]).toList(),
          'paradas': trace.paradas.map((p) => p.toJson()).toList(),
        },
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'boarding': boarding.toJson(),
        'alighting': alighting.toJson(),
        'savedAt': savedAt.toIso8601String(),
        'buses': buses.map((bus) => bus.toJson()).toList(),
        'positionsAt': positionsAt?.toIso8601String(),
      }),
    );
  }

  static Future<OfflineTrip?> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString('offline_trip_v1');
      if (raw == null) return null;
      final data = jsonDecode(raw);
      return OfflineTrip(
        Linea.fromJson(data['line']),
        Ruta.fromJson(data['route']),
        Traza.fromJson(data['trace']),
        Parada.fromJson(data['origin']),
        Parada.fromJson(data['destination']),
        Parada.fromJson(data['boarding']),
        Parada.fromJson(data['alighting']),
        DateTime.parse(data['savedAt']),
        buses: (data['buses'] as List? ?? [])
            .map((bus) => Coche.fromJson(Map<String, dynamic>.from(bus)))
            .toList(),
        positionsAt: data['positionsAt'] == null
            ? null
            : DateTime.parse(data['positionsAt']),
      );
    } catch (_) {
      return null;
    }
  }
}
