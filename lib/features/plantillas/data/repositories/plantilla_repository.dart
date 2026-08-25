import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../auditoria/domain/entities/pregunta.dart';
import '../../domain/entities/plantilla.dart';

/// Carga el cuestionario.
///
/// Estrategia: la plantilla empaquetada en assets es la red de seguridad.
/// Si el centro publica una versión más nueva en Firestore se usa esa, pero
/// si no hay red ni caché la app arranca igualmente con la del asset. Una
/// auditoría no puede quedar bloqueada porque no cargue el cuestionario.
class PlantillaRepository {
  PlantillaRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const assetPorDefecto = 'assets/plantillas/plantilla_taller_vi_v1.json';

  Plantilla? _cache;

  Future<Plantilla> cargar({String? plantillaId}) async {
    if (_cache != null && (plantillaId == null || _cache!.id == plantillaId)) {
      return _cache!;
    }

    final remota = await _intentarRemota(plantillaId);
    final plantilla = remota ?? await _desdeAsset();

    final errores = plantilla.validar();
    if (errores.isNotEmpty) {
      // Fallar aquí y no más tarde: con los pesos mal, todas las
      // puntuaciones del histórico quedarían falseadas en silencio.
      throw PlantillaInvalida(plantilla.id, errores);
    }

    _cache = plantilla;
    return plantilla;
  }

  Future<Plantilla?> _intentarRemota(String? plantillaId) async {
    try {
      final coleccion = _db.collection('plantillas');

      String? id = plantillaId;
      Map<String, dynamic>? datos;

      if (id != null) {
        final doc = await coleccion.doc(id).get();
        datos = doc.data();
      } else {
        // Sin id concreto: la publicada de mayor versión. Es un `where` de
        // igualdad sobre un solo campo, así que no necesita índice compuesto;
        // la versión se elige en Dart por el mismo motivo.
        final publicadas =
            await coleccion.where('estado', isEqualTo: 'publicada').get();
        if (publicadas.docs.isEmpty) return null;

        final docs = publicadas.docs.toList()
          ..sort((a, b) => ((b.data()['version'] as num?) ?? 0)
              .compareTo((a.data()['version'] as num?) ?? 0));
        id = docs.first.id;
        datos = docs.first.data();
      }

      if (datos == null) return null;

      // Las preguntas viven en una subcolección para no chocar con el
      // límite de 1 MiB por documento cuando la plantilla crece.
      final preguntas = await coleccion
          .doc(id)
          .collection('preguntas')
          .where('activa', isEqualTo: true)
          .get();

      if (preguntas.docs.isEmpty) return null;

      return Plantilla.fromJson({
        ...datos,
        'id': id,
        'preguntas': preguntas.docs.map((d) => {...d.data(), 'id': d.id}).toList(),
      });
    } catch (_) {
      // Sin red, sin caché o plantilla mal formada: caemos al asset.
      return null;
    }
  }

  Future<Plantilla> _desdeAsset() async {
    final texto = await rootBundle.loadString(assetPorDefecto);
    return Plantilla.fromJson(json.decode(texto) as Map<String, dynamic>);
  }

  /// Sube el asset a Firestore. Se usa una sola vez al montar el proyecto.
  Future<void> sembrarEnFirestore() async {
    final plantilla = await _desdeAsset();
    final doc = _db.collection('plantillas').doc(plantilla.id);

    await doc.set({
      'nombre': plantilla.nombre,
      'version': plantilla.version,
      'estado': 'publicada',
      'pesosArea': plantilla.pesosArea,
      'areas': [
        for (final a in plantilla.areas)
          {'codigo': a.codigo, 'nombre': a.nombre, 'orden': a.orden, 'color': a.colorHex},
      ],
    });

    // Lotes de 500: es el máximo por WriteBatch en Firestore.
    for (var i = 0; i < plantilla.preguntas.length; i += 400) {
      final lote = _db.batch();
      for (final p in plantilla.preguntas.skip(i).take(400)) {
        lote.set(doc.collection('preguntas').doc(p.id), {
          'areaCodigo': p.areaCodigo,
          'bloque': p.bloque,
          'orden': p.orden,
          'texto': p.texto,
          'ayuda': p.ayuda,
          'peso': p.peso,
          'critica': p.critica,
          'permiteNA': p.permiteNA,
          'fotoObligatoriaSi': p.fotoObligatoriaSi.map((v) => v.codigo).toList(),
          'activa': true,
        });
      }
      await lote.commit();
    }
    _cache = null;
  }

  // ------------------------------------------------------------------ edicion

  /// true si el cuestionario ya vive en Firestore y por tanto es editable.
  ///
  /// Mientras solo exista el asset empaquetado, cualquier cambio exigiría
  /// recompilar la aplicación; por eso el editor obliga a sembrarlo primero.
  Future<bool> esEditable(String plantillaId) async {
    try {
      final doc = await _db.collection('plantillas').doc(plantillaId).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> guardarPregunta(String plantillaId, Pregunta pregunta) async {
    await _db
        .collection('plantillas')
        .doc(plantillaId)
        .collection('preguntas')
        .doc(pregunta.id)
        .set(pregunta.toJson(), SetOptions(merge: true));
    _cache = null;
  }

  /// Marca la pregunta como inactiva en lugar de borrarla.
  ///
  /// Un borrado real dejaría huérfanas las respuestas del histórico que la
  /// referencian. Desactivarla la saca de las auditorías nuevas y conserva
  /// la trazabilidad de las antiguas.
  Future<void> desactivarPregunta(String plantillaId, String preguntaId) async {
    await _db
        .collection('plantillas')
        .doc(plantillaId)
        .collection('preguntas')
        .doc(preguntaId)
        .set({'activa': false}, SetOptions(merge: true));
    _cache = null;
  }

  Future<void> guardarPesosArea(
      String plantillaId, Map<String, double> pesos) async {
    final suma = pesos.values.fold<double>(0, (s, v) => s + v);
    if ((suma - 1.0).abs() >= 0.001) {
      throw ArgumentError('Los pesos de área deben sumar 1.0, suman $suma');
    }
    await _db
        .collection('plantillas')
        .doc(plantillaId)
        .set({'pesosArea': pesos}, SetOptions(merge: true));
    _cache = null;
  }

  /// Fuerza que la próxima carga vaya a Firestore en vez de servir la copia
  /// en memoria. Se llama tras cualquier edición.
  void invalidarCache() => _cache = null;
}

class PlantillaInvalida implements Exception {
  const PlantillaInvalida(this.plantillaId, this.errores);
  final String plantillaId;
  final List<String> errores;

  @override
  String toString() => 'Plantilla $plantillaId inválida:\n- ${errores.join('\n- ')}';
}
