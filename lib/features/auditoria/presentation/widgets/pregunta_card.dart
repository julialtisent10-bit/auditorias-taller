
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/evidencia.dart';
import '../../domain/entities/pregunta.dart';
import '../../domain/entities/respuesta.dart';
import '../../domain/entities/valor_respuesta.dart';
import '../providers/auditoria_controller.dart';

/// Tarjeta de una pregunta: selector de 4 valores, comentario y hasta
/// 2 evidencias fotográficas.
class PreguntaCard extends ConsumerStatefulWidget {
  const PreguntaCard({super.key, required this.pregunta, required this.colorArea});

  final Pregunta pregunta;
  final Color colorArea;

  @override
  ConsumerState<PreguntaCard> createState() => _PreguntaCardState();
}

class _PreguntaCardState extends ConsumerState<PreguntaCard> {
  late final TextEditingController _comentario;
  bool _mostrarComentario = false;

  @override
  void initState() {
    super.initState();
    final inicial = ref
            .read(auditoriaControllerProvider)
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
    final controller = ref.read(auditoriaControllerProvider.notifier);
    final Respuesta? respuesta =
        ref.watch(auditoriaControllerProvider.select((s) => s.respuestaDe(widget.pregunta.id)));

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.pregunta.critica)
                  const Padding(
                    padding: EdgeInsets.only(right: 6, top: 2),
                    child: Icon(Icons.priority_high, size: 18, color: Colors.redAccent),
                  ),
                Expanded(
                  child: Text(widget.pregunta.texto,
                      style: const TextStyle(fontSize: 15, height: 1.3)),
                ),
                _ChipPeso(peso: widget.pregunta.peso),
              ],
            ),
            if (widget.pregunta.ayuda != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.pregunta.ayuda!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
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
                  // El controller aplica debounce; no escribe por cada tecla.
                  onChanged: (t) => controller.comentar(widget.pregunta, t),
                ),
              ),
            if (evidencias.isNotEmpty)
              TiraEvidencias(
                evidencias: evidencias,
                onEliminar: (e) => controller.quitarEvidencia(widget.pregunta, e),
              ),
          ],
        ),
      ),
    );
  }
}

/// Selector de respuesta compartido: lo usa tanto el cuestionario de
/// postventa (a través de [PreguntaCard]) como el módulo de seguridad, que
/// tiene su propia tarjeta de pregunta porque no depende del controlador de
/// auditoría. Es público a propósito para que ese otro módulo lo importe en
/// lugar de reconstruir la misma lógica de chips y colores por su cuenta.
class SelectorRespuesta extends StatelessWidget {
  const SelectorRespuesta({
    super.key,
    required this.valor,
    required this.permiteNA,
    this.permiteParcial = true,
    required this.onSeleccionar,
  });

  final ValorRespuesta? valor;
  final bool permiteNA;

  /// false oculta "Cumple parcialmente": el cuestionario de seguridad es
  /// estrictamente Sí/No y esa opción no corresponde a ninguna respuesta
  /// válida de su formulario original.
  final bool permiteParcial;
  final ValueChanged<ValorRespuesta> onSeleccionar;

  static const _colores = {
    ValorRespuesta.cumple: Color(0xFF2E7D32),
    ValorRespuesta.parcial: Color(0xFFF9A825),
    ValorRespuesta.noCumple: Color(0xFFC62828),
    ValorRespuesta.noAplica: Color(0xFF757575),
  };

  static const _etiquetasCortas = {
    ValorRespuesta.cumple: 'Cumple',
    ValorRespuesta.parcial: 'Parcial',
    ValorRespuesta.noCumple: 'No cumple',
    ValorRespuesta.noAplica: 'N/A',
  };

  @override
  Widget build(BuildContext context) {
    final opciones = ValorRespuesta.values
        .where((v) => permiteNA || v != ValorRespuesta.noAplica)
        .where((v) => permiteParcial || v != ValorRespuesta.parcial)
        .toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in opciones)
          ChoiceChip(
            label: Text(v == ValorRespuesta.noAplica
                ? 'N/A'
                : '${v.puntuacion} · ${_etiquetasCortas[v]}'),
            selected: valor == v,
            showCheckmark: false,
            selectedColor: _colores[v],
            labelStyle: TextStyle(
              color: valor == v ? Colors.white : _colores[v],
              fontWeight: valor == v ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide(color: _colores[v]!.withValues(alpha: 0.6)),
            // Toque sobre el chip ya activo = deseleccionar (lo resuelve el controller).
            onSelected: (_) => onSeleccionar(v),
          ),
      ],
    );
  }
}

class _ChipPeso extends StatelessWidget {
  const _ChipPeso({required this.peso});
  final int peso;

  @override
  Widget build(BuildContext context) {
    const etiquetas = {3: 'CRÍTICA', 2: 'IMPORTANTE', 1: 'NORMAL'};
    if (peso <= 1) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: peso >= 3 ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        etiquetas[peso] ?? 'x$peso',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: peso >= 3 ? Colors.red.shade700 : Colors.orange.shade800,
        ),
      ),
    );
  }
}

/// Botón de añadir foto, compartido con el módulo de seguridad por el mismo
/// motivo que [SelectorRespuesta]: es la parte genérica (cámara/galería, el
/// límite de evidencias lo decide quien lo usa), sin nada específico de
/// auditorías de postventa.
class BotonEvidencia extends StatelessWidget {
  const BotonEvidencia({super.key, required this.habilitado, required this.onElegir});

  final bool habilitado;

  /// true = cámara, false = galería.
  final ValueChanged<bool> onElegir;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      enabled: habilitado,
      tooltip: 'Añadir evidencia',
      onSelected: onElegir,
      itemBuilder: (_) => const [
        PopupMenuItem(value: true, child: ListTile(leading: Icon(Icons.photo_camera), title: Text('Tomar foto'))),
        PopupMenuItem(value: false, child: ListTile(leading: Icon(Icons.photo_library), title: Text('Elegir de galería'))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Icon(
          Icons.add_a_photo_outlined,
          size: 22,
          color: habilitado
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade400,
        ),
      ),
    );
  }
}

/// Tira horizontal de miniaturas, compartida con el módulo de seguridad.
class TiraEvidencias extends StatelessWidget {
  const TiraEvidencias({super.key, required this.evidencias, required this.onEliminar});

  final List<Evidencia> evidencias;
  final ValueChanged<Evidencia> onEliminar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: evidencias.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = evidencias[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                // Siempre desde memoria local: la miniatura tiene que verse
                // aunque no haya red, que es la situación normal en el taller.
                child: e.miniatura != null
                    ? Image.memory(e.miniatura!,
                        width: 76, height: 76, fit: BoxFit.cover)
                    : Container(
                        width: 76,
                        height: 76,
                        color: Colors.black12,
                        child: const Icon(Icons.image_outlined, size: 20),
                      ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: GestureDetector(
                  onTap: () => onEliminar(e),
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
