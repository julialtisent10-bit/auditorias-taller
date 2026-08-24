import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/providers.dart';
import 'app/error_arranque_page.dart';
import 'core/firebase_bootstrap.dart';

/// Evita que un error repetido vuelva a montar la aplicación una y otra vez.
bool _errorMostrado = false;

void _mostrarError(Object error) {
  if (_errorMostrado) return;
  _errorMostrado = true;
  runApp(ErrorArranqueApp(error: error));
}

Future<void> main() async {
  // Zona guardada: los SDK de Firebase para web fallan dentro de promesas de
  // JavaScript, y esos errores no los atrapa un try/catch normal. Sin esto,
  // un proyecto sin configurar deja la pantalla de carga puesta para siempre
  // y no hay manera de distinguirlo de un cuelgue.
  // El cuerpo es async a proposito y no se espera: runZonedGuarded devuelve
  // antes de que termine, y esperar aqui no aportaria nada porque main() ya
  // no tiene mas trabajo despues.
  // ignore: unawaited_futures
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Solo vertical: la auditoría se hace de pie y con una mano.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    try {
      final servicios = await inicializar();

      runApp(
        ProviderScope(
          overrides: [
            almacenProvider.overrideWithValue(servicios.almacen),
          ],
          child: const AuditApp(),
        ),
      );
    } catch (e) {
      _mostrarError(e);
    }
  }, (error, _) => _mostrarError(error));
}
