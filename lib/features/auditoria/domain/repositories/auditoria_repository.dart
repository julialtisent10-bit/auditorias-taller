import 'dart:typed_data';

import '../entities/auditoria.dart';
import '../entities/evidencia.dart';
import '../entities/respuesta.dart';
import '../usecases/calcular_puntuacion.dart';

/// Contrato hacia la capa de datos. La presentación no sabe si detrás hay
/// Firestore, SQLite o un mock de test.
abstract class AuditoriaRepository {
  Future<Auditoria> crear({
    required String centroId,
    required String centroNombre,
    required String plantillaId,
    required int plantillaVersion,
    required String plantillaNombre,
    required DateTime fecha,
    required String auditorUid,
    required String auditorNombre,
    required Map<String, String> responsables,
  });

  Future<Auditoria?> obtener(String auditoriaId);

  /// Respuestas ya guardadas, para reanudar una auditoría a medias.
  Future<List<Respuesta>> respuestasDe(String auditoriaId);

  Stream<List<Auditoria>> historico({String? centroId, int limite = 50});

  /// Auditorías abiertas del auditor. Permite retomar una visita que quedó
  /// a medias porque se agotó la batería o se cerró la app en el taller.
  Stream<List<Auditoria>> enCurso({required String auditorUid, int limite = 20});

  Future<void> guardarRespuesta(String auditoriaId, Respuesta respuesta);

  Future<void> guardarResultados(String auditoriaId, ResultadoAuditoria resultado);

  /// Devuelve null si el auditor cerró la cámara sin disparar.
  Future<Evidencia?> capturarEvidencia({
    required String auditoriaId,
    required String preguntaId,
    required bool desdeCamara,
  });

  Future<void> eliminarEvidencia(
      String auditoriaId, String preguntaId, Evidencia evidencia);

  /// Borra una auditoría y todo lo que cuelga de ella: sus respuestas en la
  /// nube y sus fotos, firmas e informe en este dispositivo.
  Future<void> eliminar(String auditoriaId);

  /// Cierra la auditoría: fija el resultado, adjunta firmas, guarda el
  /// informe en el almacén local y lo encola para subir.
  Future<void> finalizar(
    String auditoriaId, {
    required ResultadoAuditoria resultado,
    required Firma firmaAuditor,
    required Firma firmaGerente,
    required Uint8List pdf,
  });
}
