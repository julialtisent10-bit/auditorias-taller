import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Explica un fallo al leer datos en términos que sirvan para arreglarlo.
///
/// «[cloud_firestore/permission-denied] Missing or insufficient permissions»
/// no dice nada por sí solo: puede ser que la sesión se haya perdido, que las
/// reglas de seguridad no estén publicadas o que estén publicadas en otro
/// sitio. Esta pantalla enseña el estado real de la sesión junto al error,
/// que es lo que distingue un caso del otro.
class ErrorDatos extends StatelessWidget {
  const ErrorDatos({super.key, required this.error, this.queSeIntentaba});

  final Object error;

  /// Qué se estaba leyendo, en palabras del usuario: «los centros».
  final String? queSeIntentaba;

  bool get _esPermisos =>
      error is FirebaseException &&
      (error as FirebaseException).code == 'permission-denied';

  @override
  Widget build(BuildContext context) {
    final usuario = FirebaseAuth.instance.currentUser;
    final esquema = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 44, color: esquema.error),
              const SizedBox(height: 14),
              Text(
                _esPermisos
                    ? 'La base de datos ha rechazado la lectura'
                    : 'No se pudieron cargar ${queSeIntentaba ?? 'los datos'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_esPermisos) ...[
                if (usuario == null)
                  const Text(
                    'No hay sesión iniciada. Cierra la aplicación, vuelve a '
                    'abrirla y entra con tu correo.',
                    style: TextStyle(height: 1.4),
                  )
                else
                  const Text(
                    'La sesión está iniciada, así que el problema está en las '
                    'reglas de seguridad de Firestore: o no se han publicado, '
                    'o se publicaron en otra base de datos.',
                    style: TextStyle(height: 1.4),
                  ),
                const SizedBox(height: 16),
              ],
              _Ficha(
                filas: {
                  'Sesión': usuario == null ? 'sin iniciar' : 'iniciada',
                  if (usuario != null) 'Correo': usuario.email ?? '—',
                  if (usuario != null) 'Identificador': usuario.uid,
                  'Error': _codigo,
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Clipboard.setData(
                        ClipboardData(text: _paraCopiar(usuario))),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar detalle'),
                  ),
                  const SizedBox(width: 8),
                  if (usuario != null)
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Cerrar sesión'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _codigo =>
      error is FirebaseException ? (error as FirebaseException).code : '$error';

  String _paraCopiar(User? usuario) => [
        'Pantalla: ${queSeIntentaba ?? 'datos'}',
        'Sesión: ${usuario == null ? 'sin iniciar' : usuario.email}',
        'Uid: ${usuario?.uid ?? '—'}',
        'Error: $error',
      ].join('\n');
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.filas});

  final Map<String, String> filas;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in filas.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text('${f.key}:',
                        style: TextStyle(fontSize: 12, color: esquema.outline)),
                  ),
                  Expanded(
                    child: SelectableText(f.value,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
