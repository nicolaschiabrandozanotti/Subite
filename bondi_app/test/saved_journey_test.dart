import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/models/saved_journey.dart';
import 'package:bondi_app/models/models.dart';

void main() {
  test('Named journey persists both endpoints; a temporary selection cannot alter it', () async {
    SharedPreferences.setMockInitialValues({});
    final origin = Parada(codigo: 'a', nombre: 'Casa', lat: -31.4, lon: -64.2);
    final destination = Parada(
      codigo: 'b',
      nombre: 'Facultad',
      lat: -31.44,
      lon: -64.19,
    );
    final saved = SavedJourney(
      id: '1',
      name: 'A la facu',
      origin: origin,
      destination: destination,
    );
    expect(await SavedJourney.save([saved]), isTrue);
    final loaded = (await SavedJourney.load()).single;
    var currentDestination = loaded.destination;
    currentDestination = Parada(
      codigo: 'c',
      nombre: 'Trabajo',
      lat: -31.42,
      lon: -64.18,
    );
    expect(currentDestination.nombre, 'Trabajo');
    final unchanged = (await SavedJourney.load()).single;
    expect(unchanged.name, 'A la facu');
    expect(unchanged.origin.nombre, 'Casa');
    expect(unchanged.destination.nombre, 'Facultad');
  });
}
