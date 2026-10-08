import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/saved_journey.dart';
import 'place_search_sheet.dart';

class SavedJourneyEditor extends StatefulWidget {
  final SavedJourney? existing;
  final Parada? origin, destination;
  final List<Parada> places;
  const SavedJourneyEditor({
    super.key,
    this.existing,
    this.origin,
    this.destination,
    required this.places,
  });
  @override
  State<SavedJourneyEditor> createState() => _SavedJourneyEditorState();
}

class _SavedJourneyEditorState extends State<SavedJourneyEditor> {
  late final TextEditingController name;
  Parada? origin, destination;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.existing?.name ?? '');
    origin = widget.existing?.origin ?? widget.origin;
    destination = widget.existing?.destination ?? widget.destination;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> choose(bool start) async {
    final point = await showModalBottomSheet<Parada>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => PlaceSearchSheet(
        places: widget.places,
        origin: start,
        onMap: () {
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Para usar un punto del mapa, elegilo en la pantalla principal antes de crear el viaje.',
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || point == null) return;
    setState(() {
      if (start) {
        origin = point;
      } else {
        destination = point;
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'Crear viaje guardado'
                  : 'Editar viaje guardado',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Casa → Facultad',
              ),
              maxLength: 50,
              onChanged: (_) => setState(() {}),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inicio'),
              subtitle: Text(origin?.nombre ?? 'Elegí un lugar'),
              trailing: const Icon(Icons.search),
              onTap: () => choose(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Destino'),
              subtitle: Text(destination?.nombre ?? 'Elegí un lugar'),
              trailing: const Icon(Icons.search),
              onTap: () => choose(false),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    name.text.trim().isEmpty ||
                        origin == null ||
                        destination == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        SavedJourney(
                          id:
                              widget.existing?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: name.text.trim(),
                          origin: origin!,
                          destination: destination!,
                        ),
                      ),
                child: const Text('Guardar viaje'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
