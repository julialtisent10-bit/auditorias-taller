import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/almacen/almacen_binarios.dart';
import '../../../../core/sync/outbox_store.dart';
import '../../../../core/sync/sync_service.dart';
import '../../domain/entities/auditoria.dart';
import '../../domain/entities/evidencia.dart';
import '../../domain/entities/respuesta.dart';
import '../../domain/repositories/auditoria_repository.dart';
import '../../domain/usecases/calcular_puntuacion.dart';
import '../datasources/evidencia_datasource.dart';

/// Implementación offline-first.
///
/// Reparto de responsabilidades, que es lo que hace que esto funcione sin red:
///
///  - DOCUMENTOS (respuestas, resultados): se escriben directos a Firestore.
///    Con `persistenceEnabled` el SDK los guarda en disco y los reenvía solo
///    al recuperar red, incluso si la app se cerró por el camino. No hace
///    falta duplicar esa lógica.
///  - BINARIOS (fotos, PDF, firmas): Firebase Storage NO tiene cola offline.
///    Van a disco local y se encolan en [OutboxStore] para que [SyncService]
///    los suba cuando haya cobertura.
///
/// Corolario práctico: un `await` sobre una escritura de Firestore estando
/// sin red se resuelve igualmente contra la caché local. Nunca hay que
/// bloquear la interfaz esperando confirmación del servidor.
class AuditoriaRepositoryImpl implements AuditoriaRepository {
  AuditoriaRepositoryImpl({
    required EvidenciaDataSource evidencias,
    required OutboxStore outbox,
    required AlmacenBinarios almacen,
    required SyncService sync,
    FirebaseFirestore? firestore,
  })  : _evidencias = evidencias,
        _outbox = outbox,
        _almacen = almacen,
        _sync = sync,
        _db = firestore ?? FirebaseFirestore.instance;

  final EvidenciaDataSource _evidencias;
  final OutboxStore _outbox;
  final AlmacenBinarios _almacen;
  final SyncService _sync;
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _auditorias =>
      _db.collection('auditorias');

  DocumentReference<Map<String, dynamic>> _doc(String id) => _auditorias.doc(id);

  // ------------------------------------------------------------- ciclo de vida

  @override
  Future<Auditoria> crear({
    required String centroId,
    required String centroNombre,
    required String plantillaId,
    required int plantillaVersion,
    required DateTime fecha,
    required String auditorUid,
    required String auditorNombre,
    required Map<String, String> responsables,
  }) async {
    // El id se genera en el cliente, no en el servidor: así la auditoría
    // existe y es navegable aunque se cree sin cobertura.
    final auditoria = Auditoria(
      id: _uuid.v4(),
      centroId: centroId,
      centroNombre: centroNombre,
      plantillaId: plantillaId,
      plantillaVersion: plantillaVersion,
      fecha: fecha,
      auditorUid: auditorUid,
      auditorNombre: auditorNombre,
      estado: EstadoAuditoria.enCurso,
      responsables: responsables,
      creadaEn: DateTime.now(),
    );

    await _doc(auditoria.id).set(auditoria.toJson());
    return auditoria;
  }

  @override
  Future<Auditoria?> obtener(String auditoriaId) async {
    final snap = await _doc(auditoriaId).get();
    final datos = snap.data();
    if (datos == null) return null;
    return Auditoria.fromJson({...datos, 'id': snap.id});
  }

  @override
  Future<List<Respuesta>> respuestasDe(String auditoriaId) async {
    final snap = await _doc(auditoriaId).collection('respuestas').get();
    return snap.docs.map((d) => Respuesta.fromJson(d.data())).toList();
  }

  /// Auditorías cerradas, de la más reciente a la más antigua.
  ///
  /// El filtro por estado y la ordenación se hacen en Dart, no en la consulta.
  /// Combinar un `where` de igualdad con un `orderBy` sobre otro campo obliga
  /// a declarar un índice compuesto en Firestore; si falta, la consulta falla
  /// en producción con un error que solo se ve cuando ya está desplegado. Para
  /// el volumen de este caso (unos cuantos centros, una auditoría al mes) el
  /// filtrado en cliente es gratis y no hay índices que mantener.
  @override
  Stream<List<Auditoria>> historico({String? centroId, int limite = 50}) {
    final Query<Map<String, dynamic>> consulta = centroId != null
        ? _auditorias.where('centroId', isEqualTo: centroId).limit(limite)
        : _auditorias.orderBy('fecha', descending: true).limit(limite);

    return consulta.snapshots().map((s) {
      final auditorias = s.docs
          .map((d) => Auditoria.fromJson({...d.data(), 'id': d.id}))
          .where((a) => a.estado == EstadoAuditoria.finalizada)
          .toList();
      auditorias.sort((x, y) => y.fecha.compareTo(x.fecha));
      return auditorias;
    });
  }

