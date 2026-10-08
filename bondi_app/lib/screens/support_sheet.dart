import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportSheet extends StatelessWidget {
  const SupportSheet({super.key});

  static const alias = 'nicochiabrando';
  static const cvu = '0000003100012189129203';
  static const owner = 'Nicolás Chiabrando Zanotti';
  static final paymentUrl = Uri.parse('https://mpago.la/1LqRS6N');

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado. Ya podés pegarlo en tu billetera.'),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(paymentUrl, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Keep the transfer details available if the payment app cannot open.
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No pudimos abrir Mercado Pago'),
        content: const Text(
          'Podés copiar el alias y hacer el aporte desde tu banco o billetera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Aceptar'),
          ),
        ],
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
          const Icon(
            Icons.favorite_outline,
            color: Color(0xFF006CA8),
            size: 32,
          ),
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
              color: const Color(0xFFEAF2FF),
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir Mercado Pago'),
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
