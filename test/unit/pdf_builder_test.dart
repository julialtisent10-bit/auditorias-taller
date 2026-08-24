import 'dart:io';
import 'dart:typed_data';

import 'package:audit_app/features/auditoria/domain/entities/respuesta.dart';
import 'package:audit_app/features/auditoria/domain/entities/valor_respuesta.dart';
import 'package:audit_app/features/auditoria/domain/usecases/calcular_puntuacion.dart';
import 'package:audit_app/features/reporte/data/pdf/pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

/// En test no hay rootBundle: las fuentes se leen del disco directamente.
ByteData _cargar(String ruta) {
  final bytes = File(ruta).readAsBytesSync();
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

const pesos = <String, double>{
  'administracion': 0.20,
  'asesores': 0.30,
  'recambios': 0.20,
  'taller': 0.30,
};

Respuesta _r(String id, String area, int peso, ValorRespuesta v,
        {bool critica = false, String comentario = ''}) =>
    Respuesta(
      preguntaId: id,
      areaCodigo: area,
      textoPregunta: 'Pregunta $id del area $area',
      peso: peso,
      critica: critica,
      valor: v,
      comentario: comentario,
    );

DatosReporte _datos({String? logoSvg}) {
  final respuestas = [
    _r('a1', 'administracion', 3, ValorRespuesta.cumple),
    _r('a2', 'administracion', 1, ValorRespuesta.parcial,
        comentario: 'Falta el desglose de trabajos externos.'),
    _r('s1', 'asesores', 3, ValorRespuesta.noCumple,
        critica: true, comentario: 'No se documenta la inspeccion perimetral.'),
    _r('r1', 'recambios', 2, ValorRespuesta.cumple),
    _r('r2', 'recambios', 1, ValorRespuesta.noAplica),
    _r('t1', 'taller', 3, ValorRespuesta.cumple),
    _r('t2', 'taller', 1, ValorRespuesta.parcial, comentario: 'Pales en el pasillo.'),
  ];

  return DatosReporte(
    centroNombre: 'Centro de prueba',
    fecha: DateTime(2026, 8, 21),
    auditorNombre: 'Auditor de prueba',
    responsables: const {
      'administracion': 'Ana',
      'asesores': 'Bruno',
      'recambios': 'Carla',
      'taller': 'Dani',
      'gerente': 'Elena',
    },
    resultado:
        const CalcularPuntuacion()(respuestas: respuestas, pesosArea: pesos),
    respuestas: respuestas,
    logoSvg: logoSvg,
  );
}

void main() {
  const constructor = PdfBuilder();

  test('genera un PDF valido y no trivial', () async {
    final bytes = await constructor.construir(_datos());

    // Cabecera del formato: si esto falla, ni siquiera es un PDF.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(3000));
  });

  test('el logotipo SVG se incrusta sin romper el documento', () async {
    // Ejercita la ruta de pw.SvgImage, que no se cubre en ningun otro test.
    final svg = File('assets/branding/scaitt_logo.svg').readAsStringSync();
    final bytes = await constructor.construir(_datos(logoSvg: svg));

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('con las fuentes incrustadas se dibujan caracteres fuera de Latin-1',
      () async {
    // El caso real: el auditor escribe en el movil y el teclado mete un
    // apostrofo curvo y unos puntos suspensivos tipograficos. Con Helvetica
    // esos caracteres desaparecerian del informe sin ningun aviso.
    final respuestas = [
      _r('t1', 'taller', 3, ValorRespuesta.noCumple,
          critica: true,
          comentario: 'L’operari no duia EPI — cal revisar-ho…'),
    ];

    final datos = DatosReporte(
      centroNombre: 'Centro — prueba',
      fecha: DateTime(2026, 8, 21),
      auditorNombre: 'Auditor',
      responsables: const {},
      resultado:
          const CalcularPuntuacion()(respuestas: respuestas, pesosArea: pesos),
      respuestas: respuestas,
      fuentes: FuentesInforme(
        base: pw.Font.ttf(_cargar(FuentesInforme.rutaBase)),
        negrita: pw.Font.ttf(_cargar(FuentesInforme.rutaNegrita)),
        cursiva: pw.Font.ttf(_cargar(FuentesInforme.rutaCursiva)),
      ),
    );

    final bytes = await constructor.construir(datos);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Con fuente incrustada el documento pesa bastante mas que sin ella.
    expect(bytes.length, greaterThan(20000));
  });

  test('el grafico de arana soporta un area sin datos evaluables', () async {
    // Un area entera en N/A daba porcentaje 0 y antes podia degenerar el
    // poligono del radar. Debe seguir generando el informe igualmente.
    final respuestas = [
      _r('a1', 'administracion', 1, ValorRespuesta.noAplica),
      _r('t1', 'taller', 1, ValorRespuesta.cumple),
    ];
    final datos = DatosReporte(
      centroNombre: 'Centro con area vacia',
      fecha: DateTime(2026, 8, 21),
      auditorNombre: 'Auditor',
      responsables: const {},
      resultado:
          const CalcularPuntuacion()(respuestas: respuestas, pesosArea: pesos),
      respuestas: respuestas,
    );

    final bytes = await constructor.construir(datos);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
