import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../auditoria/domain/usecases/calcular_puntuacion.dart';
import '../../domain/entities/revision_seguridad.dart';
import '../informe_seguridad.dart';
import '../providers/revision_controller.dart';
import '../widgets/pregunta_seguridad_card.dart';

/// El checklist en sí: una lista plana de las 33 preguntas de seguridad.
///
/// No hace falta `TabBar` por áreas, a diferencia del cuestionario de
/// postventa: este solo tiene una.
class RevisionPage extends ConsumerStatefulWidget {
  const RevisionPage({super.key});

  @override
  ConsumerState<RevisionPage> createState() => _RevisionPageState();
}

class _RevisionPageState extends ConsumerState<RevisionPage> {
  bool _finalizando = false;

  Future<bool> _confirmarSalida(RevisionState state) async {
    if (state.resultado.completa) return true;

    final pendientes = state.preguntas.length -
        state.respuestas.values.where((r) => r.respondida).length;

    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la revisión'),
        content: Text(
          'Quedan $pendientes preguntas por responder.\n\nLo contestado se '
          'guarda y podrás continuar más tarde.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir aquí')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    return salir ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(revisionControllerProvider);
    final res = state.resultado;
    final area = res.areas['SEG'];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (yaSalio, _) async {
        if (yaSalio) return;
        if (await _confirmarSalida(state) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revisión de seguridad', style: TextStyle(fontSize: 16)),
              Text(state.centroNombre,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: state.guardando
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_done_outlined, size: 20),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            if (area != null) _Cabecera(resultado: area),
            const SizedBox(height: 12),
            for (final p in state.preguntas) PreguntaSeguridadCard(pregunta: p),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${(res.progresoGlobal * 100).round()} % completado',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${res.areas['SEG']?.nAplicables ?? 0} respondidas',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _previsualizar,
                  icon: const Icon(Icons.visibility),
                  label: const Text('Ver'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: state.puedeFinalizar && !_finalizando ? _finalizar : null,
                  icon: _finalizando
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('Finalizar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _previsualizar() async {
    final datos = await construirDatosReporteSeguridad(ref);
    if (datos == null) return;
    await ref.read(generarReporteProvider).previsualizar(datos);
  }

  Future<void> _finalizar() async {
    setState(() => _finalizando = true);
    try {
      final state = ref.read(revisionControllerProvider);
      final revision = ref.read(revisionSeguridadActualProvider);
      if (revision == null) return;

      final datos = await construirDatosReporteSeguridad(ref);
      if (datos == null) return;

      final pdf = await ref.read(generarReporteProvider).bytes(datos);

      await ref.read(revisionSeguridadRepositoryProvider).finalizar(
            revision.id,
            resultado: state.resultado,
            pdf: pdf,
          );

      await ref.read(generarReporteProvider).compartir(pdf, datos);

      ref.read(revisionSeguridadActualProvider.notifier).state =
          revision.copyWith(estado: EstadoRevision.finalizada, cerradaEn: DateTime.now());
      ref.read(sesionSeguridadAbiertaProvider.notifier).state = null;

      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo finalizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.resultado});
  final ResultadoArea resultado;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(
              resultado.evaluable ? '${resultado.porcentaje.toStringAsFixed(1)}%' : '—',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: const Color(0xFFD32F2F), fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                  '${resultado.nTotal - resultado.nSinResponder}/${resultado.nTotal} respondidas'),
            ),
          ],
        ),
      ),
    );
  }
}
