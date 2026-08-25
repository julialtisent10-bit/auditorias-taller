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
    this.pesosAutomaticos = true,
  });

  final String id;
  final String nombre;
  final int version;

  /// areaCodigo -> peso relativo fijado a mano. Solo se usa cuando
  /// [pesosAutomaticos] es false.
  final Map<String, double> pesosArea;

  /// Con true, el peso de cada área se recalcula solo en función de cuántas
  /// preguntas tiene.
  ///
  /// Es lo que mantiene cierta la promesa de «todas las preguntas valen lo
  /// mismo». Con pesos fijos, retirar tres preguntas de un área no cambiaba
  /// su peso, así que las que quedaban pasaban a valer más que las de otra
  /// área sin que nada lo advirtiera.
  final bool pesosAutomaticos;
  final List<AreaPlantilla> areas;
  final List<Pregunta> preguntas;

  List<Pregunta> get preguntasActivas =>
      preguntas.toList()..sort((a, b) => a.orden.compareTo(b.orden));

  /// Los pesos que hay que usar para puntuar. Todo el cálculo pasa por aquí,
  /// nunca por [pesosArea] directamente.
  Map<String, double> get pesosEfectivos {
    if (!pesosAutomaticos) return pesosArea;

    final total = preguntas.length;
    if (total == 0) {
      // Sin preguntas no hay nada que repartir; se reparte a partes iguales
      // para no devolver un mapa vacío que dejaría la puntuación a cero.
      final iguales = areas.isEmpty ? 1.0 : 1 / areas.length;
      return {for (final a in areas) a.codigo: iguales};
    }

    final pesos = <String, double>{};
    var acumulado = 0.0;
    for (var i = 0; i < areas.length; i++) {
      final n = preguntas.where((p) => p.areaCodigo == areas[i].codigo).length;
      if (i == areas.length - 1) {
        // La última absorbe el redondeo para que la suma sea exactamente 1.
        pesos[areas[i].codigo] = double.parse((1 - acumulado).toStringAsFixed(6));
      } else {
        final peso = double.parse((n / total).toStringAsFixed(6));
        pesos[areas[i].codigo] = peso;
        acumulado += peso;
      }
    }
    return pesos;
  }

  int get totalPreguntas => preguntas.length;

  /// Comprobación defensiva: una plantilla mal editada a mano puede dejar
  /// los pesos sin sumar 1 y falsear todas las puntuaciones globales.
  bool get pesosCoherentes {
    if (pesosAutomaticos) return true; // se calculan, no pueden descuadrar
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
        pesosArea: ((j['pesosArea'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        pesosAutomaticos: j['pesosAutomaticos'] as bool? ?? true,
        areas: (j['areas'] as List)
            .map((a) => AreaPlantilla.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList()
          ..sort((a, b) => a.orden.compareTo(b.orden)),
        preguntas: (j['preguntas'] as List)
            .map((p) => Pregunta.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
      );
}
