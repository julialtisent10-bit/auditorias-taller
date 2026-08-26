import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../centros/data/repositories/centro_repository.dart';
import '../domain/entities/auditoria.dart';
import '../domain/repositories/auditoria_repository.dart';

/// Pide confirmación y borra la auditoría.
///
/// Vive aparte porque se llama desde dos sitios —el histórico y el aviso de
/// la pantalla principal— y duplicarlo habría significado arreglar dos veces
/// cualquier fallo del borrado, que no es una operación trivial: hay que
/// barrer las respuestas, purgar las fotos del dispositivo y rehacer el
/// resumen del centro.
///
/// Devuelve true si se llegó a borrar.
Future<bool> confirmarYBorrarAuditoria(
  BuildContext context,
  WidgetRef ref,
  Auditoria auditoria,
) async {
  final cerrada = auditoria.estado == EstadoAuditoria.finalizada;

  // Todo lo que dependa del widget se captura ANTES de los await: al borrar,
  // el stream reemite y la fila que disparó esto desaparece de la lista, con
  // lo que su contexto y su ref dejan de servir.
  final mensajero = ScaffoldMessenger.of(context);
  final auditorias = ref.read(auditoriaRepositoryProvider);
  final centros = ref.read(centroRepositoryProvider);

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(cerrada ? 'Borrar la auditoría' : 'Descartar la auditoría'),
      content: Text(
        cerrada
            ? 'Se eliminarán sus respuestas, sus fotos y su informe de forma '
                'permanente.\n\n${auditoria.centroNombre} · '
                '${_fecha(auditoria.fecha)}'
            : 'Se perderá lo respondido hasta ahora y las fotos que hayas '
                'hecho.\n\n${auditoria.centroNombre} · '
                '${_fecha(auditoria.fecha)}',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(cerrada ? 'Borrar' : 'Descartar'),
        ),
      ],
    ),
  );
  if (confirmado != true) return false;

  try {
    await auditorias.eliminar(auditoria.id);
    if (cerrada) {
      await _rehacerResumenCentro(auditorias, centros, auditoria.centroId);
    }
    mensajero.showSnackBar(SnackBar(
        content: Text(cerrada ? 'Auditoría borrada.' : 'Auditoría descartada.')));
    return true;
  } catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text('No se pudo borrar: $e')));
    return false;
  }
}

/// La ficha del centro guarda la última puntuación para pintar la tendencia
/// sin releer el histórico. Al borrar una auditoría cerrada ese dato puede
/// quedar apuntando a algo que ya no existe, así que se rehace con lo que
/// queda. Con una auditoría en curso no hace falta: nunca llegó al resumen.
Future<void> _rehacerResumenCentro(
  AuditoriaRepository repo,
  CentroRepository centros,
  String centroId,
) async {
  final cerradas = await repo.historico(centroId: centroId, limite: 50).first;

  if (cerradas.isEmpty) {
    await centros.limpiarResumen(centroId);
    return;
  }
  await centros.registrarCierre(
    centroId,
    auditoriaId: cerradas.first.id,
    fecha: cerradas.first.fecha,
    puntuacion: cerradas.first.puntuacionGlobal,
  );
}

String _fecha(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}
