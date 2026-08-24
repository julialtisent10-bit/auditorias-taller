import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/providers.dart';

/// Indicador de cuánto ocupan las fotos guardadas en este dispositivo.
///
/// No es decoración. Sin Cloud Storage, las imágenes existen únicamente en el
/// almacenamiento del navegador, que iOS puede vaciar si le falta espacio o
/// si el sitio pasa mucho tiempo sin abrirse. El auditor tiene que poder ver
/// que está acumulando material sin respaldo y que le conviene cerrar las
/// auditorías y descargarse los informes.
class AvisoAlmacenamiento extends ConsumerWidget {
  const AvisoAlmacenamiento({super.key});

  /// A partir de aquí se pinta en ámbar. No es un límite del navegador: es
  /// el punto en el que conviene recordar que hay mucho sin exportar.
  static const _umbralAvisoBytes = 40 * 1024 * 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final almacen = ref.watch(almacenProvider);
    final ocupado = almacen.bytesOcupados;

    if (ocupado == 0) return const SizedBox.shrink();

    final mucho = ocupado > _umbralAvisoBytes;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Fotos guardadas solo en este dispositivo: '
            '${_formatear(ocupado)}.\n'
            'Cierra las auditorías y guarda sus informes para no perderlas.',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mucho ? Icons.sd_card_alert_outlined : Icons.sd_storage_outlined,
              size: 18,
              color: mucho ? Colors.orangeAccent : null,
            ),
            const SizedBox(width: 4),
            Text(
              _formatear(ocupado),
              style: TextStyle(
                fontSize: 12,
                color: mucho ? Colors.orangeAccent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatear(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
