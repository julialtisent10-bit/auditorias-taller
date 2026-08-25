import '../../../auditoria/domain/entities/pregunta.dart';

class AreaPlantilla {
  const AreaPlantilla({
    required this.codigo,
    required this.nombre,
    required this.orden,
    required this.colorHex,
    this.iconoClave = 'checklist',
  });

  final String codigo;
  final String nombre;
  final int orden;
  final String colorHex;

  /// Clave simbólica del icono, no el icono en sí: el dominio no conoce
  /// Flutter. La capa de presentación la traduce.
  final String iconoClave;

  factory AreaPlantilla.fromJson(Map<String, dynamic> j) => AreaPlantilla(
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        orden: (j['orden'] as num?)?.toInt() ?? 0,
        colorHex: j['color'] as String? ?? '#666666',
        iconoClave: j['icono'] as String? ?? 'checklist',
      );

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        'nombre': nombre,
        'orden': orden,
        'color': colorHex,
        'icono': iconoClave,
      };
}

/// Cuestionario versionado. Una auditoría guarda `plantillaId` + `version`
/// para que su resultado sea reproducible aunque después se publique v2.
class Plantilla {
  const Plantilla({
    required this.id,
    required this.nombre,
    required this.version,
    required this.pesosArea,
    required this.areas,
    required this.preguntas,
  });

  final String id;
  final String nombre;
  final int version;

  /// areaCodigo -> peso relativo. Debe sumar 1.0.
  final Map<String, double> pesosArea;
  final List<AreaPlantilla> areas;
  final List<Pregunta> preguntas;

  List<Pregunta> get preguntasActivas =>
      preguntas.toList()..sort((a, b) => a.orden.compareTo(b.orden));

  int get totalPreguntas => preguntas.length;

  /// Comprobación defensiva: una plantilla mal editada a mano puede dejar
  /// los pesos sin sumar 1 y falsear todas las puntuaciones globales.
  bool get pesosCoherentes {
    final suma = pesosArea.values.fold<double>(0, (s, v) => s + v);
    return (suma - 1.0).abs() < 0.001;
  }

  List<String> validar() {
    final errores = <String>[];
    if (!pesosCoherentes) {
      errores.add('Los pesos de área suman '
          '${pesosArea.values.fold<double>(0, (s, v) => s + v)}, deberían sumar 1.0');
    }
    final codigosArea = areas.map((a) => a.codigo).toSet();
    for (final p in preguntas) {
      if (!codigosArea.contains(p.areaCodigo)) {
        errores.add('La pregunta ${p.id} apunta al área inexistente "${p.areaCodigo}"');
      }
    }
    final ids = <String>{};
    for (final p in preguntas) {
      if (!ids.add(p.id)) errores.add('Id de pregunta duplicado: ${p.id}');
    }
    return errores;
  }

  factory Plantilla.fromJson(Map<String, dynamic> j) => Plantilla(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        version: (j['version'] as num?)?.toInt() ?? 1,
        pesosArea: (j['pesosArea'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        areas: (j['areas'] as List)
            .map((a) => AreaPlantilla.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList()
          ..sort((a, b) => a.orden.compareTo(b.orden)),
        preguntas: (j['preguntas'] as List)
            .map((p) => Pregunta.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
      );
}
