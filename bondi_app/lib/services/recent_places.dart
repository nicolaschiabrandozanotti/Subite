import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class RecentPlace {
  final Parada point;
  final int uses;
  RecentPlace(this.point, this.uses);
}

class RecentPlaces {
  static String _key(bool origin) =>
      origin ? 'recent_origin_v1' : 'recent_destination_v1';
  static Future<List<RecentPlace>> load(bool origin) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(prefs.getString(_key(origin)) ?? '[]') as List;
      return data
          .map(
            (p) => RecentPlace(Parada.fromJson(p['point']), p['uses'] as int),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static bool _same(Parada a, Parada b) =>
      a.nombre == b.nombre &&
      (a.lat - b.lat).abs() < .00001 &&
      (a.lon - b.lon).abs() < .00001;
  static Future<void> remember(Parada point, bool origin) async {
    final previous = await load(origin);
    final matches = previous.where((p) => _same(p.point, point)).toList();
    final next = [
      RecentPlace(point, matches.isEmpty ? 1 : matches.first.uses + 1),
      ...previous.where((p) => !_same(p.point, point)),
    ].take(10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(origin),
      jsonEncode(
        next.map((p) => {'point': p.point.toJson(), 'uses': p.uses}).toList(),
      ),
    );
  }

  static Future<void> clear(bool origin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(origin));
  }
}
