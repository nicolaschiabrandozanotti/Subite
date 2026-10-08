import 'package:flutter/material.dart';

class SavePlaceDialog extends StatefulWidget {
  const SavePlaceDialog({super.key});
  @override
  State<SavePlaceDialog> createState() => _SavePlaceDialogState();
}

class _SavePlaceDialogState extends State<SavePlaceDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Guardá tu lugar'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(hintText: 'Casa, Trabajo, Facultad…'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
