import 'dart:convert';
import 'dart:io';

import 'package:audit_app/features/plantillas/domain/entities/plantilla.dart';
import 'package:flutter_test/flutter_test.dart';

/// En test no hay rootBundle: el asset se lee directamente del disco, igual
/// que en `pdf_builder_test.dart`.
Plantilla _cargar() {
  final texto = File('assets/plantillas/plantilla_seguridad_v1.json').readAsStringSync();
  return Plantilla.fromJson(json.decode(texto) as Map<String, dynamic>);
}

void main() {
  test('el cuestionario de seguridad carga con sus 33 preguntas en una sola área', () {
    final plantilla = _cargar();

    expect(plantilla.totalPreguntas, 33);
    expect(plantilla.areas, hasLength(1));
    expect(plantilla.areas.single.codigo, 'SEG');
    expect(plantilla.validar(), isEmpty);
  });

  test('todas las preguntas son Sí/No: sin parcial, sin N/A y sin críticas', () {
    final plantilla = _cargar();

    for (final p in plantilla.preguntas) {
      expect(p.permiteParcial, isFalse, reason: p.id);
      expect(p.permiteNA, isFalse, reason: p.id);
      expect(p.critica, isFalse, reason: p.id);
      expect(p.fotoObligatoriaSi, isEmpty, reason: p.id);
    }
  });

  test('con pesos automáticos, la única área concentra todo el peso', () {
    final plantilla = _cargar();

    expect(plantilla.pesosAutomaticos, isTrue);
    expect(plantilla.pesosEfectivos, {'SEG': 1.0});
  });

  test('el JSON hace ida y vuelta sin perder preguntas', () {
    final original = _cargar();
    final reconstruida = Plantilla.fromJson(
      json.decode(json.encode({
        'id': original.id,
        'nombre': original.nombre,
        'version': original.version,
        'pesosArea': original.pesosArea,
        'pesosAutomaticos': original.pesosAutomaticos,
        'areas': [for (final a in original.areas) a.toJson()],
        'preguntas': [for (final p in original.preguntas) p.toJson()],
      })) as Map<String, dynamic>,
    );

    expect(reconstruida.totalPreguntas, original.totalPreguntas);
    expect(reconstruida.validar(), isEmpty);
    expect(
      reconstruida.preguntas.map((p) => p.texto).toList(),
      original.preguntas.map((p) => p.texto).toList(),
    );
  });
}
