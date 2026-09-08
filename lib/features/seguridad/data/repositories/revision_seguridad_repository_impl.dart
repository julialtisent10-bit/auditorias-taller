import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/almacen/almacen_binarios.dart';
import '../../../auditoria/data/datasources/evidencia_datasource.dart';
import '../../../auditoria/domain/entities/evidencia.dart';
import '../../../auditoria/domain/entities/respuesta.dart';
import '../../../auditoria/domain/usecases/calcular_puntuacion.dart';
import '../../domain/entities/revision_seguridad.dart';
import '../../domain/repositories/revision_seguridad_repository.dart';

/// Implementación offline-first sobre la colección `revisionesSeguridad`.
///
/// Deliberadamente NO usa la colección `auditorias`: es un módulo aparte
/// para no arriesgar el histórico ni el ranking de postventa, que están
/// afinados para su propio cuestionario y sus propios umbrales.
///
/// Igual que en `AuditoriaRepositoryImpl`, el documento y las respuestas van
/// a Firestore (con persistencia offline), y el PDF se queda en
/// [AlmacenBinarios], en este dispositivo: el plan gratuito de Firebase no
/// incluye Cloud Storage.
class RevisionSeguridadRepositoryImpl implements RevisionSeguridadRepository {
  RevisionSeguridadRepositoryImpl({
    required AlmacenBinarios almacen,
    required EvidenciaDataSource evidencias,
    FirebaseFirestore? firestore,
  })  : _almacen = almacen,
        _evidencias = evidencias,
        _db = firestore ?? FirebaseFirestore.instance;

  final AlmacenBinarios _almacen;
  final EvidenciaDataSource _evidencias;
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _revisiones =>
      _db.collection('revisionesSeguridad');

  DocumentReference<Map<String, dynamic>> _doc(String id) => _revisiones.doc(id);

  @override
  Future<RevisionSeguridad> crear({
    required String centroId,
    required String centroNombre,
    required String plantillaId,
    required int plantillaVersion,
    required String plantillaNombre,
    required DateTime fecha,
    required String evaluadorUid,
    required String evaluadorNombre,
  }) async {
    final revision = RevisionSeguridad(
      id: _uuid.v4(),
      centroId: centroId,
      centroNombre: centroNombre,
      plantillaId: plantillaId,
      plantillaVersion: plantillaVersion,
      plantillaNombre: plantillaNombre,
      fecha: fecha,
      evaluadorUid: evaluadorUid,
      evaluadorNombre: evaluadorNombre,
      estado: EstadoRevision.enCurso,
      creadaEn: DateTime.now(),
    );

    await _doc(revision.id).set(revision.toJson());
    return revision;
  }

  @override
  Future<RevisionSeguridad?> obtener(String revisionId) async {
    final snap = await _doc(revisionId).get();
    final datos = snap.data();
    if (datos == null) return null;
    return RevisionSeguridad.fromJson({...datos, 'id': snap.id});
  }

  @override
  Future<List<Respuesta>> respuestasDe(String revisionId) async {
    final snap = await _doc(revisionId).collection('respuestas').get();
    return snap.docs.map((d) => Respuesta.fromJson(d.data())).toList();
  }

  @override
  Stream<List<RevisionSeguridad>> historico({String? centroId, int limite = 50}) {
    // Mismo criterio que en auditorías: filtro y orden en Dart para no
    // depender de un índice compuesto por un volumen tan pequeño de datos.
    final Query<Map<String, dynamic>> consulta = centroId != null
        ? _revisiones
            .where('centroId', isEqualTo: centroId)
            .orderBy(FieldPath.documentId)
            .limit(limite)
        : _revisiones.orderBy('fecha', descending: true).limit(limite);

    return consulta.snapshots().map((s) {
      final revisiones = s.docs
          .map((d) => RevisionSeguridad.fromJson({...d.data(), 'id': d.id}))
          .where((r) => r.estado == EstadoRevision.finalizada)
          .toList();
      revisiones.sort((x, y) => y.fecha.compareTo(x.fecha));
      return revisiones;
    });
  }

  @override
  Stream<List<RevisionSeguridad>> enCurso({required String evaluadorUid, int limite = 20}) {
    return _revisiones
        .where('evaluadorUid', isEqualTo: evaluadorUid)
        .orderBy(FieldPath.documentId)
        .limit(limite)
        .snapshots()
        .map((s) {
      final abiertas = s.docs
          .map((d) => RevisionSeguridad.fromJson({...d.data(), 'id': d.id}))
          .where((r) => r.estado != EstadoRevision.finalizada)
          .toList();
      abiertas.sort((x, y) => y.fecha.compareTo(x.fecha));
      return abiertas;
    });
  }

  @override
  Future<void> guardarRespuesta(String revisionId, Respuesta respuesta) async {
    await _doc(revisionId)
        .collection('respuestas')
        .doc(respuesta.preguntaId)
        .set(respuesta.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> guardarResultados(String revisionId, ResultadoAuditoria resultado) async {
    await _doc(revisionId).set({
      'resultados': resultado.toJson(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> finalizar(
    String revisionId, {
    required ResultadoAuditoria resultado,
    required Uint8List pdf,
  }) async {
    final clavePdf = RevisionSeguridad.clavePdf(revisionId);
    // El informe se guarda en local ANTES de tocar Firestore: si el proceso
    // se corta a partir de aquí, el PDF ya existe y se puede recuperar.
    await _almacen.guardar(clavePdf, pdf);

    await _doc(revisionId).set({
      'estado': EstadoRevision.finalizada.codigo,
      'resultados': resultado.toJson(),
      'pdf': {'claveLocal': clavePdf},
      'cerradaEn': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  // ----------------------------------------------------------------- evidencias

  @override
  Future<Evidencia?> capturarEvidencia({
    required String revisionId,
    required String preguntaId,
    required bool desdeCamara,
  }) async {
    // null = el evaluador cerró la cámara sin disparar. No es un error.
    return _evidencias.capturar(desdeCamara: desdeCamara);
  }

  @override
  Future<void> eliminarEvidencia(
      String revisionId, String preguntaId, Evidencia evidencia) async {
    await _evidencias.eliminar(evidencia);
  }

  @override
  Future<void> eliminar(String revisionId) async {
    final doc = _doc(revisionId);

    while (true) {
      final tanda = await doc.collection('respuestas').limit(400).get();
      if (tanda.docs.isEmpty) break;
      final lote = _db.batch();
      for (final r in tanda.docs) {
        lote.delete(r.reference);
      }
      await lote.commit();
    }

    await doc.delete();
    await _almacen.borrar(RevisionSeguridad.clavePdf(revisionId));
  }
}
