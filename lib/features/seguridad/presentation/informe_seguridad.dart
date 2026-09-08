import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;

import '../../../app/di/providers.dart';
import '../../../core/almacen/almacen_binarios.dart';
import '../../reporte/data/pdf/pdf_builder.dart';
import 'providers/revision_controller.dart';

/// Ensambla el modelo del informe a partir del estado de la revisión en
/// curso. `DatosReporte` y `PdfBuilder` son genéricos —no conocen el
/// cuestionario de postventa ni el de seguridad— así que se reutilizan tal
/// cual; lo único que cambia es cómo se rellenan aquí.
Future<DatosReporte?> construirDatosReporteSeguridad(WidgetRef ref) async {
  final state = ref.read(revisionControllerProvider);
  final revision = ref.read(revisionSeguridadActualProvider);
  if (revision == null) return null;

  String? logo;
  try {
    logo = await rootBundle.loadString('assets/branding/scaitt_logo.svg');
  } catch (_) {
    logo = null;
  }

  FuentesInforme? fuentes;
  try {
    fuentes = FuentesInforme(
      base: pw.Font.ttf(await rootBundle.load(FuentesInforme.rutaBase)),
      negrita: pw.Font.ttf(await rootBundle.load(FuentesInforme.rutaNegrita)),
      cursiva: pw.Font.ttf(await rootBundle.load(FuentesInforme.rutaCursiva)),
    );
  } catch (_) {
    fuentes = null;
  }

  // Igual que en postventa: los bytes salen del almacén local, no de la red,
  // para poder generar el informe sin cobertura dentro del taller.
  final almacen = ref.read(almacenProvider);
  final imagenes = <String, Uint8List>{};
  for (final r in state.respuestas.values) {
    if (!(r.valor?.esHallazgo ?? false)) continue;
    for (final e in r.evidencias) {
      final bytes = almacen.leer(AlmacenBinarios.claveEvidencia(e.id));
      if (bytes != null) imagenes[e.id] = bytes;
    }
  }

  return DatosReporte(
    tituloCuestionario: revision.plantillaNombre.isEmpty
        ? 'Revisión de seguridad del taller'
        : revision.plantillaNombre,
    centroNombre: state.centroNombre,
    fecha: state.fecha,
    auditorNombre: revision.evaluadorNombre,
    // Una sola área: no hay un responsable por área que imprimir en la
    // tabla, y sin firma manuscrita tampoco hace falta un "gerente" aquí.
    responsables: const {},
    resultado: state.resultado,
    respuestas: state.respuestas.values.toList(),
    areas: [const AreaInfo('SEG', 'Seguridad del taller', PdfColor.fromInt(0xFFD32F2F))],
    imagenes: imagenes,
    logoSvg: logo,
    fuentes: fuentes,
  );
}
