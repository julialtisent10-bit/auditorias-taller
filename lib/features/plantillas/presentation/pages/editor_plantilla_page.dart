import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../auditoria/domain/entities/pregunta.dart';
import '../../../auditoria/presentation/pages/cuestionario_page.dart';
import '../../data/repositories/plantilla_repository.dart';
import '../../domain/entities/plantilla.dart';
import 'editor_pregunta_page.dart';

/// Editor del cuestionario: permite cambiar las preguntas sin recompilar.
///
/// Trabaja siempre contra Firestore, nunca contra el asset empaquetado. Si el
/// cuestionario todavía no se ha subido, lo primero que ofrece es subirlo:
/// editar el asset exigiría un despliegue y no tendría sentido hacerlo desde
/// el móvil.
class EditorPlantillaPage extends ConsumerStatefulWidget {
  const EditorPlantillaPage({super.key});

  @override
  ConsumerState<EditorPlantillaPage> createState() => _EditorPlantillaPageState();
}

class _EditorPlantillaPageState extends ConsumerState<EditorPlantillaPage> {
  Future<Plantilla>? _futuro;
  bool _sembrando = false;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() {
    final repo = ref.read(plantillaRepositoryProvider);
    repo.invalidarCache();
    setState(() => _futuro = repo.cargar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar cuestionario')),
      body: FutureBuilder<Plantilla>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Mensaje(
              icono: Icons.error_outline,
              titulo: 'No se pudo cargar el cuestionario',
              detalle: '${snap.error}',
            );
          }

          final plantilla = snap.data!;
          return _Contenido(
            plantilla: plantilla,
            sembrando: _sembrando,
            onSembrar: () => _sembrar(plantilla),
            onCambio: _recargar,
          );
        },
      ),
    );
  }

  Future<void> _sembrar(Plantilla plantilla) async {
    setState(() => _sembrando = true);
    try {
      await ref.read(plantillaRepositoryProvider).sembrarEnFirestore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuestionario subido. Ya puedes editarlo.')),
      );
      _recargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo subir: $e')));
    } finally {
      if (mounted) setState(() => _sembrando = false);
    }
  }
}

class _Contenido extends ConsumerStatefulWidget {
  const _Contenido({
    required this.plantilla,
    required this.sembrando,
    required this.onSembrar,
    required this.onCambio,
  });

  final Plantilla plantilla;
  final bool sembrando;
  final VoidCallback onSembrar;
  final VoidCallback onCambio;

  @override
  ConsumerState<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends ConsumerState<_Contenido> {
  // La comprobacion se lanza UNA vez y se guarda. Creandola dentro de build()
  // se dispararia una consulta nueva en cada reconstruccion, con su parpadeo
  // de indicador de carga y su lectura de Firestore cada vez.
  late Future<bool> _editable;

  @override
  void initState() {
    super.initState();
    _editable =
        ref.read(plantillaRepositoryProvider).esEditable(widget.plantilla.id);
  }

  @override
  void didUpdateWidget(_Contenido anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.plantilla.id != widget.plantilla.id) {
      _editable =
          ref.read(plantillaRepositoryProvider).esEditable(widget.plantilla.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _editable,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data != true) {
          return _PrimeraVez(
              sembrando: widget.sembrando, onSembrar: widget.onSembrar);
        }
        return _Listado(
            plantilla: widget.plantilla, onCambio: widget.onCambio);
      },
    );
  }
}

/// Estado inicial: el cuestionario solo existe dentro de la aplicación.
class _PrimeraVez extends StatelessWidget {
  const _PrimeraVez({required this.sembrando, required this.onSembrar});

  final bool sembrando;
  final VoidCallback onSembrar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 56),
            const SizedBox(height: 16),
            Text('Preparar el cuestionario para editarlo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text(
              'Ahora mismo las preguntas viven dentro de la aplicación, así que '
              'cambiarlas exigiría publicar una versión nueva.\n\n'
              'Al subirlas a la nube pasan a ser editables desde aquí, y los '
              'cambios llegan al instante a todos los auditores.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: sembrando ? null : onSembrar,
              icon: sembrando
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: const Text('Subir cuestionario'),
            ),
            const SizedBox(height: 16),
            Text(
              'Las auditorías ya cerradas no se ven afectadas: cada una guarda '
              'una copia de las preguntas tal y como estaban ese día.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _Listado extends ConsumerStatefulWidget {
  const _Listado({required this.plantilla, required this.onCambio});

  final Plantilla plantilla;
  final VoidCallback onCambio;

  @override
  ConsumerState<_Listado> createState() => _ListadoState();
}

class _ListadoState extends ConsumerState<_Listado> {
  Future<List<PreguntaEditable>>? _preguntas;

