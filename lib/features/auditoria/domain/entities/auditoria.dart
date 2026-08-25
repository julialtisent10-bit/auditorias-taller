enum EstadoAuditoria {
  borrador('borrador', 'Borrador'),
  enCurso('en_curso', 'En curso'),
  finalizada('finalizada', 'Finalizada');

  const EstadoAuditoria(this.codigo, this.etiqueta);
  final String codigo;
  final String etiqueta;

  static EstadoAuditoria desdeCodigo(String? c) => EstadoAuditoria.values
      .firstWhere((e) => e.codigo == c, orElse: () => EstadoAuditoria.borrador);
}

class Firma {
  const Firma({required this.nombre, this.claveLocal, this.url, this.firmadoEn});

  final String nombre;

  /// Clave del PNG de la firma en el almacén local. La sube la cola de outbox.
  final String? claveLocal;
  final String? url;
  final DateTime? firmadoEn;

  bool get firmada => firmadoEn != null && (claveLocal != null || url != null);

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'claveLocal': claveLocal,
        'url': url,
        'firmadoEn': firmadoEn?.toIso8601String(),
      };

  factory Firma.fromJson(Map<String, dynamic>? j) => Firma(
        nombre: j?['nombre'] as String? ?? '',
        claveLocal: j?['claveLocal'] as String?,
        url: j?['url'] as String?,
        firmadoEn:
            j?['firmadoEn'] == null ? null : DateTime.tryParse(j!['firmadoEn'] as String),
      );
}

/// Cabecera de la auditoría. Las respuestas viven en una subcolección
/// aparte para no reescribir el documento entero en cada toque.
class Auditoria {
  const Auditoria({
    required this.id,
    required this.centroId,
    required this.centroNombre,
    required this.plantillaId,
    required this.plantillaVersion,
    this.plantillaNombre = '',
    required this.fecha,
    required this.auditorUid,
    required this.auditorNombre,
    this.estado = EstadoAuditoria.borrador,
    this.responsables = const {},
    this.resultados,
    this.firmaAuditor,
    this.firmaGerente,
    this.fortalezas = '',
    this.pdfUrl,
    this.pdfClaveLocal,
    this.creadaEn,
    this.cerradaEn,
  });

  final String id;
  final String centroId;
  final String centroNombre;
  final String plantillaId;
  final int plantillaVersion;

  /// Nombre del cuestionario tal y como se llamaba ese día. Igual que con el
  /// texto de las preguntas, se guarda copiado: si mañana se renombra, el
  /// informe antiguo debe seguir diciendo lo que decía.
  final String plantillaNombre;
  final DateTime fecha;
  final String auditorUid;
  final String auditorNombre;
  final EstadoAuditoria estado;

  /// areaCodigo -> responsable presente durante la auditoría.
  /// La clave 'gerente' guarda el gerente del centro, que firma el informe.
  final Map<String, String> responsables;

  /// Snapshot del cálculo en el momento del cierre (ResultadoAuditoria.toJson).
  final Map<String, dynamic>? resultados;

  /// Lo que el auditor destaca en positivo, con sus palabras.
  ///
  /// El Excel del que sale este cuestionario reserva un apartado para esto y
  /// no se puede deducir de las respuestas: una auditoría con todo en verde
  /// no dice qué merece la pena replicar en los demás centros.
  final String fortalezas;

  final Firma? firmaAuditor;
  final Firma? firmaGerente;
  final String? pdfUrl;
  final String? pdfClaveLocal;
  final DateTime? creadaEn;
  final DateTime? cerradaEn;

  double get puntuacionGlobal =>
      (resultados?['puntuacionGlobal'] as num?)?.toDouble() ?? 0;

  String get nivel => resultados?['nivel'] as String? ?? '-';

  double porcentajeArea(String areaCodigo) {
    final areas = resultados?['areas'] as Map?;
    return ((areas?[areaCodigo] as Map?)?['porcentaje'] as num?)?.toDouble() ?? 0;
  }

  bool get editable => estado != EstadoAuditoria.finalizada;

  Auditoria copyWith({
    EstadoAuditoria? estado,
    Map<String, String>? responsables,
    Map<String, dynamic>? resultados,
    String? fortalezas,
    Firma? firmaAuditor,
    Firma? firmaGerente,
    String? pdfUrl,
    String? pdfClaveLocal,
    DateTime? cerradaEn,
  }) =>
      Auditoria(
        id: id,
        centroId: centroId,
        centroNombre: centroNombre,
        plantillaId: plantillaId,
        plantillaVersion: plantillaVersion,
        plantillaNombre: plantillaNombre,
        fecha: fecha,
        auditorUid: auditorUid,
        auditorNombre: auditorNombre,
        estado: estado ?? this.estado,
        responsables: responsables ?? this.responsables,
        resultados: resultados ?? this.resultados,
        fortalezas: fortalezas ?? this.fortalezas,
        firmaAuditor: firmaAuditor ?? this.firmaAuditor,
        firmaGerente: firmaGerente ?? this.firmaGerente,
        pdfUrl: pdfUrl ?? this.pdfUrl,
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
        'auditorUid': auditorUid,
        'auditorNombre': auditorNombre,
        'estado': estado.codigo,
        'responsables': responsables,
        'resultados': resultados,
        'fortalezas': fortalezas,
        'firmas': {
          'auditor': firmaAuditor?.toJson(),
          'gerente': firmaGerente?.toJson(),
        },
        'pdf': {'url': pdfUrl, 'claveLocal': pdfClaveLocal},
        'creadaEn': creadaEn?.toIso8601String(),
        'cerradaEn': cerradaEn?.toIso8601String(),
      };

  factory Auditoria.fromJson(Map<String, dynamic> j) {
    final firmas = (j['firmas'] as Map?)?.cast<String, dynamic>();
    final pdf = (j['pdf'] as Map?)?.cast<String, dynamic>();
    return Auditoria(
      id: j['id'] as String,
      centroId: j['centroId'] as String,
      centroNombre: j['centroNombre'] as String? ?? '',
      plantillaId: j['plantillaId'] as String? ?? '',
      plantillaVersion: (j['plantillaVersion'] as num?)?.toInt() ?? 1,
      plantillaNombre: j['plantillaNombre'] as String? ?? '',
      fecha: DateTime.parse(j['fecha'] as String),
      auditorUid: j['auditorUid'] as String? ?? '',
      auditorNombre: j['auditorNombre'] as String? ?? '',
      estado: EstadoAuditoria.desdeCodigo(j['estado'] as String?),
      responsables:
          Map<String, String>.from((j['responsables'] as Map?)?.cast<String, String>() ?? {}),
      resultados: (j['resultados'] as Map?)?.cast<String, dynamic>(),
      fortalezas: j['fortalezas'] as String? ?? '',
      firmaAuditor: firmas?['auditor'] == null
          ? null
          : Firma.fromJson((firmas!['auditor'] as Map).cast<String, dynamic>()),
      firmaGerente: firmas?['gerente'] == null
          ? null
          : Firma.fromJson((firmas!['gerente'] as Map).cast<String, dynamic>()),
      pdfUrl: pdf?['url'] as String?,
      pdfClaveLocal: pdf?['claveLocal'] as String?,
      creadaEn:
          j['creadaEn'] == null ? null : DateTime.tryParse(j['creadaEn'] as String),
      cerradaEn:
          j['cerradaEn'] == null ? null : DateTime.tryParse(j['cerradaEn'] as String),
    );
  }
}
