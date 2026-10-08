import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> entries = [];
  bool loading = true;
  String fare = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> saved = [];
    try {
      saved = (jsonDecode(prefs.getString('expenses_v1') ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    if (mounted)
      setState(() {
        entries = saved;
        fare = prefs.getString('expense_fare_v1') ?? '';
        loading = false;
      });
  }

  String money(int cents) =>
      '\$ ${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';
  Future<bool> save(List<Map<String, dynamic>> next) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString('expenses_v1', jsonEncode(next));
    if (mounted && ok) setState(() => entries = next);
    return ok;
  }

  Future<void> add() async {
    var amount = fare;
    var line = '';
    bool free = false;
    DateTime date = DateTime.now();
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Registrar viaje'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Viajo gratis'),
                  subtitle: const Text('Beneficio, pase o gratuidad'),
                  value: free,
                  onChanged: (v) => update(() {
                    free = v;
                    error = null;
                  }),
                ),
                if (!free)
                  TextFormField(
                    initialValue: amount,
                    onChanged: (value) => amount = value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Importe en pesos',
                      hintText: 'Ej. 1500,50',
                      errorText: error,
                    ),
                  ),
                TextFormField(
                  initialValue: line,
                  onChanged: (value) => line = value,
                  decoration: const InputDecoration(
                    labelText: 'Línea o nota (opcional)',
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('${date.day}/${date.month}/${date.year}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null && ctx.mounted)
                      update(() => date = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final text = amount.trim().replaceAll(',', '.');
                final value = double.tryParse(text);
                if (!free &&
                    (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text) ||
                        value == null ||
                        !value.isFinite ||
                        value <= 0 ||
                        value > 100000000)) {
                  update(
                    () => error = 'Ingresá un importe mayor a 0, sin separadores de miles.',
                  );
                  return;
                }
                Navigator.pop(ctx, <String, dynamic>{
                  'date': date.toIso8601String(),
                  'cents': free ? 0 : (value! * 100).round(),
                  'note': line.trim(),
                  'free': free,
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final ok = await save(
      [result, ...entries]
        ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')),
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar el gasto.')),
      );
      return;
    }
    if (result['free'] == false) {
      fare = '${(result['cents'] as int) / 100}';
      await (await SharedPreferences.getInstance()).setString(
        'expense_fare_v1',
        fare,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = entries.where((e) {
      final d = DateTime.parse(e['date']);
      return d.year == now.year && d.month == now.month;
    }).toList();
    final total = month.fold<int>(0, (sum, e) => sum + (e['cents'] as int));
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Gastos de bondi'),
        actions: [
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: loading ? null : add,
        icon: const Icon(Icons.add),
        label: const Text('Registrar viaje'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Gastado este mes'),
                      Text(
                        money(total),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${month.length} viajes · ${month.where((e) => e['free'] == true).length} gratis',
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Carga manual en pesos. El último importe pago se recuerda para el próximo viaje; podés cambiarlo.',
                  ),
                ),
                if (entries.isEmpty)
                  const Text('Todavía no registraste viajes.'),
                ...entries.map((e) {
                  final date = DateTime.parse(e['date']);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e['free'] == true
                          ? Icons.card_membership
                          : Icons.payments_outlined,
                      color: const Color(0xFF006CA8),
                    ),
                    title: Text(
                      e['note'].toString().isEmpty
                          ? 'Viaje en colectivo'
                          : e['note'],
                    ),
                    subtitle: Text(
                      '${date.day}/${date.month}/${date.year} · ${e['free'] == true ? "Gratis" : "Pago"}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(money(e['cents'])),
                        IconButton(
                          tooltip: 'Eliminar registro',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('¿Eliminar este registro?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && mounted)
                              await save(
                                entries
                                    .where((item) => !identical(item, e))
                                    .toList(),
                              );
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
