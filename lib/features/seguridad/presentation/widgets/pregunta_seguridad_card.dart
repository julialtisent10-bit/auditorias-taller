import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auditoria/domain/entities/evidencia.dart';
import '../../../auditoria/domain/entities/pregunta.dart';
import '../../../auditoria/domain/entities/respuesta.dart';
import '../../../auditoria/presentation/widgets/pregunta_card.dart'
    show SelectorRespuesta, BotonEvidencia, TiraEvidencias;
import '../providers/revision_controller.dart';

/// Tarjeta de una pregunta del checklist de seguridad: selector Sí/No,
/// comentario y foto opcionales.
///
/// No es `PreguntaCard` (la del cuestionario de postventa) porque esa lee y
/// escribe contra `auditoriaControllerProvider`, atado a la colección
/// `auditorias`. Reutiliza en su lugar las partes realmente genéricas de esa
/// tarjeta —el selector de respuesta, el botón de cámara y la tira de
/// miniaturas— e implementa el resto (el comentario, el guardado) contra el
/// controlador de este módulo.
class PreguntaSeguridadCard extends ConsumerStatefulWidget {
  const PreguntaSeguridadCard({super.key, required this.pregunta});

  final Pregunta pregunta;

  @override
  ConsumerState<PreguntaSeguridadCard> createState() => _PreguntaSeguridadCardState();
}

class _PreguntaSeguridadCardState extends ConsumerState<PreguntaSeguridadCard> {
  late final TextEditingController _comentario;
  bool _mostrarComentario = false;

  @override
  void initState() {
    super.initState();
    final inicial = ref
            .read(revisionControllerProvider)
            .respuestaDe(widget.pregunta.id)
            ?.comentario ??
        '';
    _comentario = TextEditingController(text: inicial);
    _mostrarComentario = inicial.isNotEmpty;
  }

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(revisionControllerProvider.notifier);
    final Respuesta? respuesta =
        ref.watch(revisionControllerProvider.select((s) => s.respuestaDe(widget.pregunta.id)));
    final valor = respuesta?.valor;
    final evidencias = respuesta?.evidencias ?? const <Evidencia>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.pregunta.texto, style: const TextStyle(fontSize: 15, height: 1.3)),
            const SizedBox(height: 12),
            SelectorRespuesta(
              valor: valor,
              permiteNA: widget.pregunta.permiteNA,
              permiteParcial: widget.pregunta.permiteParcial,
              onSeleccionar: (v) => controller.responder(widget.pregunta, v),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _mostrarComentario = !_mostrarComentario),
                  icon: const Icon(Icons.notes, size: 18),
                  label: Text(_comentario.text.isEmpty ? 'Comentario' : 'Comentario ✓'),
                ),
                const Spacer(),
                BotonEvidencia(
                  habilitado: evidencias.length < Respuesta.maxEvidencias,
                  onElegir: (desdeCamara) =>
                      controller.anadirEvidencia(widget.pregunta, desdeCamara: desdeCamara),
                ),
                Text('${evidencias.length}/${Respuesta.maxEvidencias}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            if (evidencias.isNotEmpty)
              TiraEvidencias(
                evidencias: evidencias,
                onEliminar: (e) => controller.quitarEvidencia(widget.pregunta, e),
              ),
            if (_mostrarComentario)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: TextField(
                  controller: _comentario,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Observaciones, ubicación exacta, acción propuesta…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (t) => controller.comentar(widget.pregunta, t),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
