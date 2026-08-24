import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/providers.dart';
import '../../core/sync/sync_service.dart';

/// Indicador de cola pendiente.
///
/// No es decoración: sin él, el auditor no tiene forma de saber que sus 40
/// fotos siguen en el móvil y no en el servidor, y puede borrar la app o
/// dar la auditoría por subida cuando no lo está.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);

    return ValueListenableBuilder<EstadoSincronizacion>(
      valueListenable: sync.estado,
      builder: (context, estado, _) {
        if (estado.alDia) {
          return const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Tooltip(
              message: 'Todo sincronizado',
              child: Icon(Icons.cloud_done_outlined, size: 20),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: sync.drenar,
            icon: estado.trabajando
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    estado.hayRed ? Icons.cloud_upload_outlined : Icons.cloud_off,
                    size: 18,
                  ),
            label: Text('${estado.pendientes}', style: const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }
}
