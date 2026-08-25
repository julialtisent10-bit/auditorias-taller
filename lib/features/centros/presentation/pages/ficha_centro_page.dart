import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../shared/area_vista.dart';
import '../../../auditoria/domain/entities/auditoria.dart';
import '../../domain/entities/centro.dart';

/// Ficha de un centro: cómo ha evolucionado y en qué falla.
///
/// La pantalla principal solo enseñaba la última nota. Una auditoría suelta
/// no dice gran cosa; lo que sirve para dirigir es si sube o baja, y qué área
/// arrastra el resultado mes tras mes.
class FichaCentroPage extends ConsumerWidget {
  const FichaCentroPage({super.key, required this.centro});

  final Centro centro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(historicoDeCentroProvider(centro.id));
    final areas =
        AreaVista.listaDesde(ref.watch(plantillaProvider(null)).value?.areas ?? const []);

    return Scaffold(
      appBar: AppBar(title: Text(centro.nombre)),
      body: historico.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text('No se pudo cargar el histórico:\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (auditorias) {
          if (auditorias.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Este centro todavía no tiene ninguna auditoría cerrada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Evolucion(auditorias: auditorias),
              const SizedBox(height: 28),
              Text('Por áreas, última auditoría',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final area in areas)
                _BarraArea(
                  area: area,
                  actual: auditorias.first.porcentajeArea(area.codigo),
                  anterior: auditorias.length > 1
                      ? auditorias[1].porcentajeArea(area.codigo)
                      : null,
                ),
              const SizedBox(height: 28),
              Text('Auditorías', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final a in auditorias)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_note, size: 20),
                  title: Text(_fecha(a.fecha), style: const TextStyle(fontSize: 14)),
                  subtitle: Text('Auditor: ${a.auditorNombre}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: Text('${a.puntuacionGlobal.toStringAsFixed(1)} %',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

/// Evolución de la nota global, de la auditoría más antigua a la más nueva.
class _Evolucion extends StatelessWidget {
  const _Evolucion({required this.auditorias});

  final List<Auditoria> auditorias;

  @override
  Widget build(BuildContext context) {
    // Llegan de más reciente a más antigua; el gráfico se lee al revés.
    final serie = auditorias.reversed.toList();
    final ultima = auditorias.first.puntuacionGlobal;
    final variacion = auditorias.length > 1
        ? ultima - auditorias[1].puntuacionGlobal
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${ultima.toStringAsFixed(1)} %',
                style: const TextStyle(
                    fontSize: 38, fontWeight: FontWeight.bold, height: 1)),
            const SizedBox(width: 10),
            if (variacion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _Variacion(valor: variacion),
              ),
          ],
        ),
        Text(
          auditorias.length == 1
              ? 'Primera auditoría'
              : '${auditorias.length} auditorías registradas',
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 20),
        // Barras en lugar de una línea: con tres o cuatro puntos, una línea
        // sugiere una tendencia continua que estos datos no tienen.
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final a in serie)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${a.puntuacionGlobal.round()}',
                            style: const TextStyle(fontSize: 10)),
                        const SizedBox(height: 2),
                        Container(
                          height: (a.puntuacionGlobal / 100 * 70).clamp(2, 70),
                          decoration: BoxDecoration(
                            color: _color(a.puntuacionGlobal),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_mes(a.fecha),
                            style: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static Color _color(double p) {
    if (p >= 90) return Colors.green.shade600;
    if (p >= 80) return Colors.lightGreen.shade700;
    if (p >= 65) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  static String _mes(DateTime d) {
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${meses[d.month - 1]} ${d.year % 100}';
  }
}

class _Variacion extends StatelessWidget {
  const _Variacion({required this.valor});

  final double valor;

  @override
  Widget build(BuildContext context) {
    // Media décima de margen: variaciones mínimas no son una tendencia.
    if (valor.abs() < 0.5) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_flat, size: 18, color: Colors.grey),
          const SizedBox(width: 3),
          Text('sin cambios',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ],
      );
    }
    final sube = valor > 0;
    final color = sube ? Colors.green : Colors.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(sube ? Icons.trending_up : Icons.trending_down,
            size: 18, color: color),
        const SizedBox(width: 3),
        Text('${sube ? '+' : ''}${valor.toStringAsFixed(1)} pts',
            style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _BarraArea extends StatelessWidget {
  const _BarraArea({
    required this.area,
    required this.actual,
    required this.anterior,
  });

  final AreaVista area;
  final double actual;
  final double? anterior;

  @override
  Widget build(BuildContext context) {
    final delta = anterior == null ? null : actual - anterior!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(area.icono, color: area.color, size: 18),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: Text(area.nombreCorto,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: actual / 100,
                minHeight: 10,
                color: area.color,
                backgroundColor: area.color.withValues(alpha: 0.15),
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text('${actual.round()} %',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          SizedBox(
            width: 44,
            child: delta == null || delta.abs() < 0.5
                ? const SizedBox.shrink()
                : Text(
                    '${delta > 0 ? '+' : ''}${delta.round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        color: delta > 0 ? Colors.green : Colors.red),
                  ),
          ),
        ],
      ),
    );
  }
}
