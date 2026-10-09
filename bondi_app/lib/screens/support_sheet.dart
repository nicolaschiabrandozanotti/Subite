import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import 'package:flutter/services.dart';

class SupportSheet extends StatelessWidget {
  const SupportSheet({super.key});

  static const alias = 'nicochiabrando';
  static const cvu = '0000003100012189129203';
  static const owner = 'Nicolás Chiabrando Zanotti';

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado. Ya podés pegarlo en tu billetera.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite_outline, color: blue, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Bancá Subite',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Si Subite te sirve, podés aportar para mantener el proyecto y seguir mejorándolo.',
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: pale,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alias', style: TextStyle(color: Colors.blueGrey)),
                const SelectableText(
                  alias,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(owner),
                const SizedBox(height: 12),
                const Text('CVU', style: TextStyle(color: Colors.blueGrey)),
                const SelectableText(cvu),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _copy(context, alias),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar alias'),
                ),
                TextButton.icon(
                  onPressed: () => _copy(context, cvu),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar CVU'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Elegís cuánto aportar y cuándo. No hay cobro automático ni hace falta pagar para usar Subite.',
            style: TextStyle(color: Colors.blueGrey, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
