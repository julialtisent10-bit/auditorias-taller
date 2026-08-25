import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../auditoria/domain/entities/respuesta.dart';
import '../../../auditoria/domain/entities/valor_respuesta.dart';
import '../../../auditoria/domain/usecases/calcular_puntuacion.dart';
import 'radar_chart.dart';

class AreaInfo {
  const AreaInfo(this.codigo, this.nombre, this.color);
  final String codigo;
  final String nombre;
  final PdfColor color;
}

/// Tipografía incrustada en el informe.
///
/// No es un capricho estético. Las fuentes internas del formato PDF
/// (Helvetica y compañía) usan codificación WinAnsi y descartan en silencio
/// cualquier carácter fuera de Latin-1. Los teclados de móvil producen
/// apóstrofos curvos y guiones largos constantemente, así que un comentario
/// del auditor perdería caracteres sin avisar. Noto Sans cubre Unicode.
class FuentesInforme {
  const FuentesInforme({required this.base, required this.negrita, required this.cursiva});

  final pw.Font base;
  final pw.Font negrita;
  final pw.Font cursiva;

  static const rutaBase = 'assets/fonts/NotoSans-Regular.ttf';
  static const rutaNegrita = 'assets/fonts/NotoSans-Bold.ttf';
  static const rutaCursiva = 'assets/fonts/NotoSans-Italic.ttf';

  pw.ThemeData get tema =>
      pw.ThemeData.withFont(base: base, bold: negrita, italic: cursiva);
}

class DatosReporte {
  const DatosReporte({
    required this.centroNombre,
    required this.fecha,
    required this.auditorNombre,
    required this.responsables,
    required this.resultado,
    required this.respuestas,
    required this.areas,
    this.imagenes = const {},
    this.logoSvg,
    this.fuentes,
  });

  final String centroNombre;
  final DateTime fecha;
  final String auditorNombre;
  final Map<String, String> responsables;
  final ResultadoAuditoria resultado;
  final List<Respuesta> respuestas;

  /// Áreas del cuestionario, en orden. Vienen de la plantilla usada en esa
  /// auditoría, no de una lista fija: el informe debe reflejar el
  /// cuestionario que se pasó ese día.
  final List<AreaInfo> areas;

  /// Bytes de las evidencias, indexados por id. Los aporta quien construye
  /// el informe leyéndolos del almacén local; el generador no sabe de dónde
  /// salen, y así funciona igual en móvil que en navegador.
  final Map<String, Uint8List> imagenes;

  /// Logotipo en SVG. Se incrusta como vectorial, no como imagen: el informe
  /// se imprime y se archiva, y un PNG escalado se ve sucio en papel.
  final String? logoSvg;

  /// Si es null se usan las fuentes internas del PDF, que no cubren Unicode.
  final FuentesInforme? fuentes;
}

/// Construye el informe. Todo se genera en el dispositivo: si el auditor
/// termina sin cobertura, el PDF existe igual y se sube después.
class PdfBuilder {
  const PdfBuilder();

