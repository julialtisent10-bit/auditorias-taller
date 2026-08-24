import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../app/di/providers.dart';
import '../../../../core/almacen/almacen_binarios.dart';
import '../../../reporte/data/pdf/pdf_builder.dart';
import '../../domain/entities/respuesta.dart';
import '../../domain/entities/valor_respuesta.dart';
import '../../domain/usecases/calcular_puntuacion.dart';
import '../providers/auditoria_controller.dart';
import 'cuestionario_page.dart';

/// Resultado antes de firmar: qué nota sale, dónde están los problemas y
/// vista previa del informe.
class ResumenPage extends ConsumerWidget {
  const ResumenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditoriaControllerProvider);
    final res = state.resultado;
    final hallazgos = state.respuestas.values
        .where((r) => r.valor?.esHallazgo ?? false)
        .toList()
      ..sort((x, y) {
        final porCritica = (y.critica ? 1 : 0).compareTo(x.critica ? 1 : 0);
        return porCritica != 0 ? porCritica : y.peso.compareTo(x.peso);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Resumen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _Marcador(puntuacion: res.puntuacionGlobal, nivel: res.nivel),
          const SizedBox(height: 20),
          for (final area in areasAuditoria)
            if (res.areas[area.codigo] != null)
              _FilaArea(area: area, resultado: res.areas[area.codigo]!),
          if (res.totalCriticasFalladas > 0) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.gpp_bad, color: Colors.redAccent),
                title: Text('${res.totalCriticasFalladas} incumplimiento(s) crítico(s)'),
                subtitle: const Text(
                    'Las áreas afectadas quedan topadas al 79 % con independencia del resto.'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Hallazgos (${hallazgos.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (hallazgos.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline, color: Colors.green),
                title: Text('Sin incumplimientos registrados'),
              ),
            ),
          for (final h in hallazgos) _FilaHallazgo(respuesta: h),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _previsualizar(context, ref),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Ver informe'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/auditoria/firma'),
                  icon: const Icon(Icons.draw),
                  label: const Text('Firmar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _previsualizar(BuildContext context, WidgetRef ref) async {
    final datos = await construirDatosReporte(ref);
    if (datos == null) return;
    await ref.read(generarReporteProvider).previsualizar(datos);
  }
}

/// Ensambla el modelo del informe a partir del estado en curso.
/// Compartido por la vista previa y por el cierre definitivo.
Future<DatosReporte?> construirDatosReporte(WidgetRef ref) async {
  final state = ref.read(auditoriaControllerProvider);
  final auditoria = ref.read(auditoriaActualProvider);
  if (auditoria == null) return null;

  String? logo;
  try {
    logo = await rootBundle.loadString('assets/branding/scaitt_logo.svg');
  } catch (_) {
    // Sin logotipo el informe sale igual, solo que sin marca en la portada.
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
    // Se degrada a las fuentes internas del PDF antes que no emitir informe.
    fuentes = null;
  }

  // Los bytes de las evidencias se leen del almacen local, no de la red: el
  // informe tiene que poder generarse dentro del taller, sin cobertura.
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
    centroNombre: state.centroNombre,
    fecha: state.fecha,
    auditorNombre: auditoria.auditorNombre,
    responsables: auditoria.responsables,
    resultado: state.resultado,
    respuestas: state.respuestas.values.toList(),
    imagenes: imagenes,
    logoSvg: logo,
    fuentes: fuentes,
  );
}

class _Marcador extends StatelessWidget {
  const _Marcador({required this.puntuacion, required this.nivel});
  final double puntuacion;
  final String nivel;

  @override
  Widget build(BuildContext context) {
    final color = puntuacion >= 90
        ? Colors.green.shade700
        : puntuacion >= 80
            ? Colors.lightGreen.shade800
            : puntuacion >= 65
                ? Colors.orange.shade800
                : Colors.red.shade800;

    return Card(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text('${puntuacion.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 48, fontWeight: FontWeight.bold, color: color)),
            Text('Nivel $nivel',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _FilaArea extends StatelessWidget {
  const _FilaArea({required this.area, required this.resultado});
  final AreaTab area;
  final ResultadoArea resultado;

  @override
  Widget build(BuildContext context) {
    final evaluable = resultado.evaluable;
    final porcentaje = resultado.porcentaje;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(area.icono, color: area.color, size: 20),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(area.nombre, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: evaluable ? porcentaje / 100 : 0,
                minHeight: 10,
                color: area.color,
                backgroundColor: area.color.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Text(
              evaluable ? '${porcentaje.toStringAsFixed(1)}%' : 'N/A',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaHallazgo extends StatelessWidget {
  const _FilaHallazgo({required this.respuesta});
  final Respuesta respuesta;

  @override
  Widget build(BuildContext context) {
    final esNoCumple = respuesta.valor == ValorRespuesta.noCumple;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          esNoCumple ? Icons.cancel : Icons.error_outline,
          color: esNoCumple ? Colors.red : Colors.orange,
        ),
        title: Text(respuesta.textoPregunta, style: const TextStyle(fontSize: 13)),
        subtitle: respuesta.comentario.trim().isEmpty
            ? null
            : Text(respuesta.comentario,
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
        trailing: respuesta.critica
            ? const Chip(
                label: Text('CRÍTICA', style: TextStyle(fontSize: 9)),
                backgroundColor: Color(0xFFFFCDD2),
                visualDensity: VisualDensity.compact,
              )
            : Text('${respuesta.evidencias.length} 📷',
                style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
