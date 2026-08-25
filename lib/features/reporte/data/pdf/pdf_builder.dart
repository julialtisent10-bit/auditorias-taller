// ignore_for_file: prefer_const_constructors
//
// `pw.TextStyle` no se puede construir como constante en muchos de los usos
// de este fichero: su inicializador interno impide la evaluación constante, y
// el analizador rechaza el `const` que el propio linter pide poner. Se
// silencia la regla aquí en vez de dejar el proyecto con errores.

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
    this.tituloCuestionario = 'Auditoría operativa de taller',
    this.fortalezas = '',
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

  /// Nombre del cuestionario, tal cual lo trae la plantilla. Antes iba fijo
  /// en el encabezado y desmentía al propio informe si el cuestionario era
  /// otro.
  final String tituloCuestionario;

  /// Fortalezas escritas por el auditor. Si va vacío, el informe deduce las
  /// áreas mejor puntuadas.
  final String fortalezas;

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
                  pw.Text(d.tituloCuestionario.toUpperCase(),
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  pw.SizedBox(height: 4),
                  pw.Text(d.centroNombre,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Fecha: ${_fecha(d.fecha)}   ·   Auditor: ${d.auditorNombre}',
                      style: pw.TextStyle(fontSize: 10)),
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
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 6),
          pw.Text('${r.puntuacionGlobal.toStringAsFixed(1)}%',
              style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text('Nivel ${r.nivel}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
          if (r.totalCriticasFalladas > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text('${r.totalCriticasFalladas} incumplimiento(s) crítico(s)',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
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
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      cellStyle: pw.TextStyle(fontSize: 9),
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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _planDeAcciones(d),
        pw.SizedBox(height: 14),
        _fortalezas(d),
      ],
    );
  }

  /// Plan de acciones correctivas, numerado como en la hoja de cálculo de la
  /// que sale este cuestionario.
  ///
  /// Se ordena por gravedad —primero lo crítico, luego lo que no cumple, y
  /// después lo parcial— de modo que lo primero de la lista es lo primero que
  /// hay que atacar.
  pw.Widget _planDeAcciones(DatosReporte d) {
    final nombreArea = {for (final a in d.areas) a.codigo: a.nombre};

    final hallazgos =
        d.respuestas.where((r) => r.valor?.esHallazgo ?? false).toList()
          ..sort((x, y) {
            final porCritica = (y.critica ? 1 : 0).compareTo(x.critica ? 1 : 0);
            if (porCritica != 0) return porCritica;
            final porValor = (x.valor == ValorRespuesta.noCumple ? 0 : 1)
                .compareTo(y.valor == ValorRespuesta.noCumple ? 0 : 1);
            if (porValor != 0) return porValor;
            return y.peso.compareTo(x.peso);
          });

    // Un plan de acciones con cuarenta puntos no es un plan. Lo que no cabe
    // aquí sigue detallado, área por área, en el desglose posterior.
    const tope = 12;
    final listadas = hallazgos.take(tope).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Plan de acciones correctivas'),
        if (hallazgos.isEmpty)
          pw.Text('No se ha detectado ningún incumplimiento.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700))
        else
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(20),
              1: pw.FlexColumnWidth(),
            },
            children: [
              for (var i = 0; i < listadas.length; i++)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Text('${i + 1}.',
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(listadas[i].textoPregunta,
                              style: pw.TextStyle(fontSize: 9)),
                          pw.Text(
                            _detalleHallazgo(listadas[i], nombreArea),
                            style: pw.TextStyle(
                                fontSize: 8,
                                fontStyle: pw.FontStyle.italic,
                                color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (hallazgos.length > tope)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              'Y ${hallazgos.length - tope} incumplimientos más, detallados por '
              'áreas en las páginas siguientes.',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
      ],
    );
  }

  static String _detalleHallazgo(Respuesta r, Map<String, String> nombreArea) {
    final partes = <String>[
      nombreArea[r.areaCodigo] ?? '',
      r.valor!.etiqueta,
      if (r.comentario.trim().isNotEmpty) r.comentario.trim(),
    ];
    return partes.where((p) => p.isNotEmpty).join('  ·  ');
  }

  /// Fortalezas detectadas, con las palabras del auditor.
  ///
  /// Si no escribió ninguna se listan las áreas mejor puntuadas: es una
  /// aproximación pobre, pero deja el apartado con algo útil en vez de vacío.
  pw.Widget _fortalezas(DatosReporte d) {
    final escritas = d.fortalezas.trim();

    final deducidas = d.areas
        .where((a) =>
            (d.resultado.areas[a.codigo]?.evaluable ?? false) &&
            d.resultado.areas[a.codigo]!.porcentaje >= 85)
        .map((a) =>
            '${a.nombre}: ${d.resultado.areas[a.codigo]!.porcentaje.toStringAsFixed(1)} %')
        .toList();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: const pw.BoxDecoration(
        border:
            pw.Border(left: pw.BorderSide(color: PdfColors.green700, width: 3)),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('FORTALEZAS DETECTADAS',
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green700)),
          pw.SizedBox(height: 4),
          if (escritas.isNotEmpty)
            pw.Text(escritas, style: pw.TextStyle(fontSize: 9))
          else if (deducidas.isEmpty)
            pw.Text('Ningún área alcanza el 85 %.',
                style:
                    pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))
          else
            for (final f in deducidas)
              pw.Bullet(text: f, style: pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }


  // ------------------------------------------------------------- hallazgos

  List<pw.Widget> _desgloseHallazgos(DatosReporte d, Map<String, pw.MemoryImage> imagenes) {
    final widgets = <pw.Widget>[
      pw.SizedBox(height: 16),
      _tituloSeccion('Desglose de incumplimientos por área'),
      pw.Text(
        'Solo se listan las preguntas valoradas como "No cumple" o "Cumple parcialmente".',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
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
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      if (hallazgos.isEmpty) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, left: 8),
          child: pw.Text('Sin incumplimientos en esta área.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
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
                      style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                ),
              pw.Expanded(
                child: pw.Text(r.textoPregunta, style: pw.TextStyle(fontSize: 9.5)),
              ),
              pw.Text('peso ${r.peso}',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
          if (r.comentario.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 5, left: 2),
              child: pw.Text('Observación: ${r.comentario}',
                  style: pw.TextStyle(
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
              pw.Text(rol, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(nombre, style: pw.TextStyle(fontSize: 9)),
              pw.Text('Fecha: ${_fecha(d.fecha)}',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
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
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6)),
      );

  pw.Widget _pie(pw.Context ctx, DatosReporte d) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          '${d.centroNombre} · ${_fecha(d.fecha)} · Página ${ctx.pageNumber}/${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
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
