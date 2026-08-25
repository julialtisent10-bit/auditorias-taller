import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/centro.dart';

class CentroRepository {
  CentroRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('centros');

  /// Con persistencia activada este stream sirve desde caché al instante y
  /// se refresca solo cuando llega la red.
  ///
  /// El orden se aplica en Dart y no con `orderBy`: combinar un `where` de
  /// igualdad con un `orderBy` sobre otro campo obliga a crear un índice
  /// compuesto en Firestore. Para media docena de centros no compensa.
  Stream<List<Centro>> observar({bool soloActivos = true}) {
    final q = soloActivos ? _col.where('activo', isEqualTo: true) : _col;
    return q.snapshots().map((s) =>
        s.docs.map((d) => Centro.fromJson({...d.data(), 'id': d.id})).toList()
          ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase())));
  }

  Future<Centro> crear({
    required String nombre,
    String codigo = '',
    String poblacion = '',
    String? plantillaPorDefecto,
  }) async {
    final centro = Centro(
      id: _uuid.v4(),
      nombre: nombre.trim(),
      codigo: codigo.trim().toUpperCase(),
      poblacion: poblacion.trim(),
      plantillaPorDefecto: plantillaPorDefecto,
    );
    await _col.doc(centro.id).set(centro.toJson());
    return centro;
  }

  Future<void> actualizarResponsables(
          String centroId, Map<String, String> responsables) =>
      _col.doc(centroId).set({'responsables': responsables}, SetOptions(merge: true));

  /// Deja el centro como si nunca se hubiera auditado. Se usa al borrar su
  /// última auditoría: si no, la ficha seguiría enseñando una puntuación de
  /// algo que ya no existe.
  Future<void> limpiarResumen(String centroId) => _col
      .doc(centroId)
      .set({'resumen': const ResumenCentro().toJson()}, SetOptions(merge: true));

  /// Se llama al cerrar una auditoría. Desplaza la última puntuación a
  /// "penúltima" para poder mostrar la tendencia sin releer el histórico.
  ///
  /// Deliberadamente SIN `runTransaction`: una transacción de Firestore exige
  /// red y falla estando offline, y esto se ejecuta al cerrar la auditoría
  /// dentro del taller. Con lectura de caché + `set(merge)` la operación se
  /// encola como cualquier otra escritura y se resuelve al recuperar señal.
  ///
  /// El riesgo asumido es una carrera si dos auditores cierran auditorías del
  /// mismo centro a la vez; el campo afectado es informativo (la tendencia) y
  /// el ranking se recalcula del histórico, que es la fuente de verdad.
  Future<void> registrarCierre(
    String centroId, {
    required String auditoriaId,
    required DateTime fecha,
    required double puntuacion,
  }) async {
    final ref = _col.doc(centroId);

    ResumenCentro previo;
    try {
      final snap = await ref.get();
      previo = ResumenCentro.fromJson(
          (snap.data()?['resumen'] as Map?)?.cast<String, dynamic>());
    } catch (_) {
      previo = const ResumenCentro(); // sin caché todavía
    }

    await ref.set({
      'resumen': ResumenCentro(
        ultimaAuditoriaId: auditoriaId,
        ultimaFecha: fecha,
        ultimaPuntuacion: puntuacion,
        penultimaPuntuacion: previo.ultimaPuntuacion,
      ).toJson(),
    }, SetOptions(merge: true));
  }
}
