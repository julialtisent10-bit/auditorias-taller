import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../auditoria/domain/entities/pregunta.dart';
import '../../../auditoria/presentation/pages/cuestionario_page.dart';
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

class _Listado extends ConsumerWidget {
  const _Listado({required this.plantilla, required this.onCambio});

  final Plantilla plantilla;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: areasAuditoria.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final a in areasAuditoria)
                Tab(
                  icon: Icon(a.icono, size: 18),
                  child: Text(
                    '${a.nombre} '
                    '(${plantilla.preguntas.where((p) => p.areaCodigo == a.codigo).length})',
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
                    plantilla: plantilla,
                    area: a,
                    onCambio: onCambio,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreguntasDeArea extends ConsumerWidget {
  const _PreguntasDeArea({
    required this.plantilla,
    required this.area,
    required this.onCambio,
  });

  final Plantilla plantilla;
  final AreaTab area;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preguntas = plantilla.preguntas
        .where((p) => p.areaCodigo == area.codigo)
        .toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));

    // Agrupadas por bloque, respetando el orden ya calculado.
    final bloques = <String, List<Pregunta>>{};
    for (final p in preguntas) {
      bloques.putIfAbsent(p.bloque, () => []).add(p);
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
                pregunta: p,
                plantillaId: plantilla.id,
                onCambio: onCambio,
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_${area.codigo}',
        onPressed: () => _nueva(context, ref, preguntas),
        icon: const Icon(Icons.add),
        label: const Text('Nueva pregunta'),
      ),
    );
  }

  Future<void> _nueva(
      BuildContext context, WidgetRef ref, List<Pregunta> existentes) async {
    // Se coloca al final del área y hereda el bloque de la última, que es lo
    // que se quiere el 90 % de las veces al ir añadiendo preguntas seguidas.
    final siguiente = existentes.isEmpty ? 1 : existentes.last.orden + 1;

    final plantilla = Pregunta(
      id: 'q_${const Uuid().v4().substring(0, 8)}',
      areaCodigo: area.codigo,
      bloque: existentes.isEmpty ? 'General' : existentes.last.bloque,
      orden: siguiente,
      texto: '',
    );

    final guardada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditorPreguntaPage(
          pregunta: plantilla,
          plantillaId: this.plantilla.id,
          esNueva: true,
        ),
      ),
    );
    if (guardada == true) onCambio();
  }
}

class _FilaPregunta extends ConsumerWidget {
  const _FilaPregunta({
    required this.pregunta,
    required this.plantillaId,
    required this.onCambio,
  });

  final Pregunta pregunta;
  final String plantillaId;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(pregunta.texto, style: const TextStyle(fontSize: 13)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            children: [
              _Etiqueta('peso ${pregunta.peso}'),
              if (pregunta.critica) const _Etiqueta('CRÍTICA', alerta: true),
              if (pregunta.permiteNA) const _Etiqueta('admite N/A'),
              if (pregunta.fotoObligatoriaSi.isNotEmpty)
                const _Etiqueta('exige foto'),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (opcion) async {
            if (opcion == 'editar') {
              final guardada = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => EditorPreguntaPage(
                    pregunta: pregunta,
                    plantillaId: plantillaId,
                  ),
                ),
              );
              if (guardada == true) onCambio();
            } else if (opcion == 'quitar') {
              await _confirmarQuitar(context, ref);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(value: 'quitar', child: Text('Quitar del cuestionario')),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarQuitar(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar la pregunta'),
        content: const Text(
          'Dejará de aparecer en las auditorías nuevas.\n\n'
          'Las auditorías ya hechas la conservan, porque cada una guarda su '
          'propia copia de las preguntas.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quitar')),
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
