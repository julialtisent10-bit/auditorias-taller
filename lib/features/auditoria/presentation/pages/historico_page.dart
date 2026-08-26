import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/almacen/almacen_binarios.dart';
import '../../../../core/descarga_web.dart';
import '../../../reporte/data/exportador_excel.dart';
import '../../domain/entities/auditoria.dart';
import '../borrar_auditoria.dart';

/// Todas las auditorías, abiertas y cerradas.
///
/// Hasta ahora las cerradas solo asomaban en el ranking, que enseña una por
/// centro: no había forma de ver el histórico completo, recuperar un informe
/// ni borrar las pruebas hechas mientras se montaba la aplicación.
class HistoricoPage extends ConsumerWidget {
  const HistoricoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditorias = ref.watch(todasLasAuditoriasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditorías'),
        actions: [
          IconButton(
            tooltip: 'Exportar histórico a Excel',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => _exportarHistorico(context, ref),
          ),
        ],
      ),
      body: auditorias.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text('No se pudo cargar el histórico:\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Todavía no hay ninguna auditoría.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: lista.length,
            itemBuilder: (_, i) => _Fila(auditoria: lista[i]),
          );
        },
      ),
    );
  }

  /// Una fila por auditoría cerrada, con su desglose por áreas, para cruzarlo
  /// con los informes de postventa que ya se llevan en hoja de cálculo.
  Future<void> _exportarHistorico(BuildContext context, WidgetRef ref) async {
    final mensajero = ScaffoldMessenger.of(context);
    final cerradas = (ref.read(todasLasAuditoriasProvider).value ?? const [])
        .where((a) => a.estado == EstadoAuditoria.finalizada)
        .toList();

    if (cerradas.isEmpty) {
      mensajero.showSnackBar(const SnackBar(
          content: Text('No hay ninguna auditoría cerrada que exportar.')));
      return;
    }

    try {
      final plantilla = await ref.read(plantillaRepositoryProvider).cargar();
      final bytes = const ExportadorExcel()
          .historico(auditorias: cerradas, areas: plantilla.areas);
      descargarBytes(bytes, 'Historico_auditorias.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.auditoria});

  final Auditoria auditoria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esquema = Theme.of(context).colorScheme;
    final cerrada = auditoria.estado == EstadoAuditoria.finalizada;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          cerrada ? Icons.task_alt : Icons.pending_actions,
          color: cerrada ? esquema.primary : Colors.orangeAccent,
        ),
        title: Text(auditoria.centroNombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          cerrada
              ? '${_fecha(auditoria.fecha)} · '
                  '${auditoria.puntuacionGlobal.toStringAsFixed(1)} % · '
                  'Nivel ${auditoria.nivel}'
              : '${_fecha(auditoria.fecha)} · sin terminar',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (opcion) async {
            if (opcion == 'informe') {
              await _abrirInforme(context, ref);
            } else if (opcion == 'continuar') {
              final navegador = Navigator.of(context);
              await reanudarAuditoria(ref, auditoria);
              navegador.pushNamed('/auditoria');
            } else if (opcion == 'excel') {
              await _exportar(context, ref);
            } else if (opcion == 'borrar') {
              await confirmarYBorrarAuditoria(context, ref, auditoria);
            }
          },
          itemBuilder: (_) => [
            if (cerrada) ...[
              const PopupMenuItem(value: 'informe', child: Text('Ver informe')),
              const PopupMenuItem(value: 'excel', child: Text('Exportar a Excel')),
            ] else
              const PopupMenuItem(
                  value: 'continuar', child: Text('Continuar auditoría')),
            const PopupMenuItem(value: 'borrar', child: Text('Borrar')),
          ],
        ),
      ),
    );
  }

  /// El informe se guardó en este dispositivo al cerrar la auditoría. Si se
  /// cerró desde otro móvil, o el navegador liberó espacio, ya no está: no
  /// hay copia en la nube porque el plan gratuito no incluye Storage.
  Future<void> _abrirInforme(BuildContext context, WidgetRef ref) async {
    final almacen = ref.read(almacenProvider);
    final pdf = almacen.leer(AlmacenBinarios.claveInforme(auditoria.id));

    if (pdf == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El informe no está en este dispositivo. Solo se guarda donde se '
            'cerró la auditoría.',
          ),
        ),
      );
      return;
    }

    await Printing.sharePdf(
      bytes: pdf,
      filename: 'Auditoria_${auditoria.centroNombre}_${_fecha(auditoria.fecha)}.pdf'
          .replaceAll('/', '-'),
    );
  }

  Future<void> _exportar(BuildContext context, WidgetRef ref) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final respuestas =
          await ref.read(auditoriaRepositoryProvider).respuestasDe(auditoria.id);
      final plantilla = await ref
          .read(plantillaRepositoryProvider)
          .cargar(plantillaId: auditoria.plantillaId);

      final bytes = const ExportadorExcel().auditoria(
        auditoria: auditoria,
        respuestas: respuestas,
        areas: plantilla.areas,
      );
      descargarBytes(
        bytes,
        ExportadorExcel.nombreFichero(auditoria.centroNombre, auditoria.fecha),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
