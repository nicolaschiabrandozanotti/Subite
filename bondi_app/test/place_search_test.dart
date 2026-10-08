import 'package:flutter_test/flutter_test.dart';
import 'package:bondi_app/services/place_search_service.dart';

void main() {
  test('Local suggestions accept UTN abbreviations and unaccented names', () {
    for (final query in [
      'utn',
      'UTN FRC',
      'facultad regional cordoba',
      'universidad tecnologica',
    ]) {
      final results = PlaceSearchService.localSuggestions(query);
      expect(results.single.point.codigo, 'poi_utn_frc');
      expect(results.single.address, contains('Maestro Marcelo López'));
    }
    expect(PlaceSearchService.matches('Av. Vélez Sársfield', 'velez'), isTrue);
    expect(PlaceSearchService.localSuggestions('hospital'), isEmpty);
  });
  test('Street prefixes are equivalent and FAUD resolves both campuses', () {
    for (final query in [
      'Ambrosio Olmos',
      'Avenida Ambrosio Olmos',
      'Av. Ambrosio Olmos',
      'Avda Ambrosio Olmos',
    ]) {
      expect(PlaceSearchService.normalize(query), 'ambrosio olmos');
      expect(PlaceSearchService.matches('Ambrosio Olmos 691', query), isTrue);
    }
    for (final query in [
      'FAUD',
      'FAUD UNC',
      'facu de arquitectura',
      'universidad de arquitectura',
    ]) {
      expect(PlaceSearchService.localSuggestions(query).length, 2);
    }
    expect(
      PlaceSearchService.localSuggestions('FAUD centro').single.point.codigo,
      'poi_faud_unc_centro',
    );
    expect(
      PlaceSearchService.localSuggestions('FAUD ciudad universitaria')
          .single
          .point
          .codigo,
      'poi_faud_unc_campus',
    );
  });
}
