import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../auditoria/domain/entities/auditoria.dart';
import '../../auditoria/domain/entities/respuesta.dart';
import '../../auditoria/domain/entities/valor_respuesta.dart';
import '../../plantillas/domain/entities/plantilla.dart';

/// Genera los libros de Excel.
///
/// El cuestionario vino de una hoja de cálculo y los informes de postventa se
/// siguen cruzando ahí, así que la aplicación tiene que saber devolver los
/// datos en ese formato en lugar de encerrarlos en un PDF.
class ExportadorExcel {
  const ExportadorExcel();

  /// Una auditoría concreta, con el mismo aspecto que la hoja original:
  /// cabecera, preguntas agrupadas por área con su puntuación de 0 a 2,
  /// subtotales y observaciones.
  Uint8List auditoria({
    required Auditoria auditoria,
    required List<Respuesta> respuestas,
    required List<AreaPlantilla> areas,
  }) {
    final libro = Excel.createExcel();
    final hoja = libro[libro.getDefaultSheet()!];

    var fila = 0;

    void escribir(int columna, dynamic valor, {bool negrita = false}) {
      final celda = hoja.cell(
          CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: fila));
      celda.value = switch (valor) {
        null => null,
        final num n => DoubleCellValue(n.toDouble()),
        _ => TextCellValue(valor.toString()),
      };
      if (negrita) celda.cellStyle = CellStyle(bold: true);
    }

    escribir(0, auditoria.plantillaNombre.isEmpty
        ? 'Auditoría de taller'
        : auditoria.plantillaNombre, negrita: true);
    fila += 2;

    escribir(0, 'Centro:', negrita: true);
    escribir(1, auditoria.centroNombre);
    escribir(2, 'Fecha:', negrita: true);
    escribir(3, _fecha(auditoria.fecha));
    fila++;
    escribir(0, 'Auditor:', negrita: true);
    escribir(1, auditoria.auditorNombre);
    escribir(2, 'Global:', negrita: true);
    escribir(3, auditoria.puntuacionGlobal);
    fila += 2;

    escribir(0, 'ESCALA: 0 = No cumple · 1 = Cumple parcialmente · '
        '2 = Cumple · N/A = No aplica');
    fila += 2;

    escribir(0, 'Nº', negrita: true);
    escribir(1, 'PUNTO A AUDITAR', negrita: true);
    escribir(2, 'PUNTUACIÓN', negrita: true);
    escribir(3, 'OBSERVACIONES', negrita: true);
    fila++;

    final porArea = <String, List<Respuesta>>{};
    for (final r in respuestas) {
      porArea.putIfAbsent(r.areaCodigo, () => []).add(r);
    }

    var numero = 1;
    for (final area in areas) {
      final delArea = porArea[area.codigo] ?? const <Respuesta>[];
      if (delArea.isEmpty) continue;

      fila++;
      escribir(0, area.nombre.toUpperCase(), negrita: true);
      fila++;

      var obtenidos = 0.0;
      var posibles = 0.0;

      for (final r in delArea) {
        escribir(0, numero++);
        escribir(1, r.textoPregunta);
        // Se escribe el número, no la etiqueta: así la columna suma y se
        // puede cruzar con las hojas que ya existen.
        escribir(2, r.valor == null || r.valor == ValorRespuesta.noAplica
            ? (r.valor == null ? '' : 'N/A')
            : (r.valor!.factor! * 2).round());
        escribir(3, r.comentario);
        fila++;

        if (r.computa) {
          obtenidos += r.puntosObtenidos * 2;
          posibles += r.puntosPosibles * 2;
        }
      }

      escribir(1, 'SUBTOTAL ${area.nombre.toUpperCase()}', negrita: true);
      escribir(2, obtenidos, negrita: true);
      escribir(3, posibles == 0
          ? 'Sin preguntas aplicables'
          : '${(obtenidos / posibles * 100).toStringAsFixed(1)} %');
      fila += 2;
    }

    if (auditoria.fortalezas.trim().isNotEmpty) {
      escribir(0, 'FORTALEZAS DETECTADAS', negrita: true);
      fila++;
      escribir(1, auditoria.fortalezas.trim());
      fila += 2;
    }

    hoja.setColumnWidth(1, 62);
    hoja.setColumnWidth(3, 44);

    return Uint8List.fromList(libro.encode()!);
  }

  /// Histórico de todos los centros: una fila por auditoría, con la nota
  /// global y el desglose por áreas, para cruzarlo con otros informes.
  Uint8List historico({
    required List<Auditoria> auditorias,
    required List<AreaPlantilla> areas,
  }) {
    final libro = Excel.createExcel();
    final hoja = libro[libro.getDefaultSheet()!];

    var fila = 0;
    void escribir(int columna, dynamic valor, {bool negrita = false}) {
      final celda = hoja.cell(
          CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: fila));
      celda.value = switch (valor) {
        null => null,
        final num n => DoubleCellValue(n.toDouble()),
        _ => TextCellValue(valor.toString()),
      };
      if (negrita) celda.cellStyle = CellStyle(bold: true);
    }

    escribir(0, 'Centro', negrita: true);
    escribir(1, 'Fecha', negrita: true);
    escribir(2, 'Auditor', negrita: true);
    escribir(3, 'Global', negrita: true);
    escribir(4, 'Nivel', negrita: true);
    for (var i = 0; i < areas.length; i++) {
      escribir(5 + i, areas[i].nombre, negrita: true);
    }
    fila++;

    for (final a in auditorias) {
      escribir(0, a.centroNombre);
      escribir(1, _fecha(a.fecha));
      escribir(2, a.auditorNombre);
      escribir(3, a.puntuacionGlobal);
      escribir(4, a.nivel);
      for (var i = 0; i < areas.length; i++) {
        escribir(5 + i, a.porcentajeArea(areas[i].codigo));
      }
      fila++;
    }

    hoja.setColumnWidth(0, 26);
    return Uint8List.fromList(libro.encode()!);
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  static String nombreFichero(String centro, DateTime fecha) {
    final f = '${fecha.year}'
        '${fecha.month.toString().padLeft(2, '0')}'
        '${fecha.day.toString().padLeft(2, '0')}';
    final limpio = centro.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'Auditoria_${limpio}_$f.xlsx';
  }
}
