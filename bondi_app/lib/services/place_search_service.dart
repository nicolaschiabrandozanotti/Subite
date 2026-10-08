import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_service.dart';

class PlaceSuggestion {
  final Parada point;
  final String address;
  final bool requiresMap;
  const PlaceSuggestion(this.point, this.address, {this.requiresMap = false});
}

class PlaceSearchService {
  static String normalize(String text) {
    var result = text.toLowerCase().trim();
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    accents.forEach((a, b) => result = result.replaceAll(a, b));
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result
        .replaceFirst(
          RegExp(r'^(avenida|av\.?|avda\.?|calle)\s+', caseSensitive: false),
          '',
        )
        .trim();
  }

  static bool matches(String name, String query) {
    final n = normalize(name), q = normalize(query);
    return q.isEmpty || q.split(' ').every((token) => n.contains(token));
  }

  // Coordinate: https://www.wikidata.org/wiki/Q5854479
  // Address: https://www.frc.utn.edu.ar/secretarias/relacionesinstitucionales/?pIs=3717
  static List<PlaceSuggestion> localSuggestions(String query) {
    final architecture = matches(
      'FAUD UNC Facultad facu de Arquitectura Urbanismo y Diseño Universidad Nacional Córdoba sede centro ciudad universitaria',
      query,
    );
    if (normalize(query).isNotEmpty && architecture) {
      // Addresses: official FAUD/UNC publications. OSM building coordinates:
      // ways 103537771 (Ciudad Universitaria), 1073692572 (Centro).
      final center = normalize(query).contains('centro');
      final campus = normalize(query).contains('universitaria');
      return [
        if (!center)
          PlaceSuggestion(
            Parada(
              codigo: 'poi_faud_unc_campus',
              nombre: 'FAUD · Ciudad Universitaria',
              lat: -31.4387355,
              lon: -64.1911006,
            ),
            'Facultad de Arquitectura, Urbanismo y Diseño · Haya de la Torre, Córdoba',
          ),
        if (!campus)
          PlaceSuggestion(
            Parada(
              codigo: 'poi_faud_unc_centro',
              nombre: 'FAUD · Sede Centro',
              lat: -31.41815,
              lon: -64.1881649,
            ),
            'Facultad de Arquitectura, Urbanismo y Diseño · Vélez Sársfield 264, Córdoba',
          ),
      ];
    }
    if (normalize(query).isEmpty ||
        !matches(
          'UTN FRC Facultad Regional Córdoba Universidad Tecnológica Nacional',
          query,
        )) {
      return [];
    }
    return [
      PlaceSuggestion(
        Parada(
          codigo: 'poi_utn_frc',
          nombre: 'UTN · Facultad Regional Córdoba',
          lat: -31.4423306,
          lon: -64.1932389,
        ),
        'Maestro Marcelo López y Cruz Roja Argentina, Córdoba',
      ),
    ];
  }

  static Future<List<PlaceSuggestion>> search(String query) async {
    if (localSuggestions(query)
        .any((p) => p.point.codigo.startsWith('poi_faud_'))) {
      return [];
    }
    final uri = Uri.parse('${ApiService.baseUrl}/places')
        .replace(queryParameters: {'q': query.trim()});
    final response = await http.get(uri).timeout(const Duration(seconds: 14));
    if (response.statusCode != 200) throw Exception('Buscador no disponible');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['places'] as List)
        .map(
          (p) => PlaceSuggestion(
            Parada.fromJson(p),
            p['direccion'] as String? ?? 'Córdoba',
            requiresMap: p['requiresMap'] == true,
          ),
        )
        .toList();
  }
}
