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
  final _busqueda = TextEditingController();
  bool _buscando = false;

  @override
  void dispose() {
    _tabs?.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  /// Confirma antes de abandonar una auditoría a medias.
  ///
  /// Lo respondido no se pierde —se guarda al momento y la auditoría queda
  /// abierta en el histórico— pero salir sin querer en mitad de un taller y
  /// creer que se ha perdido todo es un susto evitable.
  Future<bool> _confirmarSalida(AuditoriaState state) async {
    if (state.resultado.completa) return true;

    final pendientes = state.preguntas.length -
        state.respuestas.values.where((r) => r.respondida).length;

    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la auditoría'),
        content: Text(
          'Quedan $pendientes preguntas por responder.\n\nLo contestado se '
          'guarda y podrás continuar desde «Auditorías» cuando quieras.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir aquí')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salir')),
        ],
      ),
    );
    return salir ?? false;
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

    final filtro = _busqueda.text.trim().toLowerCase();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (yaSalio, _) async {
        if (yaSalio) return;
        if (await _confirmarSalida(state) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: _buscando
            ? TextField(
                controller: _busqueda,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Buscar en las preguntas…',
                  border: InputBorder.none,
                ),
              )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.centroNombre, style: const TextStyle(fontSize: 16)),
            Text(_fecha(state.fecha),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _buscando ? 'Cerrar búsqueda' : 'Buscar',
            icon: Icon(_buscando ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _buscando = !_buscando;
              if (!_buscando) _busqueda.clear();
            }),
          ),
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
        bottom: filtro.isNotEmpty ? null : TabBar(
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
      // Con búsqueda activa se deja de pintar por pestañas: lo que se quiere
      // entonces es ver los resultados de todas las áreas a la vez.
      body: filtro.isNotEmpty
          ? _Resultados(filtro: filtro)
          : TabBarView(
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

/// Resultados de la búsqueda, planos y de todas las áreas a la vez.
///
/// Con 47 preguntas repartidas en siete pestañas, localizar una concreta
/// obligaba a recordar en qué área estaba. Buscar por texto lo resuelve.
class _Resultados extends ConsumerWidget {
  const _Resultados({required this.filtro});

  final String filtro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditoriaControllerProvider);
    final porCodigo = {for (final a in state.areas) a.codigo: a};

    final encontradas = state.preguntas.where((p) {
      final area = porCodigo[p.areaCodigo]?.nombre ?? '';
      return '${p.texto} ${p.ayuda ?? ''} ${p.bloque} $area'
          .toLowerCase()
          .contains(filtro);
    }).toList();

    if (encontradas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Ninguna pregunta contiene «$filtro».',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            '${encontradas.length} pregunta${encontradas.length == 1 ? '' : 's'}',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline),
          ),
        ),
        for (final p in encontradas) ...[
          // Se indica el área porque aquí se mezclan todas y sin ese dato
          // no se sabe qué se está respondiendo.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              (porCodigo[p.areaCodigo]?.nombre ?? '').toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: porCodigo[p.areaCodigo]?.color,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          PreguntaCard(
            pregunta: p,
            colorArea: porCodigo[p.areaCodigo]?.color ?? Colors.blueGrey,
          ),
        ],
      ],
    );
  }
}
