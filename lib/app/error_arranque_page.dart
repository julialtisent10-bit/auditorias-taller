import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Pantalla de último recurso cuando el arranque falla.
///
/// El caso típico es que falte `firebase_options.dart` porque todavía no se
/// ha ejecutado `flutterfire configure`. Sin esto la aplicación se queda en
/// la pantalla de carga para siempre y no hay forma de saber por qué.
class ErrorArranqueApp extends StatelessWidget {
  const ErrorArranqueApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auditorías de taller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro(),
      darkTheme: AppTheme.oscuro(),
      // El contenido va en un widget aparte, y no en línea aquí, por un
      // motivo concreto: `Theme.of(context)` con el contexto de ESTE build
      // devuelve el tema por defecto de Flutter, no el que acabamos de
      // declarar, porque el MaterialApp todavía no está por encima. El
      // síntoma es un titular gris sobre fondo negro en modo oscuro.
      home: _Contenido(error: error),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_suggest_outlined,
                      size: 56, color: Colors.orangeAccent),
                  const SizedBox(height: 16),
                  Text('Falta configurar Firebase',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Text(
                    'La aplicación no ha podido conectar con el proyecto. '
                    'Es lo normal hasta que se ejecuta la configuración '
                    'inicial:',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  const _Comando('flutterfire configure'),
                  const SizedBox(height: 12),
                  const Text(
                    'Después hay que activar en la consola de Firebase: '
                    'Authentication (correo y contraseña), Firestore y Storage.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Detalle técnico',
                        style: TextStyle(fontSize: 13)),
                    children: [
                      SelectableText('$error',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey, height: 1.4)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

class _Comando extends StatelessWidget {
  const _Comando(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SelectableText(texto,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      );
}