  /// Ids seleccionados. Vacío = modo normal; con algo dentro = modo selección.
  final Set<String> _seleccion = {};
  bool _mostrarRetiradas = false;
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() {
    setState(() {
      _seleccion.clear();
      _preguntas = ref
          .read(plantillaRepositoryProvider)
          .cargarParaEditor(widget.plantilla.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PreguntaEditable>>(
      future: _preguntas,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Mensaje(
            icono: Icons.error_outline,
            titulo: 'No se pudieron cargar las preguntas',
            detalle: '${snap.error}',
          );
        }

        final todas = snap.data!;
        final retiradas = todas.where((p) => !p.activa).length;

        return DefaultTabController(
          length: areasAuditoria.length,
          child: Column(
            children: [
              _BarraHerramientas(
                seleccionadas: _seleccion.length,
                retiradas: retiradas,
                mostrarRetiradas: _mostrarRetiradas,
                trabajando: _trabajando,
                onAlternarRetiradas: () =>
                    setState(() => _mostrarRetiradas = !_mostrarRetiradas),
                onCancelarSeleccion: () => setState(_seleccion.clear),
                onRetirarSeleccion: _retirarSeleccionadas,
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final a in areasAuditoria)
                    Tab(
                      icon: Icon(a.icono, size: 18),
                      child: Text(
                        '${a.nombre} '
                        '(${todas.where((p) => p.activa && p.pregunta.areaCodigo == a.codigo).length})',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final a in areasAuditoria)
                      _PreguntasDeArea(
                        plantillaId: widget.plantilla.id,
                        area: a,
                        preguntas: todas
                            .where((p) => p.pregunta.areaCodigo == a.codigo)
                            .toList(),
                        mostrarRetiradas: _mostrarRetiradas,
                        seleccion: _seleccion,
                        onAlternarSeleccion: (id) => setState(() {
                          if (!_seleccion.remove(id)) _seleccion.add(id);
                        }),
                        onCambio: () {
                          _recargar();
                          widget.onCambio();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _retirarSeleccionadas() async {
    final cuantas = _seleccion.length;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirar $cuantas pregunta${cuantas == 1 ? '' : 's'}'),
        content: const Text(
          'Dejarán de aparecer en las auditorías nuevas.\n\n'
          'Podrás recuperarlas desde «Ver retiradas», y las auditorías ya '
          'hechas las conservan.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirar')),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _trabajando = true);
    try {
      await ref
          .read(plantillaRepositoryProvider)
          .desactivarVarias(widget.plantilla.id, _seleccion.toList());
      _recargar();
      widget.onCambio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo retirar: $e')));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }
}

/// Barra superior del editor. Cambia de aspecto según haya o no selección,
/// para que quede claro que el toque prolongado ha entrado en otro modo.
class _BarraHerramientas extends StatelessWidget {
  const _BarraHerramientas({
    required this.seleccionadas,
    required this.retiradas,
    required this.mostrarRetiradas,
    required this.trabajando,
    required this.onAlternarRetiradas,
    required this.onCancelarSeleccion,
    required this.onRetirarSeleccion,
  });

  final int seleccionadas;
  final int retiradas;
  final bool mostrarRetiradas;
  final bool trabajando;
  final VoidCallback onAlternarRetiradas;
  final VoidCallback onCancelarSeleccion;
  final VoidCallback onRetirarSeleccion;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    if (seleccionadas > 0) {
      return Material(
        color: esquema.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancelar selección',
                onPressed: trabajando ? null : onCancelarSeleccion,
              ),
              Expanded(
                child: Text('$seleccionadas seleccionada'
                    '${seleccionadas == 1 ? '' : 's'}'),
              ),
              TextButton.icon(
                onPressed: trabajando ? null : onRetirarSeleccion,
                icon: trabajando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Retirar'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mantén pulsada una pregunta para seleccionar varias',
              style: TextStyle(fontSize: 11, color: esquema.outline),
            ),
          ),
          if (retiradas > 0)
            TextButton.icon(
              onPressed: onAlternarRetiradas,
              icon: Icon(
                  mostrarRetiradas ? Icons.visibility_off : Icons.visibility,
                  size: 16),
              label: Text(
                mostrarRetiradas ? 'Ocultar retiradas' : 'Ver retiradas ($retiradas)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreguntasDeArea extends ConsumerWidget {
  const _PreguntasDeArea({
    required this.plantillaId,
    required this.area,
    required this.preguntas,
    required this.mostrarRetiradas,
    required this.seleccion,
    required this.onAlternarSeleccion,
    required this.onCambio,
  });

  final String plantillaId;
  final AreaTab area;
  final List<PreguntaEditable> preguntas;
  final bool mostrarRetiradas;
  final Set<String> seleccion;
  final ValueChanged<String> onAlternarSeleccion;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activas = preguntas.where((p) => p.activa).toList();
    final retiradas = preguntas.where((p) => !p.activa).toList();

    final bloques = <String, List<PreguntaEditable>>{};
    for (final p in activas) {
      bloques.putIfAbsent(p.pregunta.bloque, () => []).add(p);
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          for (final entrada in bloques.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text(
                entrada.key.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: area.color,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final p in entrada.value)
              _FilaPregunta(
                editable: p,
                plantillaId: plantillaId,
                seleccionada: seleccion.contains(p.pregunta.id),
                modoSeleccion: seleccion.isNotEmpty,
                onAlternarSeleccion: () => onAlternarSeleccion(p.pregunta.id),
                onCambio: onCambio,
              ),
          ],
          if (mostrarRetiradas && retiradas.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 28, 4, 6),
              child: Text(
                'RETIRADAS DEL CUESTIONARIO',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final p in retiradas)
              _FilaPregunta(
                editable: p,
                plantillaId: plantillaId,
                seleccionada: false,
                modoSeleccion: false,
                onAlternarSeleccion: () {},
                onCambio: onCambio,
              ),
          ],
        ],
      ),
      floatingActionButton: seleccion.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add_${area.codigo}',
              onPressed: () => _nueva(context, activas),
              icon: const Icon(Icons.add),
              label: const Text('Nueva pregunta'),
            ),
    );
  }

  Future<void> _nueva(BuildContext context, List<PreguntaEditable> activas) async {
    // Se coloca al final del área y hereda el bloque de la última, que es lo
    // que se quiere casi siempre al ir añadiendo preguntas seguidas.
    final ultima = activas.isEmpty ? null : activas.last.pregunta;

    final nueva = Pregunta(
      id: 'q_${const Uuid().v4().substring(0, 8)}',
      areaCodigo: area.codigo,
      bloque: ultima?.bloque ?? 'General',
      orden: (ultima?.orden ?? 0) + 1,
      texto: '',
    );

    final guardada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditorPreguntaPage(
          pregunta: nueva,
          plantillaId: plantillaId,
          esNueva: true,
        ),
      ),
    );
    if (guardada == true) onCambio();
  }
}

class _FilaPregunta extends ConsumerWidget {
  const _FilaPregunta({
    required this.editable,
    required this.plantillaId,
    required this.seleccionada,
    required this.modoSeleccion,
    required this.onAlternarSeleccion,
    required this.onCambio,
  });

  final PreguntaEditable editable;
  final String plantillaId;
  final bool seleccionada;
  final bool modoSeleccion;
  final VoidCallback onAlternarSeleccion;
  final VoidCallback onCambio;

  Pregunta get pregunta => editable.pregunta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esquema = Theme.of(context).colorScheme;
    final retirada = !editable.activa;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: seleccionada ? esquema.secondaryContainer : null,
      child: ListTile(
        dense: true,
        onTap: modoSeleccion && !retirada ? onAlternarSeleccion : null,
        onLongPress: retirada ? null : onAlternarSeleccion,
        leading: modoSeleccion && !retirada
            ? Icon(seleccionada
                ? Icons.check_circle
                : Icons.radio_button_unchecked)
            : null,
        title: Text(
          pregunta.texto,
          style: TextStyle(
            fontSize: 13,
            color: retirada ? esquema.outline : null,
            decoration: retirada ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (retirada) const _Etiqueta('RETIRADA', alerta: true),
              _Etiqueta('peso ${pregunta.peso}'),
              if (pregunta.critica) const _Etiqueta('CRÍTICA', alerta: true),
              if (pregunta.permiteNA) const _Etiqueta('admite N/A'),
              if (pregunta.fotoObligatoriaSi.isNotEmpty)
                const _Etiqueta('exige foto'),
            ],
          ),
        ),
        trailing: modoSeleccion
            ? null
            : PopupMenuButton<String>(
                onSelected: (opcion) async {
                  switch (opcion) {
                    case 'editar':
                      final guardada = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => EditorPreguntaPage(
                            pregunta: pregunta,
                            plantillaId: plantillaId,
                          ),
                        ),
                      );
                      if (guardada == true) onCambio();
                    case 'quitar':
                      await _quitar(context, ref);
                    case 'restaurar':
                      await ref
                          .read(plantillaRepositoryProvider)
                          .reactivarPregunta(plantillaId, pregunta.id);
                      onCambio();
                  }
                },
                itemBuilder: (_) => retirada
                    ? const [
                        PopupMenuItem(
                            value: 'restaurar',
                            child: Text('Devolver al cuestionario')),
                      ]
                    : const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(
                            value: 'quitar',
                            child: Text('Retirar del cuestionario')),
                      ],
              ),
      ),
    );
  }

  Future<void> _quitar(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirar la pregunta'),
        content: const Text(
          'Dejará de aparecer en las auditorías nuevas.\n\n'
          'Podrás recuperarla desde «Ver retiradas», y las auditorías ya '
          'hechas la conservan.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirar')),
        ],
      ),
    );
    if (confirmado != true) return;

    await ref
        .read(plantillaRepositoryProvider)
        .desactivarPregunta(plantillaId, pregunta.id);
    onCambio();
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, {this.alerta = false});
  final String texto;
  final bool alerta;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: alerta
              ? Colors.red.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 10,
            fontWeight: alerta ? FontWeight.bold : FontWeight.normal,
            color: alerta ? Colors.red.shade400 : null,
          ),
        ),
      );
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.icono, required this.titulo, this.detalle});

  final IconData icono;
  final String titulo;
  final String? detalle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 48),
              const SizedBox(height: 12),
              Text(titulo, textAlign: TextAlign.center),
              if (detalle != null) ...[
                const SizedBox(height: 8),
                Text(detalle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ],
          ),
        ),
      );
}
