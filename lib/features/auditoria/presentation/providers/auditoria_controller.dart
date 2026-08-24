import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../domain/entities/evidencia.dart';
import '../../domain/entities/pregunta.dart';
import '../../domain/entities/respuesta.dart';
import '../../domain/entities/valor_respuesta.dart';
import '../../domain/repositories/auditoria_repository.dart';
import '../../domain/usecases/calcular_puntuacion.dart';

class AuditoriaState {
  const AuditoriaState({
    required this.auditoriaId,
    required this.centroNombre,
    required this.fecha,
    required this.preguntas,
    required this.respuestas,
    required this.pesosArea,
    required this.resultado,
    this.guardando = false,
  });

  /// Construye el estado inicial a partir de la plantilla y de las respuestas
  /// ya guardadas. Con [respuestasPrevias] no vacío se reanuda una auditoría
  /// a medias sin perder nada de lo respondido.
  factory AuditoriaState.desde({
    required String auditoriaId,
    required String centroNombre,
    required DateTime fecha,
    required List<Pregunta> preguntas,
    required Map<String, double> pesosArea,
    List<Respuesta> respuestasPrevias = const [],
  }) {
    final respuestas = {for (final r in respuestasPrevias) r.preguntaId: r};
    return AuditoriaState(
      auditoriaId: auditoriaId,
      centroNombre: centroNombre,
      fecha: fecha,
      preguntas: [...preguntas]..sort((a, b) => a.orden.compareTo(b.orden)),
      respuestas: respuestas,
      pesosArea: pesosArea,
      resultado: const CalcularPuntuacion()(
        respuestas: respuestas.values.toList(),
        pesosArea: pesosArea,
      ),
    );
  }

  final String auditoriaId;
  final String centroNombre;
  final DateTime fecha;

  /// Catalogo de la plantilla, ya ordenado.
  final List<Pregunta> preguntas;

  /// Indexado por preguntaId para acceso O(1) desde la UI.
  final Map<String, Respuesta> respuestas;
  final Map<String, double> pesosArea;
  final ResultadoAuditoria resultado;
  final bool guardando;

  List<Pregunta> preguntasDe(String areaCodigo) =>
      preguntas.where((p) => p.areaCodigo == areaCodigo).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

  /// Preguntas de un area agrupadas por bloque, respetando el orden original.
  Map<String, List<Pregunta>> bloquesDe(String areaCodigo) {
    final mapa = <String, List<Pregunta>>{};
    for (final p in preguntasDe(areaCodigo)) {
      mapa.putIfAbsent(p.bloque, () => []).add(p);
    }
    return mapa;
  }

  Respuesta? respuestaDe(String preguntaId) => respuestas[preguntaId];

  /// Preguntas que exigen foto segun su valor y aun no la tienen.
  List<Pregunta> get evidenciasPendientes => preguntas.where((p) {
        final r = respuestas[p.id];
        return p.exigeFoto(r?.valor) && (r?.evidencias.isEmpty ?? true);
      }).toList();

  bool get puedeFinalizar => resultado.completa && evidenciasPendientes.isEmpty;

  AuditoriaState copyWith({
    Map<String, Respuesta>? respuestas,
    ResultadoAuditoria? resultado,
    bool? guardando,
  }) =>
      AuditoriaState(
        auditoriaId: auditoriaId,
        centroNombre: centroNombre,
        fecha: fecha,
        preguntas: preguntas,
        respuestas: respuestas ?? this.respuestas,
        pesosArea: pesosArea,
        resultado: resultado ?? this.resultado,
        guardando: guardando ?? this.guardando,
      );
}

class AuditoriaController extends StateNotifier<AuditoriaState> {
  AuditoriaController(this._repo, AuditoriaState inicial) : super(inicial);

  final AuditoriaRepository _repo;
  static const _calculo = CalcularPuntuacion();

  /// Debounce por pregunta: escribir un comentario no debe disparar
  /// una escritura por pulsacion de tecla.
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
      auditoriaId: state.auditoriaId,
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
    await _repo.eliminarEvidencia(state.auditoriaId, pregunta.id, evidencia);
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
        textoPregunta: p.texto, // snapshot inmutable
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
      // Escritura local siempre; la subida a Firestore la resuelve la
      // persistencia offline + la cola de outbox para las fotos.
      await _repo.guardarRespuesta(state.auditoriaId, r);
      await _repo.guardarResultados(state.auditoriaId, state.resultado);
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

/// Sesión de auditoría abierta. La fija la pantalla de inicio antes de
/// navegar al cuestionario y se limpia al cerrar el informe.
///
/// Se resuelve así, con un provider global, y no con un `ProviderScope`
/// anidado: las rutas con nombre se insertan en el Navigator raíz, de modo
/// que un scope anidado alrededor del cuestionario no sería ancestro de las
/// pantallas de resumen y firma, y estas perderían el controlador.
final sesionAbiertaProvider = StateProvider<AuditoriaState?>((ref) => null);

final auditoriaControllerProvider =
    StateNotifierProvider<AuditoriaController, AuditoriaState>((ref) {
  final sesion = ref.watch(sesionAbiertaProvider);
  if (sesion == null) {
    throw StateError('No hay ninguna auditoría abierta');
  }
  return AuditoriaController(ref.watch(auditoriaRepositoryProvider), sesion);
});
