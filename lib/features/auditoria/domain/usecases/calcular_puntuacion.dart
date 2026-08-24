import '../entities/respuesta.dart';
import '../entities/valor_respuesta.dart';

/// Resultado de una de las 4 areas.
class ResultadoArea {
  const ResultadoArea({
    required this.areaCodigo,
    required this.puntosObtenidos,
    required this.puntosPosibles,
    required this.porcentaje,
    required this.evaluable,
    required this.nTotal,
    required this.nAplicables,
    required this.nNoAplica,
    required this.nSinResponder,
    required this.nCriticasFalladas,
    required this.topadaPorCritica,
  });

  final String areaCodigo;
  final double puntosObtenidos;
  final double puntosPosibles;

  /// 0..100. Solo tiene sentido si [evaluable] es true.
  final double porcentaje;

  /// false cuando todas las preguntas del area quedaron en N/A o sin responder.
  final bool evaluable;

  final int nTotal;
  final int nAplicables;
  final int nNoAplica;
  final int nSinResponder;
  final int nCriticasFalladas;
  final bool topadaPorCritica;

  bool get completa => nSinResponder == 0;
  double get progreso => nTotal == 0 ? 1 : (nTotal - nSinResponder) / nTotal;

  Map<String, dynamic> toJson() => {
        'puntosObtenidos': puntosObtenidos,
        'puntosPosibles': puntosPosibles,
        'porcentaje': porcentaje,
        'evaluable': evaluable,
        'nAplicables': nAplicables,
        'nNoAplica': nNoAplica,
        'nSinResponder': nSinResponder,
        'nCriticasFalladas': nCriticasFalladas,
        'topadaPorCritica': topadaPorCritica,
      };
}

class ResultadoAuditoria {
  const ResultadoAuditoria({
    required this.areas,
    required this.puntuacionGlobal,
    required this.nivel,
    required this.progresoGlobal,
    required this.totalCriticasFalladas,
  });

  final Map<String, ResultadoArea> areas;
  final double puntuacionGlobal;
  final String nivel;
  final double progresoGlobal;
  final int totalCriticasFalladas;

  bool get completa => areas.values.every((a) => a.completa);

  Map<String, dynamic> toJson() => {
        'areas': areas.map((k, v) => MapEntry(k, v.toJson())),
        'puntuacionGlobal': puntuacionGlobal,
        'nivel': nivel,
        'totalCriticasFalladas': totalCriticasFalladas,
      };
}

/// Caso de uso PURO: sin Flutter, sin Firebase, sin IO. Testeable al 100%.
///
///   % Area  = SUM(peso_i * factor_i) / SUM(peso_i) * 100   [solo i con valor != N/A]
///   Global  = SUM(pesoArea_a * %Area_a) / SUM(pesoArea_a)  [solo areas evaluables]
///
/// Regla de critica: si una pregunta con `critica == true` se responde
/// NO_CUMPLE, el area se topa en [topeCritica] por muy alta que salga la media.
/// Sin esta regla un fallo de EPIs queda diluido entre 25 preguntas correctas.
class CalcularPuntuacion {
  const CalcularPuntuacion({
    this.aplicarTopeCritica = true,
    this.topeCritica = 79.0,
  });

  final bool aplicarTopeCritica;
  final double topeCritica;

  ResultadoAuditoria call({
    required List<Respuesta> respuestas,
    required Map<String, double> pesosArea,
  }) {
    final areas = <String, ResultadoArea>{};

    for (final areaCodigo in pesosArea.keys) {
      final delArea = respuestas.where((r) => r.areaCodigo == areaCodigo).toList();

      double obtenidos = 0;
      double posibles = 0;
      var nAplicables = 0;
      var nNoAplica = 0;
      var nSinResponder = 0;
      var nCriticasFalladas = 0;

      for (final r in delArea) {
        if (r.valor == null) {
          nSinResponder++;
          continue;
        }
        if (r.valor == ValorRespuesta.noAplica) {
          nNoAplica++;
          continue;
        }
        nAplicables++;
        obtenidos += r.puntosObtenidos;
        posibles += r.puntosPosibles;
        if (r.critica && r.valor == ValorRespuesta.noCumple) nCriticasFalladas++;
      }

      final evaluable = posibles > 0;
      var porcentaje = evaluable ? (obtenidos / posibles) * 100 : 0.0;

      final topada = aplicarTopeCritica && nCriticasFalladas > 0 && porcentaje > topeCritica;
      if (topada) porcentaje = topeCritica;

      areas[areaCodigo] = ResultadoArea(
        areaCodigo: areaCodigo,
        puntosObtenidos: obtenidos,
        puntosPosibles: posibles,
        porcentaje: _redondear(porcentaje),
        evaluable: evaluable,
        nTotal: delArea.length,
        nAplicables: nAplicables,
        nNoAplica: nNoAplica,
        nSinResponder: nSinResponder,
        nCriticasFalladas: nCriticasFalladas,
        topadaPorCritica: topada,
      );
    }

    // Media ponderada solo sobre areas evaluables: un area entera en N/A
    // no debe arrastrar la global hacia cero.
    double numerador = 0;
    double denominador = 0;
    for (final entry in areas.entries) {
      if (!entry.value.evaluable) continue;
      final peso = pesosArea[entry.key] ?? 0;
      numerador += peso * entry.value.porcentaje;
      denominador += peso;
    }
    final global = denominador > 0 ? _redondear(numerador / denominador) : 0.0;

    final totalPreguntas = respuestas.length;
    final respondidas = respuestas.where((r) => r.respondida).length;

    return ResultadoAuditoria(
      areas: areas,
      puntuacionGlobal: global,
      nivel: nivelDe(global),
      progresoGlobal: totalPreguntas == 0 ? 0 : respondidas / totalPreguntas,
      totalCriticasFalladas: areas.values.fold(0, (s, a) => s + a.nCriticasFalladas),
    );
  }

  static String nivelDe(double p) {
    if (p >= 90) return 'A';
    if (p >= 80) return 'B';
    if (p >= 65) return 'C';
    return 'D';
  }

  static double _redondear(double v) => (v * 10).roundToDouble() / 10;
}
