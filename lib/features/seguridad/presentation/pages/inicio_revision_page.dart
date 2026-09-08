import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../shared/widgets/error_datos.dart';
import '../../../centros/domain/entities/centro.dart';
import '../providers/revision_controller.dart';

/// Paso previo al checklist: qué centro, qué día y quién revisa.
///
/// Deliberadamente más simple que `InicioAuditoriaPage`: una sola área no
/// necesita un responsable por área, y sin firma manuscrita no hace falta
/// pedir el nombre del gerente.
class InicioRevisionPage extends ConsumerStatefulWidget {
  const InicioRevisionPage({super.key});

  @override
  ConsumerState<InicioRevisionPage> createState() => _InicioRevisionPageState();
}

class _InicioRevisionPageState extends ConsumerState<InicioRevisionPage> {
  Centro? _centro;
  DateTime _fecha = DateTime.now();
  bool _creando = false;

  @override
  Widget build(BuildContext context) {
    final centros = ref.watch(centrosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva revisión de seguridad')),
      body: centros.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorDatos(error: e, queSeIntentaba: 'los centros'),
        data: (lista) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _Titulo('Centro'),
            if (lista.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Todavía no hay centros dados de alta'),
                  subtitle: Text('Da de alta un centro desde la pantalla principal.'),
                ),
              ),
            for (final c in lista)
              ListTile(
                selected: _centro?.id == c.id,
                onTap: () => setState(() => _centro = c),
                leading: Icon(
                  _centro?.id == c.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _centro?.id == c.id
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(c.nombre),
              ),
            const Divider(height: 32),
            const _Titulo('Fecha'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_formatear(_fecha)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _elegirFecha,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _centro == null || _creando ? null : _comenzar,
              icon: _creando
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: const Text('Comenzar revisión'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(_fecha.year - 2),
      lastDate: DateTime(_fecha.year + 1),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _comenzar() async {
    final centro = _centro;
    if (centro == null) return;
    setState(() => _creando = true);

    try {
      final plantilla = await ref.read(plantillaSeguridadRepositoryProvider).cargar();

      final revision = await ref.read(revisionSeguridadRepositoryProvider).crear(
            centroId: centro.id,
            centroNombre: centro.nombre,
            plantillaId: plantilla.id,
            plantillaVersion: plantilla.version,
            plantillaNombre: plantilla.nombre,
            fecha: _fecha,
            evaluadorUid: ref.read(auditorUidProvider),
            evaluadorNombre: ref.read(auditorNombreProvider),
          );

      ref.read(revisionSeguridadActualProvider.notifier).state = revision;
      ref.read(sesionSeguridadAbiertaProvider.notifier).state = RevisionState.desde(
        revisionId: revision.id,
        centroNombre: centro.nombre,
        fecha: _fecha,
        preguntas: plantilla.preguntas,
        pesosArea: plantilla.pesosEfectivos,
      );

      if (mounted) Navigator.of(context).pushReplacementNamed('/seguridad/revision');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo iniciar: $e')));
      }
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  static String _formatear(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700)),
      );
}
