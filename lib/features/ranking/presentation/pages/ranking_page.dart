import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../auditoria/domain/entities/auditoria.dart';
import '../../../../shared/area_vista.dart';

/// Clasificación de centros por la puntuación de su última auditoría cerrada.
class RankingPage extends ConsumerWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(historicoProvider);
    final ranking = ref.watch(rankingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ranking de centros')),
      body: historico.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('No se pudo cargar el histórico:\n$e')),
        data: (_) {
          if (ranking.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no hay auditorías cerradas.\n'
                  'El ranking aparece en cuanto finalices la primera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          // Las áreas salen de la plantilla vigente. Si todavía no ha
          // cargado, se pintan las tarjetas sin el desglose por área.
          final areas = ref.watch(plantillaProvider(null)).value?.areas ?? const [];
          final vista = AreaVista.listaDesde(areas);

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: ranking.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _Tarjeta(posicion: i + 1, auditoria: ranking[i], areas: vista),
          );
        },
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.posicion,
    required this.auditoria,
    required this.areas,
  });

  final int posicion;
  final Auditoria auditoria;
  final List<AreaVista> areas;

  @override
  Widget build(BuildContext context) {
    final color = _colorNota(auditoria.puntuacionGlobal);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                _Medalla(posicion: posicion),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(auditoria.centroNombre,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(_fecha(auditoria.fecha),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${auditoria.puntuacionGlobal.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                    Text('Nivel ${auditoria.nivel}',
                        style: TextStyle(fontSize: 11, color: color)),
                  ],
                ),
              ],
            ),
            if (areas.isNotEmpty) const SizedBox(height: 10),
            // Desglose por área: dos centros con la misma nota global pueden
            // tener problemas en sitios muy distintos.
            Row(
              children: [
                for (final area in areas)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: auditoria.porcentajeArea(area.codigo) / 100,
                              minHeight: 6,
                              color: area.color,
                              backgroundColor: area.color.withValues(alpha: 0.15),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${auditoria.porcentajeArea(area.codigo).round()}%',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorNota(double p) {
    if (p >= 90) return Colors.green.shade700;
    if (p >= 80) return Colors.lightGreen.shade800;
    if (p >= 65) return Colors.orange.shade800;
    return Colors.red.shade800;
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _Medalla extends StatelessWidget {
  const _Medalla({required this.posicion});
  final int posicion;

  @override
  Widget build(BuildContext context) {
    const colores = {1: Color(0xFFFFD700), 2: Color(0xFFC0C0C0), 3: Color(0xFFCD7F32)};
    final color = colores[posicion] ?? Colors.blueGrey.shade200;

    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Text('$posicion',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14)),
    );
  }
}
