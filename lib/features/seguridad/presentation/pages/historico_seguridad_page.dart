import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../app/di/providers.dart';
import '../../../../shared/widgets/error_datos.dart';
import '../../domain/entities/revision_seguridad.dart';

/// Histórico de revisiones de seguridad, simplificado a propósito: sin
/// ranking ni niveles A-D, que son del cuestionario de postventa y no
/// significan lo mismo aquí. Solo cuántas preguntas salieron "Sí" y "No".
class HistoricoSeguridadPage extends ConsumerWidget {
  const HistoricoSeguridadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisiones = ref.watch(historicoSeguridadProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Revisiones de seguridad')),
      body: revisiones.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorDatos(error: e, queSeIntentaba: 'las revisiones'),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Todavía no hay ninguna revisión de seguridad.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: lista.length,
            itemBuilder: (_, i) => _Fila(revision: lista[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed('/seguridad/inicio'),
        icon: const Icon(Icons.add_task),
        label: const Text('Nueva revisión'),
      ),
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.revision});
  final RevisionSeguridad revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = revision.resultados?['areas'] as Map?;
    final seg = (area?['SEG'] as Map?);
    final nAplicables = (seg?['nAplicables'] as num?)?.toInt() ?? 0;
    final puntosObtenidos = (seg?['puntosObtenidos'] as num?)?.toDouble() ?? 0;
    // Con preguntas Sí/No de peso 1, cada punto obtenido es un "Sí": no hace
    // falta guardar un contador aparte para saber cuántos "No" hubo.
    final ok = puntosObtenidos.round();
    final noOk = nAplicables - ok;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.health_and_safety_outlined),
        title: Text(revision.centroNombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${_fecha(revision.fecha)} · $ok Sí · $noOk No',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (opcion) async {
            if (opcion == 'informe') await _abrirInforme(context, ref);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'informe', child: Text('Ver informe')),
          ],
        ),
      ),
    );
  }

  /// El informe solo se guarda en el dispositivo donde se cerró la revisión:
  /// el plan gratuito de Firebase no incluye Cloud Storage.
  Future<void> _abrirInforme(BuildContext context, WidgetRef ref) async {
    final almacen = ref.read(almacenProvider);
    final pdf = almacen.leer(RevisionSeguridad.clavePdf(revision.id));

    if (pdf == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'El informe no está en este dispositivo. Solo se guarda donde se cerró la revisión.'),
        ),
      );
      return;
    }

    await Printing.sharePdf(
      bytes: pdf,
      filename: 'Seguridad_${revision.centroNombre}_${_fecha(revision.fecha)}.pdf'
          .replaceAll('/', '-'),
    );
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
