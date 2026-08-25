import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../auditoria/domain/entities/pregunta.dart';
import '../../../auditoria/domain/entities/valor_respuesta.dart';

/// Formulario de una pregunta del cuestionario.
class EditorPreguntaPage extends ConsumerStatefulWidget {
  const EditorPreguntaPage({
    super.key,
    required this.pregunta,
    required this.plantillaId,
    this.esNueva = false,
  });

  final Pregunta pregunta;
  final String plantillaId;
  final bool esNueva;

  @override
  ConsumerState<EditorPreguntaPage> createState() => _EditorPreguntaPageState();
}

class _EditorPreguntaPageState extends ConsumerState<EditorPreguntaPage> {
  late final TextEditingController _texto =
      TextEditingController(text: widget.pregunta.texto);
  late final TextEditingController _ayuda =
      TextEditingController(text: widget.pregunta.ayuda ?? '');
  late final TextEditingController _bloque =
      TextEditingController(text: widget.pregunta.bloque);
  late final TextEditingController _orden =
      TextEditingController(text: widget.pregunta.orden.toString());

  late int _peso = widget.pregunta.peso;
  late bool _critica = widget.pregunta.critica;
  late bool _permiteNA = widget.pregunta.permiteNA;
  late Set<ValorRespuesta> _exigeFoto = widget.pregunta.fotoObligatoriaSi.toSet();

  bool _guardando = false;

  @override
  void dispose() {
    _texto.dispose();
    _ayuda.dispose();
    _bloque.dispose();
    _orden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.esNueva ? 'Nueva pregunta' : 'Editar pregunta'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          TextField(
            controller: _texto,
            minLines: 2,
            maxLines: 5,
            autofocus: widget.esNueva,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Pregunta',
              helperText: 'Redáctala como algo comprobable, no como una opinión',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ayuda,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Ayuda para el auditor (opcional)',
              helperText: 'Qué mirar exactamente, dónde comprobarlo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _bloque,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Bloque',
                    helperText: 'Agrupa preguntas bajo una cabecera',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _orden,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Orden',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Titulo('Peso en la puntuación'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Normal')),
              ButtonSegment(value: 2, label: Text('Importante')),
              ButtonSegment(value: 3, label: Text('Crítica')),
            ],
            selected: {_peso},
            onSelectionChanged: (s) => setState(() => _peso = s.first),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _critica,
            onChanged: (v) => setState(() => _critica = v),
            title: const Text('Incumplirla topa el área al 79 %'),
            subtitle: const Text(
              'Resérvalo para riesgo directo sobre personas. Si lo activas en '
              'muchas preguntas, casi ningún centro aprobará el área.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _permiteNA,
            onChanged: (v) => setState(() => _permiteNA = v),
            title: const Text('Permite marcar "No aplica"'),
            subtitle: const Text(
              'Actívalo solo si hay centros donde la pregunta no tenga sentido. '
              'Si se deja abierto, se usa para esquivar preguntas incómodas.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          const _Titulo('Exigir foto cuando la respuesta sea'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final v in [ValorRespuesta.noCumple, ValorRespuesta.parcial])
                FilterChip(
                  label: Text(v.etiqueta),
                  selected: _exigeFoto.contains(v),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _exigeFoto = {..._exigeFoto, v};
                    } else {
                      _exigeFoto = {..._exigeFoto}..remove(v);
                    }
                  }),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Sin foto, la auditoría no deja finalizar esa pregunta.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (_texto.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La pregunta no puede quedar vacía.')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final actualizada = widget.pregunta.copyWith(
        texto: _texto.text.trim(),
        ayuda: _ayuda.text,
        bloque: _bloque.text.trim().isEmpty ? 'General' : _bloque.text.trim(),
        orden: int.tryParse(_orden.text) ?? widget.pregunta.orden,
        peso: _peso,
        critica: _critica,
        permiteNA: _permiteNA,
        fotoObligatoriaSi: _exigeFoto.toList(),
      );

      await ref
          .read(plantillaRepositoryProvider)
          .guardarPregunta(widget.plantillaId, actualizada);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
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
