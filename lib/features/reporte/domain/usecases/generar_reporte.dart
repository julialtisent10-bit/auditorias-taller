import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../../data/pdf/pdf_builder.dart';

/// Genera el informe y lo pone en manos del auditor.
///
/// En la PWA no hay sistema de ficheros ni hoja de compartir del sistema:
/// el paquete `printing` resuelve las dos cosas contra el navegador
/// (`layoutPdf` abre el diálogo de impresión, `sharePdf` dispara la descarga).
/// Los bytes se guardan además en el almacén local para que la cola pueda
/// subirlos a Storage cuando haya red.
class GenerarReporte {
  const GenerarReporte({this.builder = const PdfBuilder()});

  final PdfBuilder builder;

  Future<Uint8List> bytes(DatosReporte datos) => builder.construir(datos);

  /// Vista previa con opción de imprimir. Útil para dejar copia en papel
  /// firmada en el propio centro.
  Future<void> previsualizar(DatosReporte datos) async {
    await Printing.layoutPdf(
      onLayout: (_) => builder.construir(datos),
      name: nombreFichero(datos),
    );
  }

  Future<void> compartir(Uint8List pdf, DatosReporte datos) async {
    await Printing.sharePdf(bytes: pdf, filename: nombreFichero(datos));
  }

  static String nombreFichero(DatosReporte d) {
    final f = d.fecha;
    final fecha = '${f.year}${f.month.toString().padLeft(2, '0')}'
        '${f.day.toString().padLeft(2, '0')}';
    final centro = d.centroNombre.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'Auditoria_${centro}_$fecha.pdf';
  }
}
