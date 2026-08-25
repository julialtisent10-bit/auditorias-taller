import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../shared/area_vista.dart';
import '../../../centros/domain/entities/centro.dart';
import '../../../plantillas/domain/entities/plantilla.dart';
import '../providers/auditoria_controller.dart';

/// Paso previo: qué centro, qué día y quién está delante en cada área.
class InicioAuditoriaPage extends ConsumerStatefulWidget {
  const InicioAuditoriaPage({super.key});

  @override
  ConsumerState<InicioAuditoriaPage> createState() => _InicioAuditoriaPageState();
}

class _InicioAuditoriaPageState extends ConsumerState<InicioAuditoriaPage> {
  Centro? _centro;
  DateTime _fecha = DateTime.now();
  /// Un campo por área más el gerente. Se crean cuando llega la plantilla:
  /// las áreas ya no están fijadas en el código y cada cuestionario trae
  /// las suyas.
  final _responsables = <String, TextEditingController>{
    'gerente': TextEditingController(),
  };
  bool _creando = false;

  void _prepararCampos(List<AreaPlantilla> areas) {
    for (final a in areas) {
      _responsables.putIfAbsent(a.codigo, TextEditingController.new);
    }
  }

  @override
  void dispose() {
    for (final c in _responsables.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Al elegir centro se precargan los responsables de la última visita:
  /// en un taller la plantilla de personal cambia poco y ahorra teclear.
  void _seleccionar(Centro centro) {
    setState(() => _centro = centro);
    for (final entrada in centro.responsables.entries) {
      _responsables[entrada.key]?.text = entrada.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final centros = ref.watch(centrosProvider);
    final plantilla = ref.watch(plantillaProvider(null));

    // Sin plantilla no se puede saber qué responsables pedir.
    if (plantilla.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nueva auditoría')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (plantilla.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nueva auditoría')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
                'No se pudo cargar el cuestionario:\n${plantilla.error}',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    _prepararCampos(plantilla.value!.areas);
    final areasVista = AreaVista.listaDesde(plantilla.value!.areas);

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva auditoría')),
      body: centros.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('No se pudieron cargar los centros:\n$e')),
        data: (lista) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _Titulo('Centro'),
            if (lista.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Todavía no hay centros dados de alta'),
                  subtitle: Text('Crea el primero para poder auditarlo.'),
                ),
              ),
            // ListTile en lugar de RadioListTile: los parámetros `groupValue`
            // y `onChanged` del radio quedaron deprecados en favor de un
            // ancestro RadioGroup, y para una lista de media docena de
            // centros no compensa montar esa maquinaria.
            for (final c in lista)
              ListTile(
                selected: _centro?.id == c.id,
                onTap: () => _seleccionar(c),
                leading: Icon(
                  _centro?.id == c.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _centro?.id == c.id
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(c.nombre),
                subtitle: Text(
                  c.resumen.ultimaPuntuacion == null
                      ? 'Sin auditorías previas'
                      : 'Última: ${c.resumen.ultimaPuntuacion!.toStringAsFixed(1)}%',
                ),
              ),
            TextButton.icon(
              onPressed: _nuevoCentro,
              icon: const Icon(Icons.add),
              label: const Text('Dar de alta un centro'),
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
            const Divider(height: 32),
            const _Titulo('Responsables presentes'),
            const Text(
              'Se imprimen en el informe junto al resultado de su área.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            for (final area in areasVista)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _responsables[area.codigo],
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: area.nombre,
                    prefixIcon: Icon(area.icono, color: area.color),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            TextField(
              controller: _responsables['gerente'],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Gerente del centro (firma el informe)',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _centro == null || _creando ? null : _comenzar,
              icon: _creando
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: const Text('Comenzar auditoría'),
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

  Future<void> _nuevoCentro() async {
    final nombre = TextEditingController();
    final poblacion = TextEditingController();

    final crear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo centro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombre,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: poblacion,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Población'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );

    if (crear == true && nombre.text.trim().isNotEmpty) {
      final centro = await ref
          .read(centroRepositoryProvider)
          .crear(nombre: nombre.text, poblacion: poblacion.text);
      if (mounted) _seleccionar(centro);
    }
    nombre.dispose();
    poblacion.dispose();
  }

  Future<void> _comenzar() async {
    final centro = _centro;
    if (centro == null) return;
    setState(() => _creando = true);

    try {
      final plantilla =
          await ref.read(plantillaRepositoryProvider).cargar(plantillaId: centro.plantillaPorDefecto);

      final responsables = {
        for (final e in _responsables.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      };

      final auditoria = await ref.read(auditoriaRepositoryProvider).crear(
            centroId: centro.id,
            centroNombre: centro.nombre,
            plantillaId: plantilla.id,
            plantillaVersion: plantilla.version,
            fecha: _fecha,
            auditorUid: ref.read(auditorUidProvider),
            auditorNombre: ref.read(auditorNombreProvider),
            responsables: responsables,
          );

      // Se guardan en el centro para precargarlos la próxima vez.
      await ref
          .read(centroRepositoryProvider)
          .actualizarResponsables(centro.id, responsables);

      ref.read(auditoriaActualProvider.notifier).state = auditoria;
      ref.read(sesionAbiertaProvider.notifier).state = AuditoriaState.desde(
        auditoriaId: auditoria.id,
        centroNombre: centro.nombre,
        fecha: _fecha,
        preguntas: plantilla.preguntas,
        pesosArea: plantilla.pesosArea,
        areas: AreaVista.listaDesde(plantilla.areas),
      );

      if (mounted) Navigator.of(context).pushReplacementNamed('/auditoria');
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