  @override
  Stream<List<Auditoria>> enCurso({required String auditorUid, int limite = 20}) {
    return _auditorias
        .where('auditorUid', isEqualTo: auditorUid)
        .limit(limite)
        .snapshots()
        .map((s) {
      final abiertas = s.docs
          .map((d) => Auditoria.fromJson({...d.data(), 'id': d.id}))
          .where((a) => a.estado != EstadoAuditoria.finalizada)
          .toList();
      abiertas.sort((x, y) => y.fecha.compareTo(x.fecha));
      return abiertas;
    });
  }

  // ------------------------------------------------------------------ escritura

  @override
  Future<void> guardarRespuesta(String auditoriaId, Respuesta respuesta) async {
    await _doc(auditoriaId)
        .collection('respuestas')
        .doc(respuesta.preguntaId)
        .set(respuesta.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> guardarResultados(
      String auditoriaId, ResultadoAuditoria resultado) async {
    await _doc(auditoriaId).set({
      'resultados': resultado.toJson(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ----------------------------------------------------------------- evidencias

  @override
  Future<Evidencia?> capturarEvidencia({
    required String auditoriaId,
    required String preguntaId,
    required bool desdeCamara,
  }) async {
    final evidencia = await _evidencias.capturar(desdeCamara: desdeCamara);
    // null = el auditor cerró la cámara sin disparar. No es un error.
    if (evidencia == null) return null;

    await _outbox.encolar(TareaOutbox(
      // El id de la tarea es el de la evidencia: así SyncService sabe qué
      // entrada del array actualizar cuando termine la subida.
      id: evidencia.id,
      tipo: TipoTarea.evidencia,
      auditoriaId: auditoriaId,
      referencia: preguntaId,
      claveBinario: AlmacenBinarios.claveEvidencia(evidencia.id),
      remotePath:
          EvidenciaDataSource.rutaStorage(auditoriaId, preguntaId, evidencia.id),
    ));

    // Intento oportunista: si hay cobertura sube ya; si no, queda en cola.
    unawaited(_sync.drenar());
    return evidencia;
  }

  @override
  Future<void> eliminarEvidencia(
      String auditoriaId, String preguntaId, Evidencia evidencia) async {
    await _outbox.completar(evidencia.id); // cancela la subida si sigue en cola
    await _evidencias.eliminar(evidencia);
  }

  // ------------------------------------------------------------------- cierre

  @override
  Future<void> finalizar(
    String auditoriaId, {
    required ResultadoAuditoria resultado,
    required Firma firmaAuditor,
    required Firma firmaGerente,
    required Uint8List pdf,
  }) async {
    final ahora = DateTime.now();

    // El informe se guarda en local ANTES de tocar Firestore: si el proceso
    // se corta a partir de aquí, el PDF ya existe y la cola lo subirá.
    final clavePdf = AlmacenBinarios.claveInforme(auditoriaId);
    await _almacen.guardar(clavePdf, pdf);

    await _doc(auditoriaId).set({
      'estado': EstadoAuditoria.finalizada.codigo,
      'resultados': resultado.toJson(),
      'firmas': {
        'auditor': firmaAuditor.toJson(),
        'gerente': firmaGerente.toJson(),
      },
      'pdf': {'claveLocal': clavePdf},
      'cerradaEn': ahora.toIso8601String(),
    }, SetOptions(merge: true));

    await _outbox.encolar(TareaOutbox(
      id: 'pdf_$auditoriaId',
      tipo: TipoTarea.informePdf,
      auditoriaId: auditoriaId,
      claveBinario: clavePdf,
      remotePath: 'auditorias/$auditoriaId/informe.pdf',
    ));

    for (final entrada in {'auditor': firmaAuditor, 'gerente': firmaGerente}.entries) {
      final clave = entrada.value.claveLocal;
      if (clave == null) continue;
      await _outbox.encolar(TareaOutbox(
        id: 'firma_${entrada.key}_$auditoriaId',
        tipo: TipoTarea.firma,
        auditoriaId: auditoriaId,
        referencia: entrada.key,
        claveBinario: clave,
        remotePath: 'auditorias/$auditoriaId/firma_${entrada.key}.png',
      ));
    }

    unawaited(_sync.drenar());
  }
}
