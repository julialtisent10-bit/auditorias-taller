import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/pregunta.dart';
import '../../../../shared/area_vista.dart';
import '../providers/auditoria_controller.dart';
import '../widgets/pregunta_card.dart';

class CuestionarioPage extends ConsumerStatefulWidget {
  const CuestionarioPage({super.key});

  @override
  ConsumerState<CuestionarioPage> createState() => _CuestionarioPageState();
}

class _CuestionarioPageState extends ConsumerState<CuestionarioPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(auditoriaControllerProvider);
    final areas = state.areas;

    // El controlador se crea aquí y no en initState porque el número de
    // pestañas sale de la plantilla, que no se conoce hasta tener el estado.
    if (_tabs == null || _tabs!.length != areas.length) {
      _tabs?.dispose();
      _tabs = TabController(length: areas.length, vsync: this);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.centroNombre, style: const TextStyle(fontSize: 16)),
            Text(_fecha(state.fecha),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          // Indicador de autoguardado: el auditor necesita ver que no pierde datos.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: state.guardando
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_done_outlined, size: 20),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final area in areas)
              Tab(
                icon: Icon(area.icono, size: 20),
                child: _EtiquetaTab(
                  nombre: area.nombreCorto,
                  progreso: state.resultado.areas[area.codigo]?.progreso ?? 0,
                ),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final area in areas) _AreaView(area: area),
        ],
      ),
      bottomNavigationBar: _BarraInferior(
        onFinalizar: state.puedeFinalizar
            ? () => Navigator.of(context).pushNamed('/auditoria/resumen')
            : null,
      ),
    );
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _EtiquetaTab extends StatelessWidget {
  const _EtiquetaTab({required this.nombre, required this.progreso});
  final String nombre;
  final double progreso;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(nombre, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        SizedBox(width: 64, child: LinearProgressIndicator(value: progreso, minHeight: 3)),
      ],
    );
  }
}

class _AreaView extends ConsumerWidget {
  const _AreaView({required this.area});
  final AreaVista area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditoriaControllerProvider);
    final bloques = state.bloquesDe(area.codigo);

    if (bloques.isEmpty) {
      return const Center(child: Text('Esta área no tiene preguntas en la plantilla.'));
    }

    return ListView(
      // El padding inferior deja hueco para la barra fija de puntuación.
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        _CabeceraArea(area: area),
        for (final entrada in bloques.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text(
              entrada.key.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: area.color,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final Pregunta pregunta in entrada.value)
            PreguntaCard(pregunta: pregunta, colorArea: area.color),
        ],
      ],
    );
  }
}

class _CabeceraArea extends ConsumerWidget {
  const _CabeceraArea({required this.area});
  final AreaVista area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(auditoriaControllerProvider).resultado.areas[area.codigo];
    if (r == null) return const SizedBox.shrink();

    final avisoTope = r.topadaPorCritica ? ' · área topada al 79%' : '';

    return Card(
      color: area.color.withValues(alpha: 0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(
              r.evaluable ? '${r.porcentaje.toStringAsFixed(1)}%' : '—',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: area.color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.nTotal - r.nSinResponder}/${r.nTotal} respondidas · ${r.nNoAplica} N/A'),
                  if (r.nCriticasFalladas > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.redAccent),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${r.nCriticasFalladas} crítica(s) incumplida(s)$avisoTope',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarraInferior extends ConsumerWidget {
  const _BarraInferior({this.onFinalizar});
  final VoidCallback? onFinalizar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditoriaControllerProvider);
    final res = state.resultado;
    final pendientes = state.evidenciasPendientes.length;

    final subtitulo = pendientes > 0
        ? '$pendientes foto(s) obligatoria(s) pendiente(s)'
        : '${(res.progresoGlobal * 100).round()}% completado';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Global ${res.puntuacionGlobal.toStringAsFixed(1)}%  ·  Nivel ${res.nivel}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  subtitulo,
                  style: TextStyle(
                      fontSize: 12, color: pendientes > 0 ? Colors.redAccent : Colors.grey),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onFinalizar,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Finalizar'),
            ),
          ],
        ),
      ),
    );
  }
}
