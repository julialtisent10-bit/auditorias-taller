import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../firebase_options.dart';
import 'almacen/almacen_binarios.dart';

class Servicios {
  const Servicios({required this.almacen});

  final AlmacenBinarios almacen;
}

/// Arranque de la aplicación. Se llama desde main() antes de runApp().
///
/// `options` es obligatorio en web: sin él el SDK no sabe a qué proyecto
/// conectar y falla en silencio dentro de una promesa de JavaScript.
Future<Servicios> inicializar() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Persistencia de documentos. Es lo que hace que las lecturas y escrituras
  // de Firestore funcionen contra la caché local sin cobertura, y que se
  // reenvíen solas al recuperar red, incluso tras cerrar la pestaña.
  //
  // En web la caché vive en IndexedDB y solo admite UNA pestaña a la vez: si
  // el auditor abre la app dos veces, la segunda se queda sin persistencia.
  // Por eso el fallo se traga en lugar de tumbar el arranque.
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Persistencia de Firestore no disponible: $e');
  }

  await Hive.initFlutter();
  final almacen = await AlmacenBinarios.abrir();

  // Sin Cloud Storage (requiere plan de pago) no hay nada que subir: las
  // fotos se quedan aquí y el PDF es la copia que sale del dispositivo.
  return Servicios(almacen: almacen);
}
