import 'dart:convert';

import '../models/models.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SavedJourney {
  final String id, name;
  final Parada origin, destination;
  const SavedJourney({
    required this.id,
    required this.name,
    required this.origin,
    required this.destination,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'origin': origin.toJson(),
    'destination': destination.toJson(),
  };
  factory SavedJourney.fromJson(Map<String, dynamic> data) => SavedJourney(
    id: data['id'],
    name: data['name'],
    origin: Parada.fromJson(data['origin']),
    destination: Parada.fromJson(data['destination']),
  );
  static Future<List<SavedJourney>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return (jsonDecode(prefs.getString('saved_journeys') ?? '[]') as List)
          .map((p) => SavedJourney.fromJson(p))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> save(List<SavedJourney> routes) async =>
      (await SharedPreferences.getInstance()).setString(
        'saved_journeys',
        jsonEncode(routes.map((p) => p.toJson()).toList()),
      );
}
