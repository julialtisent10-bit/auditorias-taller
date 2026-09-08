import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../plantillas/domain/entities/plantilla.dart';

/// Carga el cuestionario de seguridad.
///
/// A diferencia de `PlantillaRepository`, este NO tiene copia editable en
/// Firestore ni editor propio: es un módulo aparte y deliberadamente simple.
/// El cuestionario vive fijo en el asset; cambiarlo exige recompilar la
/// aplicación, igual que pasaba con el de postventa antes de tener editor.
class PlantillaSeguridadRepository {
  static const asset = 'assets/plantillas/plantilla_seguridad_v1.json';

  Plantilla? _cache;

  Future<Plantilla> cargar() async {
    final cache = _cache;
    if (cache != null) return cache;

    final texto = await rootBundle.loadString(asset);
    final plantilla = Plantilla.fromJson(json.decode(texto) as Map<String, dynamic>);

    final errores = plantilla.validar();
    if (errores.isNotEmpty) {
      // Fallar aquí y no más tarde: con los pesos mal, la puntuación de toda
      // revisión hecha con esta plantilla quedaría falseada en silencio.
      throw PlantillaSeguridadInvalida(errores);
    }

    _cache = plantilla;
    return plantilla;
  }
}

class PlantillaSeguridadInvalida implements Exception {
  const PlantillaSeguridadInvalida(this.errores);
  final List<String> errores;

  @override
  String toString() =>
      'Cuestionario de seguridad inválido:\n- ${errores.join('\n- ')}';
}
