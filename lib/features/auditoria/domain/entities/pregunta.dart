import 'valor_respuesta.dart';

/// Pregunta del catalogo (plantilla). Inmutable: si cambia, se publica
/// una nueva version de la plantilla; las auditorias cerradas no se tocan.
class Pregunta {
  const Pregunta({
    required this.id,
    required this.areaCodigo,
    required this.bloque,
    required this.orden,
    required this.texto,
    this.ayuda,
    this.peso = 1,
    this.critica = false,
    this.permiteNA = true,
    this.fotoObligatoriaSi = const [ValorRespuesta.noCumple],
  });

  final String id;
  final String areaCodigo;
  final String bloque;
  final int orden;
  final String texto;
  final String? ayuda;

  /// 3 = critica, 2 = importante, 1 = normal.
  final int peso;

  /// Si es critica y se responde NO_CUMPLE, el area queda topada.
  final bool critica;
  final bool permiteNA;
  final List<ValorRespuesta> fotoObligatoriaSi;

  bool exigeFoto(ValorRespuesta? v) => v != null && fotoObligatoriaSi.contains(v);

  Pregunta copyWith({
    String? areaCodigo,
    String? bloque,
    int? orden,
    String? texto,
    String? ayuda,
    int? peso,
    bool? critica,
    bool? permiteNA,
    List<ValorRespuesta>? fotoObligatoriaSi,
  }) =>
      Pregunta(
        id: id,
        areaCodigo: areaCodigo ?? this.areaCodigo,
        bloque: bloque ?? this.bloque,
        orden: orden ?? this.orden,
        texto: texto ?? this.texto,
        // Cadena vacía = borrar la ayuda. Sin este caso no habría forma de
        // quitarla desde el editor, porque null significa "no tocar".
        ayuda: ayuda == null
            ? this.ayuda
            : (ayuda.trim().isEmpty ? null : ayuda.trim()),
        peso: peso ?? this.peso,
        critica: critica ?? this.critica,
        permiteNA: permiteNA ?? this.permiteNA,
        fotoObligatoriaSi: fotoObligatoriaSi ?? this.fotoObligatoriaSi,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'areaCodigo': areaCodigo,
        'bloque': bloque,
        'orden': orden,
        'texto': texto,
        'ayuda': ayuda,
        'peso': peso,
        'critica': critica,
        'permiteNA': permiteNA,
        'fotoObligatoriaSi': fotoObligatoriaSi.map((v) => v.codigo).toList(),
        'activa': true,
      };

  factory Pregunta.fromJson(Map<String, dynamic> j) => Pregunta(
        id: j['id'] as String,
        areaCodigo: j['areaCodigo'] as String,
        bloque: j['bloque'] as String? ?? '',
        orden: (j['orden'] as num?)?.toInt() ?? 0,
        texto: j['texto'] as String,
        ayuda: j['ayuda'] as String?,
        peso: (j['peso'] as num?)?.toInt() ?? 1,
        critica: j['critica'] as bool? ?? false,
        permiteNA: j['permiteNA'] as bool? ?? true,
        fotoObligatoriaSi: ((j['fotoObligatoriaSi'] as List?) ?? const ['NO_CUMPLE'])
            .map((c) => ValorRespuesta.desdeCodigo(c as String))
            .whereType<ValorRespuesta>()
            .toList(),
      );
}
