class ResumenCentro {
  const ResumenCentro({
    this.ultimaAuditoriaId,
    this.ultimaFecha,
    this.ultimaPuntuacion,
    this.penultimaPuntuacion,
  });

  final String? ultimaAuditoriaId;
  final DateTime? ultimaFecha;
  final double? ultimaPuntuacion;
  final double? penultimaPuntuacion;

  /// Variación respecto a la auditoría anterior. null si es la primera.
  double? get tendencia => (ultimaPuntuacion == null || penultimaPuntuacion == null)
      ? null
      : ultimaPuntuacion! - penultimaPuntuacion!;

  Map<String, dynamic> toJson() => {
        'ultimaAuditoriaId': ultimaAuditoriaId,
        'ultimaFecha': ultimaFecha?.toIso8601String(),
        'ultimaPuntuacion': ultimaPuntuacion,
        'penultimaPuntuacion': penultimaPuntuacion,
      };

  factory ResumenCentro.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ResumenCentro();
    return ResumenCentro(
      ultimaAuditoriaId: j['ultimaAuditoriaId'] as String?,
      ultimaFecha:
          j['ultimaFecha'] == null ? null : DateTime.tryParse(j['ultimaFecha'] as String),
      ultimaPuntuacion: (j['ultimaPuntuacion'] as num?)?.toDouble(),
      penultimaPuntuacion: (j['penultimaPuntuacion'] as num?)?.toDouble(),
    );
  }
}

class Centro {
  const Centro({
    required this.id,
    required this.nombre,
    this.codigo = '',
    this.poblacion = '',
    this.tipo = 'taller_vehiculo_industrial',
    this.plantillaPorDefecto,
    this.activo = true,
    this.responsables = const {},
    this.resumen = const ResumenCentro(),
  });

  final String id;
  final String nombre;
  final String codigo;
  final String poblacion;

  /// Permite que un centro especializado (p. ej. remolques) use otra
  /// plantilla sin duplicar la aplicación.
  final String tipo;
  final String? plantillaPorDefecto;
  final bool activo;

  /// areaCodigo -> nombre del responsable. Se precarga en cada auditoría
  /// nueva para no volver a teclearlo.
  final Map<String, String> responsables;
  final ResumenCentro resumen;

  Centro copyWith({
    String? nombre,
    String? codigo,
    String? poblacion,
    bool? activo,
    Map<String, String>? responsables,
  }) =>
      Centro(
        id: id,
        nombre: nombre ?? this.nombre,
        codigo: codigo ?? this.codigo,
        poblacion: poblacion ?? this.poblacion,
        tipo: tipo,
        plantillaPorDefecto: plantillaPorDefecto,
        activo: activo ?? this.activo,
        responsables: responsables ?? this.responsables,
        resumen: resumen,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'codigo': codigo,
        'poblacion': poblacion,
        'tipo': tipo,
        'plantillaPorDefecto': plantillaPorDefecto,
        'activo': activo,
        'responsables': responsables,
        'resumen': resumen.toJson(),
      };

  factory Centro.fromJson(Map<String, dynamic> j) => Centro(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        codigo: j['codigo'] as String? ?? '',
        poblacion: j['poblacion'] as String? ?? '',
        tipo: j['tipo'] as String? ?? 'taller_vehiculo_industrial',
        plantillaPorDefecto: j['plantillaPorDefecto'] as String?,
        activo: j['activo'] as bool? ?? true,
        responsables: Map<String, String>.from(
            (j['responsables'] as Map?)?.cast<String, String>() ?? const {}),
        resumen: ResumenCentro.fromJson(
            (j['resumen'] as Map?)?.cast<String, dynamic>()),
      );
}
