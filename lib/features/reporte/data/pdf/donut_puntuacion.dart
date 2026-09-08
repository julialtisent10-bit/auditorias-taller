// ignore_for_file: prefer_const_constructors
//
// `pw.TextStyle` no admite `const` en varios usos de este fichero: su
// inicializador interno impide la evaluación constante y el analizador
// rechaza el `const` que el propio linter reclama.

import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Indicador circular de la puntuación global.
///
/// Sustituye al gráfico de araña, que con siete áreas salía apretado e
/// ilegible. Un anillo con el número dentro se lee de un vistazo, que es lo
/// único que se le pide a la portada de un informe; el detalle por áreas va
/// justo debajo en barras, donde sí se puede comparar.
///
/// El arco se aproxima con segmentos rectos en lugar de curvas: a la
/// resolución de impresión no se distingue, y evita depender de primitivas de
/// arco cuyo comportamiento varía entre versiones del paquete.
class DonutPuntuacion extends pw.StatelessWidget {
  DonutPuntuacion({
    required this.porcentaje,
    required this.color,
    this.nivel,
    this.tamano = 132,
    this.grosor = 15,
  });

  /// 0..100.
  final double porcentaje;
  final PdfColor color;

  /// Letra del nivel (A, B, C, D). Va bajo el número.
  final String? nivel;

  final double tamano;
  final double grosor;

  @override
  pw.Widget build(pw.Context context) {
    return pw.SizedBox(
      width: tamano,
      height: tamano,
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          pw.SizedBox(
            width: tamano,
            height: tamano,
            child: pw.CustomPaint(painter: _pintar),
          ),
          pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                '${porcentaje.toStringAsFixed(1)}%',
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                ),
              ),
              if (nivel != null)
                pw.Text(
                  'NIVEL $nivel',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _pintar(PdfGraphics canvas, PdfPoint size) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final radio = math.min(cx, cy) - grosor / 2;

    // Anillo de fondo: deja ver cuánto falta, no solo cuánto hay.
    canvas
      ..setLineWidth(grosor)
      ..setStrokeColor(PdfColors.grey300);
    _trazarArco(canvas, cx, cy, radio, 1.0);
    canvas.strokePath();

    final fraccion = (porcentaje.clamp(0, 100)) / 100;
    if (fraccion <= 0) return;

    canvas.setStrokeColor(color);
    _trazarArco(canvas, cx, cy, radio, fraccion);
    canvas.strokePath();
  }

  /// Arranca arriba y avanza en el sentido de las agujas del reloj.
  ///
  /// En un PDF el eje vertical crece hacia arriba, así que «arriba» es +π/2 y
  /// el sentido horario se consigue restando ángulo, no sumándolo.
  void _trazarArco(
      PdfGraphics canvas, double cx, double cy, double radio, double fraccion) {
    const pasos = 180;
    final hasta = (pasos * fraccion).ceil().clamp(1, pasos);

    for (var i = 0; i <= hasta; i++) {
      final angulo = math.pi / 2 - (2 * math.pi * fraccion * i / hasta);
      final x = cx + radio * math.cos(angulo);
      final y = cy + radio * math.sin(angulo);
      if (i == 0) {
        canvas.moveTo(x, y);
      } else {
        canvas.lineTo(x, y);
      }
    }
  }
}
