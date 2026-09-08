import 'dart:typed_data';

import '../../../auditoria/domain/entities/evidencia.dart';
import '../../../auditoria/domain/entities/respuesta.dart';
import '../../../auditoria/domain/usecases/calcular_puntuacion.dart';
import '../entities/revision_seguridad.dart';

/// Contrato hacia la capa de datos, igual que `AuditoriaRepository` pero para
/// revisiones de seguridad. Se mantiene aparte del de auditorías para poder
/// cambiar uno sin arriesgar el otro: son colecciones y ciclos de vida
/// distintos, aunque el dominio se parezca.
abstract class RevisionSeguridadRepository {
  Future<RevisionSeguridad> crear({
    required String centroId,
    required String centroNombre,
    required String plantillaId,
    required int plantillaVersion,
    required String plantillaNombre,
    required DateTime fecha,
    required String evaluadorUid,
    required String evaluadorNombre,
  });

  Future<RevisionSeguridad?> obtener(String revisionId);

  /// Respuestas ya guardadas, para reanudar una revisión a medias.
  Future<List<Respuesta>> respuestasDe(String revisionId);

  Stream<List<RevisionSeguridad>> historico({String? centroId, int limite = 50});

  /// Revisiones abiertas del evaluador, para poder retomar una visita a medias.
  Stream<List<RevisionSeguridad>> enCurso({required String evaluadorUid, int limite = 20});

  Future<void> guardarRespuesta(String revisionId, Respuesta respuesta);

  Future<void> guardarResultados(String revisionId, ResultadoAuditoria resultado);

  /// Foto opcional para una pregunta. Nunca obligatoria, igual que en
  /// auditorías: hay cosas en un taller que no se pueden fotografiar.
  Future<Evidencia?> capturarEvidencia({
    required String revisionId,
    required String preguntaId,
    required bool desdeCamara,
  });

  Future<void> eliminarEvidencia(
      String revisionId, String preguntaId, Evidencia evidencia);

  /// Cierra la revisión: fija el resultado y guarda el informe en el
  /// almacén local.
  Future<void> finalizar(
    String revisionId, {
    required ResultadoAuditoria resultado,
    required Uint8List pdf,
  });

  /// Borra una revisión y todo lo que cuelga de ella: sus respuestas en la
  /// nube y su informe en este dispositivo.
  Future<void> eliminar(String revisionId);
}
