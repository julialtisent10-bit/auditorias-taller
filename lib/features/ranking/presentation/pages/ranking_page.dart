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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Ranking de centros'),
        bottom: const TabBar(tabs: [
          Tab(text: 'Clasificación'),
          Tab(text: 'Por áreas'),
        ]),
      ),
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

          return TabBarView(
            children: [
              ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: ranking.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _Tarjeta(posicion: i + 1, auditoria: ranking[i], areas: vista),
              ),
              _Comparativa(ranking: ranking, areas: vista),
            ],
          );
        },
      ),
      ),
    );
  }
}

/// Matriz de áreas contra centros.
///
/// La clasificación dice quién va delante, pero no en qué. Aquí se ve de un
/// vistazo si un área flojea en todos los centros —problema de proceso, no de
/// centro— o si es uno solo el que arrastra el resultado.
class _Comparativa extends StatelessWidget {
  const _Comparativa({required this.ranking, required this.areas});

  final List<Auditoria> ranking;
  final List<AreaVista> areas;

  @override
  Widget build(BuildContext context) {
    if (areas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Cargando el cuestionario…',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final esquema = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        // Con siete áreas y varios centros la tabla no cabe de ancho: se
        // desplaza ella en lugar de encoger el texto hasta lo ilegible.
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 44,
          columns: [
            const DataColumn(label: Text('Área', style: TextStyle(fontSize: 12))),
            for (final a in ranking)
              DataColumn(
                label: SizedBox(
                  width: 74,
                  child: Text(a.centroNombre,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
          rows: [
            for (final area in areas)
              DataRow(cells: [
                DataCell(Row(children: [
                  Icon(area.icono, size: 15, color: area.color),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 110,
                    child: Text(area.nombreCorto,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                ])),
                for (final a in ranking)
                  DataCell(_Celda(valor: a.porcentajeArea(area.codigo))),
              ]),
            // Fila de totales, para poder comparar el área con la nota global.
            DataRow(
              color: WidgetStatePropertyAll(
                  esquema.surfaceContainerHighest.withValues(alpha: 0.5)),
              cells: [
                const DataCell(Text('GLOBAL',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                for (final a in ranking)
                  DataCell(_Celda(valor: a.puntuacionGlobal, destacada: true)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Celda extends StatelessWidget {
  const _Celda({required this.valor, this.destacada = false});

  final double valor;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final color = valor >= 90
        ? Colors.green.shade700
        : valor >= 80
            ? Colors.lightGreen.shade800
            : valor >= 65
                ? Colors.orange.shade800
                : Colors.red.shade700;

    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${valor.round()}',
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: destacada ? FontWeight.bold : FontWeight.w500,
        ),
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
