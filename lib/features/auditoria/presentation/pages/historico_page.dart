import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/almacen/almacen_binarios.dart';
import '../../../centros/data/repositories/centro_repository.dart';
import '../../domain/entities/auditoria.dart';
import '../../domain/repositories/auditoria_repository.dart';

/// Todas las auditorías, abiertas y cerradas.
///
/// Hasta ahora las cerradas solo asomaban en el ranking, que enseña una por
/// centro: no había forma de ver el histórico completo, recuperar un informe
/// ni borrar las pruebas hechas mientras se montaba la aplicación.
class HistoricoPage extends ConsumerWidget {
  const HistoricoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditorias = ref.watch(todasLasAuditoriasProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Auditorías')),
      body: auditorias.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text('No se pudo cargar el histórico:\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Todavía no hay ninguna auditoría.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: lista.length,
            itemBuilder: (_, i) => _Fila(auditoria: lista[i]),
          );
        },
      ),
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.auditoria});

  final Auditoria auditoria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esquema = Theme.of(context).colorScheme;
    final cerrada = auditoria.estado == EstadoAuditoria.finalizada;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          cerrada ? Icons.task_alt : Icons.pending_actions,
          color: cerrada ? esquema.primary : Colors.orangeAccent,
        ),
        title: Text(auditoria.centroNombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          cerrada
              ? '${_fecha(auditoria.fecha)} · '
                  '${auditoria.puntuacionGlobal.toStringAsFixed(1)} % · '
                  'Nivel ${auditoria.nivel}'
              : '${_fecha(auditoria.fecha)} · sin terminar',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (opcion) async {
            if (opcion == 'informe') {
              await _abrirInforme(context, ref);
            } else if (opcion == 'continuar') {
              final navegador = Navigator.of(context);
              await reanudarAuditoria(ref, auditoria);
              navegador.pushNamed('/auditoria');
            } else if (opcion == 'borrar') {
              await _borrar(context, ref);
            }
          },
          itemBuilder: (_) => [
            if (cerrada)
              const PopupMenuItem(value: 'informe', child: Text('Ver informe'))
            else
              const PopupMenuItem(
                  value: 'continuar', child: Text('Continuar auditoría')),
            const PopupMenuItem(value: 'borrar', child: Text('Borrar')),
          ],
        ),
      ),
    );
  }

  /// El informe se guardó en este dispositivo al cerrar la auditoría. Si se
  /// cerró desde otro móvil, o el navegador liberó espacio, ya no está: no
  /// hay copia en la nube porque el plan gratuito no incluye Storage.
  Future<void> _abrirInforme(BuildContext context, WidgetRef ref) async {
    final almacen = ref.read(almacenProvider);
    final pdf = almacen.leer(AlmacenBinarios.claveInforme(auditoria.id));

    if (pdf == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El informe no está en este dispositivo. Solo se guarda donde se '
            'cerró la auditoría.',
          ),
        ),
      );
      return;
    }

    await Printing.sharePdf(
      bytes: pdf,
      filename: 'Auditoria_${auditoria.centroNombre}_${_fecha(auditoria.fecha)}.pdf'
          .replaceAll('/', '-'),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    // Todo lo que dependa del widget se captura ANTES de los await. Al
    // borrar, el stream reemite, la lista se reconstruye sin esta fila y su
    // elemento queda descartado: usar `context` o `ref` después de ese punto
    // lanza, y el catch lo mostraba como «no se pudo borrar» cuando en
    // realidad sí se había borrado.
    final mensajero = ScaffoldMessenger.of(context);
    final auditorias = ref.read(auditoriaRepositoryProvider);
    final centros = ref.read(centroRepositoryProvider);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar la auditoría'),
        content: Text(
          'Se eliminarán sus respuestas, sus fotos y su informe de forma '
          'permanente.\n\n${auditoria.centroNombre} · ${_fecha(auditoria.fecha)}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await auditorias.eliminar(auditoria.id);
      await _recalcularCentro(auditorias, centros);
      mensajero.showSnackBar(const SnackBar(content: Text('Auditoría borrada.')));
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo borrar: $e')));
    }
  }

  /// La ficha del centro guarda la última puntuación para pintar la tendencia
  /// sin releer el histórico. Al borrar una auditoría ese dato puede quedar
  /// apuntando a algo que ya no existe, así que se rehace con lo que queda.
  Future<void> _recalcularCentro(
      AuditoriaRepository repo, CentroRepository centros) async {
    final cerradas =
        await repo.historico(centroId: auditoria.centroId, limite: 50).first;

    if (cerradas.isEmpty) {
      await centros.limpiarResumen(auditoria.centroId);
      return;
    }
    await centros.registrarCierre(
      auditoria.centroId,
      auditoriaId: cerradas.first.id,
      fecha: cerradas.first.fecha,
      puntuacion: cerradas.first.puntuacionGlobal,
    );
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
