import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/recent_places.dart';

Parada point(int n) =>
    Parada(codigo: '$n', nombre: 'Lugar $n', lat: -31.4, lon: -64.2 + n / 1000);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Persists coordinates, moves reused place first and separates endpoints',
    () async {
      await RecentPlaces.remember(point(1), true);
      await RecentPlaces.remember(point(2), true);
      await RecentPlaces.remember(point(1), true);
      await RecentPlaces.remember(point(3), false);
      final origins = await RecentPlaces.load(true);
      expect(origins.map((p) => p.point.nombre), ['Lugar 1', 'Lugar 2']);
      expect(origins.first.uses, 2);
      expect(origins.first.point.lon, point(1).lon);
      expect((await RecentPlaces.load(false)).single.point.nombre, 'Lugar 3');
      await RecentPlaces.clear(true);
      expect(await RecentPlaces.load(true), isEmpty);
      expect(await RecentPlaces.load(false), hasLength(1));
    },
  );
  test('Keeps only ten most recent places', () async {
    for (var i = 0; i < 12; i++) {
      await RecentPlaces.remember(point(i), true);
    }
    final loaded = await RecentPlaces.load(true);
    expect(loaded, hasLength(10));
    expect(loaded.first.point.nombre, 'Lugar 11');
    expect(loaded.last.point.nombre, 'Lugar 2');
  });
}
