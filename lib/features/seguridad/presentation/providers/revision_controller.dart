import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../auditoria/domain/entities/evidencia.dart';
import '../../../auditoria/domain/entities/pregunta.dart';
import '../../../auditoria/domain/entities/respuesta.dart';
import '../../../auditoria/domain/entities/valor_respuesta.dart';
import '../../../auditoria/domain/usecases/calcular_puntuacion.dart';
import '../../domain/repositories/revision_seguridad_repository.dart';

/// Estado de una revisión de seguridad en curso.
///
/// Mirroring deliberado de `AuditoriaState`, incluidas las evidencias: la
/// foto sigue sin ser obligatoria nunca, pero sí opcional, igual que en
/// auditorías de postventa.
class RevisionState {
  const RevisionState({
    required this.revisionId,
    required this.centroNombre,
    required this.fecha,
    required this.preguntas,
    required this.respuestas,
    required this.pesosArea,
    required this.resultado,
    this.guardando = false,
  });

  factory RevisionState.desde({
    required String revisionId,
    required String centroNombre,
    required DateTime fecha,
    required List<Pregunta> preguntas,
    required Map<String, double> pesosArea,
    List<Respuesta> respuestasPrevias = const [],
  }) {
    final respuestas = {for (final r in respuestasPrevias) r.preguntaId: r};
    return RevisionState(
      revisionId: revisionId,
      centroNombre: centroNombre,
      fecha: fecha,
      preguntas: [...preguntas]..sort((a, b) => a.orden.compareTo(b.orden)),
      respuestas: respuestas,
      pesosArea: pesosArea,
      resultado: const CalcularPuntuacion(aplicarTopeCritica: false)(
        respuestas: respuestas.values.toList(),
        pesosArea: pesosArea,
      ),
    );
  }

  final String revisionId;
  final String centroNombre;
  final DateTime fecha;
  final List<Pregunta> preguntas;
  final Map<String, Respuesta> respuestas;
  final Map<String, double> pesosArea;
  final ResultadoAuditoria resultado;
  final bool guardando;

  Respuesta? respuestaDe(String preguntaId) => respuestas[preguntaId];

  bool get puedeFinalizar => resultado.completa;

  RevisionState copyWith({
    Map<String, Respuesta>? respuestas,
    ResultadoAuditoria? resultado,
    bool? guardando,
  }) =>
      RevisionState(
        revisionId: revisionId,
        centroNombre: centroNombre,
        fecha: fecha,
        preguntas: preguntas,
        respuestas: respuestas ?? this.respuestas,
        pesosArea: pesosArea,
        resultado: resultado ?? this.resultado,
        guardando: guardando ?? this.guardando,
      );
}

class RevisionController extends StateNotifier<RevisionState> {
  RevisionController(this._repo, RevisionState inicial) : super(inicial);

  final RevisionSeguridadRepository _repo;
  static const _calculo = CalcularPuntuacion(aplicarTopeCritica: false);

  /// Debounce por pregunta: escribir un comentario no debe disparar una
  /// escritura por pulsación de tecla.
  final Map<String, Timer> _debounces = {};

  void responder(Pregunta pregunta, ValorRespuesta valor) {
    final actual = state.respuestas[pregunta.id];
    // Segundo toque sobre el mismo valor = deseleccionar.
    final nuevoValor = actual?.valor == valor ? null : valor;
    _actualizar(
      pregunta,
      (r) => r.copyWith(valor: nuevoValor, respondidaEn: DateTime.now()),
      forzarValorNulo: nuevoValor == null,
      inmediato: true,
    );
  }

  void comentar(Pregunta pregunta, String texto) {
    _actualizar(pregunta, (r) => r.copyWith(comentario: texto));
  }

  Future<void> anadirEvidencia(Pregunta pregunta, {required bool desdeCamara}) async {
    final actual = _respuestaOVacia(pregunta);
    if (!actual.puedeAnadirEvidencia) return;

    final evidencia = await _repo.capturarEvidencia(
      revisionId: state.revisionId,
      preguntaId: pregunta.id,
      desdeCamara: desdeCamara,
    );
    if (evidencia == null) return; // captura cancelada
    _actualizar(
      pregunta,
      (r) => r.copyWith(evidencias: [...r.evidencias, evidencia]),
      inmediato: true,
    );
  }

  Future<void> quitarEvidencia(Pregunta pregunta, Evidencia evidencia) async {
    await _repo.eliminarEvidencia(state.revisionId, pregunta.id, evidencia);
    _actualizar(
      pregunta,
      (r) => r.copyWith(evidencias: r.evidencias.where((e) => e.id != evidencia.id).toList()),
      inmediato: true,
    );
  }

  Respuesta _respuestaOVacia(Pregunta p) =>
      state.respuestas[p.id] ??
      Respuesta(
        preguntaId: p.id,
        areaCodigo: p.areaCodigo,
        textoPregunta: p.texto,
        peso: p.peso,
        critica: p.critica,
      );

  void _actualizar(
    Pregunta pregunta,
    Respuesta Function(Respuesta) transformar, {
    bool inmediato = false,
    bool forzarValorNulo = false,
  }) {
    var nueva = transformar(_respuestaOVacia(pregunta));
    if (forzarValorNulo) {
      nueva = Respuesta(
        preguntaId: nueva.preguntaId,
        areaCodigo: nueva.areaCodigo,
        textoPregunta: nueva.textoPregunta,
        peso: nueva.peso,
        critica: nueva.critica,
        comentario: nueva.comentario,
        evidencias: nueva.evidencias,
      );
    }

    final respuestas = {...state.respuestas, pregunta.id: nueva};
    state = state.copyWith(
      respuestas: respuestas,
      resultado: _calculo(respuestas: respuestas.values.toList(), pesosArea: state.pesosArea),
    );

    _debounces[pregunta.id]?.cancel();
    if (inmediato) {
      _persistir(nueva);
    } else {
      _debounces[pregunta.id] = Timer(const Duration(milliseconds: 700), () => _persistir(nueva));
    }
  }

  Future<void> _persistir(Respuesta r) async {
    state = state.copyWith(guardando: true);
    try {
      await _repo.guardarRespuesta(state.revisionId, r);
      await _repo.guardarResultados(state.revisionId, state.resultado);
    } finally {
      if (mounted) state = state.copyWith(guardando: false);
    }
  }

  @override
  void dispose() {
    for (final t in _debounces.values) {
      t.cancel();
    }
    super.dispose();
  }
}

/// Sesión de revisión abierta, igual que `sesionAbiertaProvider` en
/// auditorías: la fija la pantalla de inicio antes de navegar al checklist.
final sesionSeguridadAbiertaProvider = StateProvider<RevisionState?>((ref) => null);

final revisionControllerProvider =
    StateNotifierProvider<RevisionController, RevisionState>((ref) {
  final sesion = ref.watch(sesionSeguridadAbiertaProvider);
  if (sesion == null) {
    throw StateError('No hay ninguna revisión de seguridad abierta');
  }
  return RevisionController(ref.watch(revisionSeguridadRepositoryProvider), sesion);
});
