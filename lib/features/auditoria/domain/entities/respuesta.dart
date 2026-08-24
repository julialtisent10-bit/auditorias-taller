import 'evidencia.dart';
import 'valor_respuesta.dart';

/// Respuesta a una pregunta. Guarda un SNAPSHOT del texto y el peso para
/// que el historico sea reproducible aunque la plantilla evolucione.
class Respuesta {
  const Respuesta({
    required this.preguntaId,
    required this.areaCodigo,
    required this.textoPregunta,
    required this.peso,
    required this.critica,
    this.valor,
    this.comentario = '',
    this.evidencias = const [],
    this.respondidaEn,
  });

  static const int maxEvidencias = 2;

  final String preguntaId;
  final String areaCodigo;
  final String textoPregunta;
  final int peso;
  final bool critica;
  final ValorRespuesta? valor;
  final String comentario;
  final List<Evidencia> evidencias;
  final DateTime? respondidaEn;

  bool get respondida => valor != null;
  bool get computa => valor?.computa ?? false;
  bool get puedeAnadirEvidencia => evidencias.length < maxEvidencias;

  double get puntosObtenidos => computa ? peso * valor!.factor! : 0;
  double get puntosPosibles => computa ? peso.toDouble() : 0;

  Respuesta copyWith({
    ValorRespuesta? valor,
    String? comentario,
    List<Evidencia>? evidencias,
    DateTime? respondidaEn,
  }) =>
      Respuesta(
        preguntaId: preguntaId,
        areaCodigo: areaCodigo,
        textoPregunta: textoPregunta,
        peso: peso,
        critica: critica,
        valor: valor ?? this.valor,
        comentario: comentario ?? this.comentario,
        evidencias: evidencias ?? this.evidencias,
        respondidaEn: respondidaEn ?? this.respondidaEn,
      );

  Map<String, dynamic> toJson() => {
        'preguntaId': preguntaId,
        'areaCodigo': areaCodigo,
        'textoPregunta': textoPregunta,
        'peso': peso,
        'critica': critica,
        'valor': valor?.codigo,
        'factor': valor?.factor,
        'comentario': comentario,
        'evidencias': evidencias.map((e) => e.toJson()).toList(),
        'respondidaEn': respondidaEn?.toIso8601String(),
      };

  factory Respuesta.fromJson(Map<String, dynamic> j) => Respuesta(
        preguntaId: j['preguntaId'] as String,
        areaCodigo: j['areaCodigo'] as String,
        textoPregunta: j['textoPregunta'] as String,
        peso: (j['peso'] as num).toInt(),
        critica: j['critica'] as bool? ?? false,
        valor: ValorRespuesta.desdeCodigo(j['valor'] as String?),
        comentario: j['comentario'] as String? ?? '',
        evidencias: ((j['evidencias'] as List?) ?? const [])
            .map((e) => Evidencia.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        respondidaEn: j['respondidaEn'] == null ? null : DateTime.parse(j['respondidaEn'] as String),
      );
}
