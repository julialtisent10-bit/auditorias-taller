import 'package:flutter/material.dart';

import '../features/plantillas/domain/entities/plantilla.dart';

/// Un área lista para pintar: nombre, color e icono ya resueltos.
///
/// Existe porque las áreas dejaron de estar fijadas en el código. Antes eran
/// cuatro constantes; ahora salen de la plantilla, que puede traer las que
/// haga falta. El dominio guarda el color como texto y el icono como una
/// clave simbólica, y esta clase es la que los traduce a tipos de Flutter.
class AreaVista {
  const AreaVista({
    required this.codigo,
    required this.nombre,
    required this.color,
    required this.icono,
  });

  final String codigo;
  final String nombre;
  final Color color;
  final IconData icono;

  factory AreaVista.desde(AreaPlantilla area) => AreaVista(
        codigo: area.codigo,
        nombre: area.nombre,
        color: _color(area.colorHex),
        icono: _iconos[area.iconoClave] ?? Icons.checklist,
      );

  static List<AreaVista> listaDesde(Iterable<AreaPlantilla> areas) =>
      areas.map(AreaVista.desde).toList();

  /// Versión abreviada para pestañas, donde no cabe el nombre entero.
  /// Corta por el separador si lo hay: «Taller · Mecánicos» -> «Taller».
  String get nombreCorto {
    final corte = nombre.indexOf('·');
    return corte > 0 ? nombre.substring(0, corte).trim() : nombre;
  }

  static Color _color(String hex) {
    final limpio = hex.replaceAll('#', '').trim();
    final valor = int.tryParse(limpio, radix: 16);
    if (valor == null) return const Color(0xFF607D8B);
    // Seis dígitos: le falta el canal alfa, que va opaco.
    return Color(limpio.length <= 6 ? 0xFF000000 | valor : valor);
  }

  /// Iconos disponibles para las áreas. Añadir aquí uno nuevo es lo único
  /// que hace falta para poder usarlo desde la plantilla.
  static const Map<String, IconData> _iconos = {
    'domain': Icons.domain,
    'receipt_long': Icons.receipt_long,
    'build': Icons.build,
    'inventory_2': Icons.inventory_2,
    'support_agent': Icons.support_agent,
    'engineering': Icons.engineering,
    'insights': Icons.insights,
    'checklist': Icons.checklist,
    'groups': Icons.groups,
    'local_shipping': Icons.local_shipping,
    'shield': Icons.shield_outlined,
    'cleaning_services': Icons.cleaning_services,
  };
}
