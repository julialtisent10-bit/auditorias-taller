/// Estado de una revisión de seguridad.
///
/// Deliberadamente NO se reutiliza `EstadoAuditoria`: aunque el significado
/// es el mismo, este módulo se mantiene aparte para no arrastrar una
/// dependencia del feature `auditoria` en algo tan pequeño como un enum, y
/// para poder tocar uno sin pensar en el otro.
enum EstadoRevision {
  enCurso('en_curso', 'En curso'),
  finalizada('finalizada', 'Finalizada');

  const EstadoRevision(this.codigo, this.etiqueta);
  final String codigo;
  final String etiqueta;

  static EstadoRevision desdeCodigo(String? c) => EstadoRevision.values
      .firstWhere((e) => e.codigo == c, orElse: () => EstadoRevision.enCurso);
}

/// Cabecera de una revisión mensual de seguridad del taller.
///
/// Mirroring deliberado de la forma de `Auditoria`, pero sin firmas ni
/// responsables por área: el cuestionario tiene una sola área y el informe
/// no exige firma manuscrita, solo el nombre de quien revisó.
class RevisionSeguridad {
  const RevisionSeguridad({
    required this.id,
    required this.centroId,
    required this.centroNombre,
    required this.plantillaId,
    required this.plantillaVersion,
    this.plantillaNombre = '',
    required this.fecha,
    required this.evaluadorUid,
    required this.evaluadorNombre,
    this.estado = EstadoRevision.enCurso,
    this.resultados,
    this.pdfClaveLocal,
    this.creadaEn,
    this.cerradaEn,
  });

  final String id;
  final String centroId;
  final String centroNombre;
  final String plantillaId;
  final int plantillaVersion;
  final String plantillaNombre;
  final DateTime fecha;
  final String evaluadorUid;
  final String evaluadorNombre;
  final EstadoRevision estado;

  /// Snapshot de ResultadoAuditoria.toJson() en el momento del cierre.
  final Map<String, dynamic>? resultados;
  final String? pdfClaveLocal;
  final DateTime? creadaEn;
  final DateTime? cerradaEn;

  /// Clave del informe en el almacén local. Centralizada aquí, igual que
  /// `AlmacenBinarios.claveInforme` para auditorías, y con un prefijo propio
  /// para que ambos módulos no puedan pisarse aunque compartan el almacén.
  static String clavePdf(String revisionId) => 'pdf/seg/$revisionId';

  double get puntuacionGlobal =>
      (resultados?['puntuacionGlobal'] as num?)?.toDouble() ?? 0;

  /// El snapshot de área solo guarda agregados (puntos, %, N/A...), no el
  /// recuento de "Sí"/"No" que pide el histórico. Ese recuento se calcula en
  /// la capa de presentación a partir de las respuestas reales, que es la
  /// única fuente que sabe cuántas fueron CUMPLE y cuántas NO_CUMPLE.
  int get nAplicables =>
      (((resultados?['areas'] as Map?)?['SEG'] as Map?)?['nAplicables'] as num?)
          ?.toInt() ??
      0;

  bool get editable => estado != EstadoRevision.finalizada;

  RevisionSeguridad copyWith({
    EstadoRevision? estado,
    Map<String, dynamic>? resultados,
    String? pdfClaveLocal,
    DateTime? cerradaEn,
  }) =>
      RevisionSeguridad(
        id: id,
        centroId: centroId,
        centroNombre: centroNombre,
        plantillaId: plantillaId,
        plantillaVersion: plantillaVersion,
        plantillaNombre: plantillaNombre,
        fecha: fecha,
        evaluadorUid: evaluadorUid,
        evaluadorNombre: evaluadorNombre,
        estado: estado ?? this.estado,
        resultados: resultados ?? this.resultados,
        pdfClaveLocal: pdfClaveLocal ?? this.pdfClaveLocal,
        creadaEn: creadaEn,
        cerradaEn: cerradaEn ?? this.cerradaEn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'centroId': centroId,
        'centroNombre': centroNombre,
        'plantillaId': plantillaId,
        'plantillaVersion': plantillaVersion,
        'plantillaNombre': plantillaNombre,
        'fecha': fecha.toIso8601String(),
        'evaluadorUid': evaluadorUid,
        'evaluadorNombre': evaluadorNombre,
        'estado': estado.codigo,
        'resultados': resultados,
        'pdf': {'claveLocal': pdfClaveLocal},
        'creadaEn': creadaEn?.toIso8601String(),
        'cerradaEn': cerradaEn?.toIso8601String(),
      };

  factory RevisionSeguridad.fromJson(Map<String, dynamic> j) {
    final pdf = (j['pdf'] as Map?)?.cast<String, dynamic>();
    return RevisionSeguridad(
      id: j['id'] as String,
      centroId: j['centroId'] as String,
      centroNombre: j['centroNombre'] as String? ?? '',
      plantillaId: j['plantillaId'] as String? ?? '',
      plantillaVersion: (j['plantillaVersion'] as num?)?.toInt() ?? 1,
      plantillaNombre: j['plantillaNombre'] as String? ?? '',
      fecha: DateTime.parse(j['fecha'] as String),
      evaluadorUid: j['evaluadorUid'] as String? ?? '',
      evaluadorNombre: j['evaluadorNombre'] as String? ?? '',
      estado: EstadoRevision.desdeCodigo(j['estado'] as String?),
      resultados: (j['resultados'] as Map?)?.cast<String, dynamic>(),
      pdfClaveLocal: pdf?['claveLocal'] as String?,
      creadaEn:
          j['creadaEn'] == null ? null : DateTime.tryParse(j['creadaEn'] as String),
      cerradaEn:
          j['cerradaEn'] == null ? null : DateTime.tryParse(j['cerradaEn'] as String),
    );
  }
}
