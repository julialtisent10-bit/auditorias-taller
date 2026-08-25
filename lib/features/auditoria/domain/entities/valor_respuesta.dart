/// Valor que puede tomar una respuesta de auditoria.
///
/// `factor == null` significa "No Aplica": la pregunta se excluye del
/// numerador Y del denominador, por lo que ni suma ni resta.
enum ValorRespuesta {
  cumple('CUMPLE', 'Cumple', 1.0, '2'),
  parcial('PARCIAL', 'Cumple parcialmente', 0.5, '1'),
  noCumple('NO_CUMPLE', 'No cumple', 0.0, '0'),
  noAplica('NA', 'No aplica', null, 'N/A');

  const ValorRespuesta(this.codigo, this.etiqueta, this.factor, this.puntuacion);

  final String codigo;
  final String etiqueta;
  final double? factor;

  /// Cómo se llama esta respuesta en la hoja de cálculo de la que salió el
  /// cuestionario. Se enseña junto a la etiqueta para que quien lleva años
  /// puntuando «0, 1, 2» reconozca de inmediato lo que está marcando.
  final String puntuacion;

  /// true si la pregunta entra en el calculo (todo menos N/A).
  bool get computa => factor != null;

  /// true si genera hallazgo en el informe PDF.
  bool get esHallazgo => this == ValorRespuesta.noCumple || this == ValorRespuesta.parcial;

  static ValorRespuesta? desdeCodigo(String? codigo) {
    if (codigo == null) return null;
    for (final v in ValorRespuesta.values) {
      if (v.codigo == codigo) return v;
    }
    return null;
  }
}
