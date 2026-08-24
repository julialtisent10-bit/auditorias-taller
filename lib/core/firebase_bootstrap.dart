import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'almacen/almacen_binarios.dart';
import 'sync/outbox_store.dart';
import 'sync/sync_service.dart';

class Servicios {
  const Servicios({
    required this.outbox,
    required this.almacen,
    required this.sync,
  });

  final OutboxStore outbox;
  final AlmacenBinarios almacen;
  final SyncService sync;
}

/// Arranque de la aplicación. Se llama desde main() antes de runApp().
///
/// Tras ejecutar `flutterfire configure`, sustituir la llamada sin opciones
/// por `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
/// En web es obligatorio: sin opciones explícitas el SDK no arranca.
Future<Servicios> inicializar() async {
  await Firebase.initializeApp();

  // Persistencia de documentos. Es lo que hace que las lecturas y escrituras
  // de Firestore funcionen contra la caché local sin cobertura.
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
  final outbox = await OutboxStore.abrir();

  final sync = SyncService(outbox: outbox, almacen: almacen);
  await sync.iniciar();

  return Servicios(outbox: outbox, almacen: almacen, sync: sync);
}
