import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../shared/widgets/aviso_almacenamiento.dart';
import '../../domain/entities/centro.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centros = ref.watch(centrosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditorías de taller'),
        actions: [
          const AvisoAlmacenamiento(),
          IconButton(
            tooltip: 'Ranking',
            icon: const Icon(Icons.leaderboard),
            onPressed: () => Navigator.of(context).pushNamed('/ranking'),
          ),
        ],
      ),
      body: centros.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error cargando centros:\n$e')),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay centros dados de alta.\n'
                  'Pulsa "Nueva auditoría" para crear el primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              const _AvisoEnCurso(),
              for (final centro in lista) _TarjetaCentro(centro: centro),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed('/auditoria/inicio'),
        icon: const Icon(Icons.add_task),
        label: const Text('Nueva auditoría'),
      ),
    );
  }
}

/// Auditorías abiertas. Si la app se cerró a media visita, esta tarjeta es
/// la única forma de volver a ella sin empezar de cero.
class _AvisoEnCurso extends ConsumerWidget {
  const _AvisoEnCurso();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abiertas = ref.watch(enCursoProvider).value ?? const [];
    if (abiertas.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final a in abiertas)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.pending_actions),
              title: Text('Auditoría sin terminar · ${a.centroNombre}'),
              subtitle: Text('Iniciada el ${_fecha(a.fecha)}',
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () async {
                final navegador = Navigator.of(context);
                await reanudarAuditoria(ref, a);
                navegador.pushNamed('/auditoria');
              },
            ),
          ),
      ],
    );
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _TarjetaCentro extends StatelessWidget {
  const _TarjetaCentro({required this.centro});
  final Centro centro;

  @override
  Widget build(BuildContext context) {
    final puntuacion = centro.resumen.ultimaPuntuacion;
    final tendencia = centro.resumen.tendencia;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(centro.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          puntuacion == null
              ? 'Sin auditorías'
              : 'Última auditoría: ${_fecha(centro.resumen.ultimaFecha)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: puntuacion == null
            ? const Icon(Icons.remove, color: Colors.grey)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tendencia != null) _Tendencia(valor: tendencia),
                  const SizedBox(width: 8),
                  Text('${puntuacion.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }

  static String _fecha(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _Tendencia extends StatelessWidget {
  const _Tendencia({required this.valor});
  final double valor;

  @override
  Widget build(BuildContext context) {
    // Media décima de margen: variaciones mínimas no son una tendencia.
    if (valor.abs() < 0.5) {
      return const Icon(Icons.trending_flat, size: 18, color: Colors.grey);
    }
    final sube = valor > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(sube ? Icons.trending_up : Icons.trending_down,
            size: 18, color: sube ? Colors.green : Colors.red),
        Text('${sube ? '+' : ''}${valor.toStringAsFixed(1)}',
            style: TextStyle(
                fontSize: 11, color: sube ? Colors.green : Colors.red)),
      ],
    );
  }
}
