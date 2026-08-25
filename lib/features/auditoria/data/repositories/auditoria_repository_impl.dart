import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/almacen/almacen_binarios.dart';
import '../../domain/entities/auditoria.dart';
import '../../domain/entities/evidencia.dart';
import '../../domain/entities/respuesta.dart';
import '../../domain/repositories/auditoria_repository.dart';
import '../../domain/usecases/calcular_puntuacion.dart';
import '../datasources/evidencia_datasource.dart';

/// Implementación offline-first.
///
/// Reparto de responsabilidades:
///
///  - DOCUMENTOS (respuestas, resultados): se escriben directos a Firestore.
///    Con `persistenceEnabled` el SDK los guarda en IndexedDB y los reenvía
///    solo al recuperar red, incluso si la pestaña se cerró por el camino.
///    No hace falta duplicar esa lógica.
///  - BINARIOS (fotos, firmas, informe): se quedan en [AlmacenBinarios], en
///    este dispositivo y nada más. El plan gratuito de Firebase no incluye
///    Cloud Storage, así que no hay adónde subirlos. La copia duradera de la
///    evidencia es el PDF que el auditor descarga o comparte al cerrar.
///
/// Corolario práctico: un `await` sobre una escritura de Firestore estando
/// sin red se resuelve igualmente contra la caché local. Nunca hay que
/// bloquear la interfaz esperando confirmación del servidor.
class AuditoriaRepositoryImpl implements AuditoriaRepository {
  AuditoriaRepositoryImpl({
    required EvidenciaDataSource evidencias,
    required AlmacenBinarios almacen,
    FirebaseFirestore? firestore,
  })  : _evidencias = evidencias,
        _almacen = almacen,
        _db = firestore ?? FirebaseFirestore.instance;

  final EvidenciaDataSource _evidencias;
  final AlmacenBinarios _almacen;
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
    required String plantillaNombre,
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
      plantillaNombre: plantillaNombre,
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
    // Ordenar antes de limitar. Con `limit` a secas Firestore devuelve un
    // subconjunto arbitrario, y quien luego busque «la más reciente» entre
    // ellas puede no tenerla siquiera en el lote.
    //
    // Con centroId se ordena por documento en lugar de por fecha: combinar
    // un where de igualdad con un orderBy sobre otro campo exigiría declarar
    // un índice compuesto. El orden real lo pone el sort de más abajo, y el
    // límite alto deja margen de sobra para que quepan todas las del centro.
    final Query<Map<String, dynamic>> consulta = centroId != null
        ? _auditorias
            .where('centroId', isEqualTo: centroId)
            .orderBy(FieldPath.documentId)
            .limit(limite)
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
        .orderBy(FieldPath.documentId)
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
    // Los bytes ya quedan guardados en el almacén local por el datasource.
    // No hay nada que encolar: sin Cloud Storage no existe destino remoto.
    final evidencia = await _evidencias.capturar(desdeCamara: desdeCamara);
    // null = el auditor cerró la cámara sin disparar. No es un error.
    return evidencia;
  }

  @override
  Future<void> eliminarEvidencia(
      String auditoriaId, String preguntaId, Evidencia evidencia) async {
    await _evidencias.eliminar(evidencia);
  }

  @override
  Future<void> eliminar(String auditoriaId) async {
    final doc = _doc(auditoriaId);

    // Las respuestas primero: Firestore no borra en cascada y quedarían
    // huérfanas, invisibles y ocupando para siempre. De paso se aprovecha el
    // recorrido para saber qué fotos hay que barrer del almacén local.
    final claves = <String>[];
    while (true) {
      final tanda = await doc.collection('respuestas').limit(400).get();
      if (tanda.docs.isEmpty) break;

      final lote = _db.batch();
      for (final r in tanda.docs) {
        for (final e in (r.data()['evidencias'] as List? ?? const [])) {
          final id = (e as Map)['id'] as String?;
          if (id != null) claves.add(id);
        }
        lote.delete(r.reference);
      }
      await lote.commit();
    }

    await doc.delete();

    for (final id in claves) {
      await _almacen.borrarEvidencia(id);
    }
    await _almacen.borrar(AlmacenBinarios.claveInforme(auditoriaId));
    await _almacen.borrar(AlmacenBinarios.claveFirma(auditoriaId, 'auditor'));
    await _almacen.borrar(AlmacenBinarios.claveFirma(auditoriaId, 'gerente'));
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
    // se corta a partir de aquí, el PDF ya existe y se puede recuperar.
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
  }

  /// Borra del dispositivo las fotos de una auditoría ya cerrada.
  ///
  /// Existe porque el almacén local es finito y el navegador puede desalojarlo
  /// entero si crece demasiado. Una vez descargado el PDF —que lleva las
  /// imágenes incrustadas— las originales ya no hacen falta para nada.
  Future<void> liberarEvidencias(List<Respuesta> respuestas) async {
    for (final r in respuestas) {
      for (final e in r.evidencias) {
        await _almacen.borrarEvidencia(e.id);
      }
    }
  }
}
