import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Gráfico de araña vectorial dibujado directamente sobre el lienzo del PDF.
///
/// El paquete `pdf` no trae radar entre sus charts, así que se pinta a mano
/// con CustomPaint. Al ser vectorial, el informe se puede imprimir en A3 o
/// hacer zoom sin pixelar (a diferencia de capturar un widget Flutter a PNG).
class RadarChart extends pw.StatelessWidget {
  RadarChart({
    required this.ejes,
    required this.valores,
    this.tamano = 220,
    this.color = const PdfColor.fromInt(0xFF1E88E5),
  }) : assert(ejes.length == valores.length);

  /// Nombres de los ejes, en sentido horario empezando arriba.
  final List<String> ejes;

  /// Valores 0..100, alineados con [ejes].
  final List<double> valores;

  final double tamano;
  final PdfColor color;

  @override
  pw.Widget build(pw.Context context) {
    // Margen para que las etiquetas no se coman el borde del lienzo.
    const margenEtiquetas = 46.0;

    return pw.SizedBox(
      width: tamano + margenEtiquetas * 2,
      height: tamano + margenEtiquetas,
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          pw.Center(
            child: pw.SizedBox(
              width: tamano,
              height: tamano,
              child: pw.CustomPaint(painter: _pintar),
            ),
          ),
          ..._etiquetas(margenEtiquetas),
        ],
      ),
    );
  }

  List<pw.Widget> _etiquetas(double margen) {
    final alineaciones = <pw.Alignment>[
      pw.Alignment.topCenter,
      pw.Alignment.centerRight,
      pw.Alignment.bottomCenter,
      pw.Alignment.centerLeft,
    ];
    return [
      for (var i = 0; i < ejes.length && i < 4; i++)
        pw.Align(
          alignment: alineaciones[i],
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(ejes[i],
                  style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('${valores[i].toStringAsFixed(1)}%',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ),
    ];
  }

  void _pintar(PdfGraphics canvas, PdfPoint size) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final radio = math.min(cx, cy) * 0.82;
    final n = ejes.length;

    PdfPoint punto(int i, double fraccion) {
      // -pi/2 arranca en el eje vertical superior; se avanza en horario.
      final angulo = -math.pi / 2 + (2 * math.pi * i / n);
      return PdfPoint(
        cx + radio * fraccion * math.cos(angulo),
        cy + radio * fraccion * math.sin(angulo),
      );
    }

    // Retícula: anillos al 25/50/75/100 %.
    canvas
      ..setLineWidth(0.4)
      ..setStrokeColor(PdfColors.grey400);
    for (final anillo in const [0.25, 0.5, 0.75, 1.0]) {
      for (var i = 0; i < n; i++) {
        final a = punto(i, anillo);
        final b = punto((i + 1) % n, anillo);
        if (i == 0) canvas.moveTo(a.x, a.y);
        canvas.lineTo(b.x, b.y);
      }
      canvas
        ..closePath()
        ..strokePath();
    }

    // Radios.
    canvas.setStrokeColor(PdfColors.grey300);
    for (var i = 0; i < n; i++) {
      final p = punto(i, 1.0);
      canvas
        ..moveTo(cx, cy)
        ..lineTo(p.x, p.y)
        ..strokePath();
    }

    // Umbral objetivo (80 %) en discontinuo visual: verde claro.
    canvas
      ..setStrokeColor(PdfColors.green300)
      ..setLineWidth(0.8);
    for (var i = 0; i < n; i++) {
      final a = punto(i, 0.8);
      final b = punto((i + 1) % n, 0.8);
      if (i == 0) canvas.moveTo(a.x, a.y);
      canvas.lineTo(b.x, b.y);
    }
    canvas
      ..closePath()
      ..strokePath();

    // Polígono de resultados.
    for (var i = 0; i < n; i++) {
      final p = punto(i, (valores[i].clamp(0, 100)) / 100);
      if (i == 0) {
        canvas.moveTo(p.x, p.y);
      } else {
        canvas.lineTo(p.x, p.y);
      }
    }
    canvas
      ..closePath()
      ..setFillColor(PdfColor(color.red, color.green, color.blue, 0.28))
      ..setStrokeColor(color)
      ..setLineWidth(1.4)
      ..fillAndStrokePath();

    // Vértices.
    canvas.setFillColor(color);
    for (var i = 0; i < n; i++) {
      final p = punto(i, (valores[i].clamp(0, 100)) / 100);
      canvas
        ..drawEllipse(p.x, p.y, 2.2, 2.2)
        ..fillPath();
    }
  }
}