  Future<Uint8List> construir(DatosReporte d) async {
    final doc = pw.Document(
      title: 'Auditoría ${d.centroNombre}',
      author: d.auditorNombre,
      theme: d.fuentes?.tema,
    );

    // Las imágenes se preparan una sola vez: un informe con 40 evidencias
    // reventaría la memoria si se decodificaran dentro del builder de cada
    // página, que se ejecuta varias veces durante el paginado.
    final imagenes = _prepararEvidencias(d);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
        footer: (ctx) => _pie(ctx, d),
        build: (ctx) => [
          _portada(d),
          pw.SizedBox(height: 18),
          _tablaAreas(d),
          pw.SizedBox(height: 18),
          _resumenEjecutivo(d),
          ..._desgloseHallazgos(d, imagenes),
          pw.SizedBox(height: 24),
          _firmas(d),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------- portada

  pw.Widget _portada(DatosReporte d) {
    final r = d.resultado;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('AUDITORÍA OPERATIVA DE TALLER',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  pw.SizedBox(height: 4),
                  pw.Text(d.centroNombre,
                      style: const pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Fecha: ${_fecha(d.fecha)}   ·   Auditor: ${d.auditorNombre}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            if (d.logoSvg != null)
              pw.SizedBox(height: 34, width: 136, child: pw.SvgImage(svg: d.logoSvg!)),
          ],
        ),
        pw.Divider(thickness: 1.2),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _marcadorGlobal(r),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Center(
                child: RadarChart(
                  ejes: d.areas.map((a) => a.nombre).toList(),
                  valores: d.areas
                      .map((a) => r.areas[a.codigo]?.porcentaje ?? 0)
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _marcadorGlobal(ResultadoAuditoria r) {
    final color = _colorNota(r.puntuacionGlobal);
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.12),
        border: pw.Border.all(color: color, width: 1.4),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text('PUNTUACIÓN GLOBAL',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 6),
          pw.Text('${r.puntuacionGlobal.toStringAsFixed(1)}%',
              style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text('Nivel ${r.nivel}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
          if (r.totalCriticasFalladas > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text('${r.totalCriticasFalladas} incumplimiento(s) crítico(s)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.red800, fontWeight: pw.FontWeight.bold)),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ tabla áreas

  pw.Widget _tablaAreas(DatosReporte d) {
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headerStyle: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
      },
      headers: const ['Área', 'Responsable', 'Puntos', 'N/A', 'Críticas', '%'],
      data: [
        for (final a in d.areas)
          () {
            final r = d.resultado.areas[a.codigo];
            if (r == null) return [a.nombre, '-', '-', '-', '-', '-'];
            return [
              a.nombre,
              d.responsables[a.codigo] ?? '-',
              '${r.puntosObtenidos.toStringAsFixed(1)}/${r.puntosPosibles.toStringAsFixed(0)}',
              '${r.nNoAplica}',
              '${r.nCriticasFalladas}',
              r.evaluable ? '${r.porcentaje.toStringAsFixed(1)}%' : 'N/A',
            ];
          }(),
      ],
    );
  }

  // ------------------------------------------------------ resumen ejecutivo

  pw.Widget _resumenEjecutivo(DatosReporte d) {
    final areasOrdenadas = d.areas
        .where((a) => d.resultado.areas[a.codigo]?.evaluable ?? false)
        .toList()
      ..sort((x, y) => (d.resultado.areas[y.codigo]!.porcentaje)
          .compareTo(d.resultado.areas[x.codigo]!.porcentaje));

    final fortalezas = areasOrdenadas.where((a) => d.resultado.areas[a.codigo]!.porcentaje >= 85);
    final mejoras = areasOrdenadas.reversed
        .where((a) => d.resultado.areas[a.codigo]!.porcentaje < 85);

    // Los 5 hallazgos de mayor impacto: primero críticos, luego por peso.
    final criticos = d.respuestas.where((r) => r.valor?.esHallazgo ?? false).toList()
      ..sort((x, y) {
        final porCritica = (y.critica ? 1 : 0).compareTo(x.critica ? 1 : 0);
        if (porCritica != 0) return porCritica;
        final porValor = (x.valor == ValorRespuesta.noCumple ? 0 : 1)
            .compareTo(y.valor == ValorRespuesta.noCumple ? 0 : 1);
        if (porValor != 0) return porValor;
        return y.peso.compareTo(x.peso);
      });

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Resumen ejecutivo'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _bloqueLista(
                'Fortalezas',
                PdfColors.green700,
                fortalezas
                    .map((a) =>
                        '${a.nombre}: ${d.resultado.areas[a.codigo]!.porcentaje.toStringAsFixed(1)}%')
                    .toList(),
                vacio: 'Ningún área alcanza el 85 %.',
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _bloqueLista(
                'Áreas de mejora',
                PdfColors.red700,
                mejoras
                    .map((a) =>
                        '${a.nombre}: ${d.resultado.areas[a.codigo]!.porcentaje.toStringAsFixed(1)}%')
                    .toList(),
                vacio: 'Todas las áreas por encima del 85 %.',
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _bloqueLista(
          'Prioridades de acción',
          PdfColors.blueGrey800,
          criticos.take(5).map((r) {
            final marca = r.critica ? '[CRÍTICA] ' : '';
            return '$marca${r.textoPregunta} (${r.valor!.etiqueta})';
          }).toList(),
          vacio: 'Sin incumplimientos registrados.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------- hallazgos

  List<pw.Widget> _desgloseHallazgos(DatosReporte d, Map<String, pw.MemoryImage> imagenes) {
    final widgets = <pw.Widget>[
      pw.SizedBox(height: 16),
      _tituloSeccion('Desglose de incumplimientos por área'),
      pw.Text(
        'Solo se listan las preguntas valoradas como "No cumple" o "Cumple parcialmente".',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    ];

    for (final area in d.areas) {
      final hallazgos = d.respuestas
          .where((r) => r.areaCodigo == area.codigo && (r.valor?.esHallazgo ?? false))
          .toList()
        ..sort((x, y) => y.peso.compareTo(x.peso));

      widgets.add(pw.SizedBox(height: 12));
      widgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: PdfColor(area.color.red, area.color.green, area.color.blue, 0.15),
          child: pw.Text(
            '${area.nombre}  ·  ${hallazgos.length} hallazgo(s)',
            style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      if (hallazgos.isEmpty) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, left: 8),
          child: pw.Text('Sin incumplimientos en esta área.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ));
        continue;
      }

      for (final h in hallazgos) {
        widgets.add(_fichaHallazgo(h, area, imagenes));
      }
    }
    return widgets;
  }

  pw.Widget _fichaHallazgo(
      Respuesta r, AreaInfo area, Map<String, pw.MemoryImage> imagenes) {
    final esNoCumple = r.valor == ValorRespuesta.noCumple;
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                margin: const pw.EdgeInsets.only(right: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: esNoCumple ? PdfColors.red100 : PdfColors.amber100,
                child: pw.Text(
                  r.valor!.etiqueta.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: esNoCumple ? PdfColors.red900 : PdfColors.orange900,
                  ),
                ),
              ),
              if (r.critica)
                pw.Container(
                  margin: const pw.EdgeInsets.only(right: 6),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  color: PdfColors.red800,
                  child: pw.Text('CRÍTICA',
                      style: const pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                ),
              pw.Expanded(
                child: pw.Text(r.textoPregunta, style: const pw.TextStyle(fontSize: 9.5)),
              ),
              pw.Text('peso ${r.peso}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
          if (r.comentario.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 5, left: 2),
              child: pw.Text('Observación: ${r.comentario}',
                  style: const pw.TextStyle(
                      fontSize: 8.5,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey800)),
            ),
          if (r.evidencias.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Row(
                children: [
                  for (final e in r.evidencias)
                    if (imagenes[e.id] != null)
                      pw.Container(
                        margin: const pw.EdgeInsets.only(right: 6),
                        width: 90,
                        height: 68,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400),
                          image: pw.DecorationImage(
                              image: imagenes[e.id]!, fit: pw.BoxFit.cover),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- firmas

  pw.Widget _firmas(DatosReporte d) {
    pw.Widget casilla(String rol, String nombre) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(height: 60),
              pw.Divider(thickness: 0.8),
              pw.Text(rol, style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(nombre, style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Fecha: ${_fecha(d.fecha)}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Conformidad'),
        pw.Row(children: [
          casilla('Auditor', d.auditorNombre),
          pw.SizedBox(width: 40),
          casilla('Gerente del centro', d.responsables['gerente'] ?? ''),
        ]),
      ],
    );
  }

  // -------------------------------------------------------------- auxiliares

  pw.Widget _tituloSeccion(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(texto.toUpperCase(),
            style: const pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6)),
      );

  pw.Widget _bloqueLista(String titulo, PdfColor color, List<String> items,
      {required String vacio}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: color, width: 3)),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titulo,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 4),
          if (items.isEmpty)
            pw.Text(vacio, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))
          else
            for (final i in items)
              pw.Bullet(text: i, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  pw.Widget _pie(pw.Context ctx, DatosReporte d) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          '${d.centroNombre} · ${_fecha(d.fecha)} · Página ${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      );

  /// Prepara solo las evidencias que van a salir impresas. Decodificar las de
  /// las preguntas conformes sería trabajo tirado y memoria ocupada para nada.
  Map<String, pw.MemoryImage> _prepararEvidencias(DatosReporte d) {
    final mapa = <String, pw.MemoryImage>{};
    for (final r in d.respuestas) {
      if (!(r.valor?.esHallazgo ?? false)) continue;
      for (final e in r.evidencias) {
        final bytes = d.imagenes[e.id];
        if (bytes != null) mapa[e.id] = pw.MemoryImage(bytes);
      }
    }
    return mapa;
  }

  static PdfColor _colorNota(double p) {
    if (p >= 90) return PdfColors.green700;
    if (p >= 80) return PdfColors.lightGreen800;
    if (p >= 65) return PdfColors.orange800;
    return PdfColors.red800;
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
