import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../almacen/almacen_binarios.dart';
import 'outbox_store.dart';

class EstadoSincronizacion {
  const EstadoSincronizacion({
    this.pendientes = 0,
    this.fallidas = 0,
    this.trabajando = false,
    this.hayRed = true,
  });

  final int pendientes;
  final int fallidas;
  final bool trabajando;
  final bool hayRed;

  bool get alDia => pendientes == 0 && !trabajando;
}

/// Vacía la cola de binarios cuando hay red.
///
/// Un solo trabajador en serie, deliberadamente: subir ocho fotos en paralelo
/// por 4G desde un polígono satura la conexión y hace que fallen todas. En
/// serie tarda más, pero termina.
class SyncService {
  SyncService({
    required OutboxStore outbox,
    required AlmacenBinarios almacen,
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
  })  : _outbox = outbox,
        _almacen = almacen,
        _storage = storage ?? FirebaseStorage.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _connectivity = connectivity ?? Connectivity();

  final OutboxStore _outbox;
  final AlmacenBinarios _almacen;
  final FirebaseStorage _storage;
  final FirebaseFirestore _db;
  final Connectivity _connectivity;

  final _estado = ValueNotifier<EstadoSincronizacion>(const EstadoSincronizacion());
  ValueListenable<EstadoSincronizacion> get estado => _estado;

  StreamSubscription<List<ConnectivityResult>>? _subRed;
  Timer? _reloj;
  bool _drenando = false;

  Future<void> iniciar() async {
    _refrescarContador();

    // Disparador 1: cambia la conectividad (sale del taller, coge el wifi).
    _subRed = _connectivity.onConnectivityChanged.listen((resultados) {
      final hayRed = !resultados.contains(ConnectivityResult.none);
      _refrescarContador(hayRed: hayRed);
      if (hayRed) unawaited(drenar());
    });

    // Disparador 2: reloj de respaldo. La conectividad puede informar de
    // "wifi" con un portal cautivo delante, y entonces el evento no vuelve
    // a saltar nunca.
    _reloj = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(drenar()));

    unawaited(drenar());
  }

  /// Procesa la cola hasta vaciarla o hasta que todo lo pendiente esté
  /// esperando su turno. Reentrante: si ya hay un drenado en curso, sale.
  Future<void> drenar() async {
    if (_drenando) return;
    _drenando = true;
    _refrescarContador();

    try {
      while (true) {
        final ahora = DateTime.now().millisecondsSinceEpoch;
        final lote = _outbox.pendientes(ahoraMs: ahora, limite: 10);
        if (lote.isEmpty) break;

        for (final tarea in lote) {
          try {
            await _subir(tarea);
            await _outbox.completar(tarea.id);
          } catch (e) {
            await _outbox.fallar(tarea, e,
                ahoraMs: DateTime.now().millisecondsSinceEpoch);
            // Un fallo suele significar que se ha caído la red: no seguimos
            // martilleando el resto del lote.
            break;
          }
        }
        _refrescarContador();
      }
    } finally {
      _drenando = false;
      _refrescarContador();
    }
  }

  Future<void> _subir(TareaOutbox tarea) async {
    final datos = _almacen.leer(tarea.claveBinario);
    if (datos == null) {
      // El binario ya no está (el auditor borró la evidencia): la tarea deja
      // de tener sentido y se descarta en silencio.
      return;
    }

    await _outbox.marcarSubiendo(tarea.id);
    final ref = _storage.ref(tarea.remotePath);
    await ref.putData(datos, SettableMetadata(contentType: _mime(tarea.tipo)));
    final url = await ref.getDownloadURL();

    await _anotarUrl(tarea, url);

    // Ya está a salvo en el servidor: se libera el espacio local. En iOS el
    // navegador puede desalojar el almacenamiento del sitio si crece mucho,
    // así que conviene no acumular lo que ya no hace falta.
    if (tarea.tipo == TipoTarea.evidencia) {
      await _almacen.borrar(tarea.claveBinario);
    }
  }

  /// Escribe la URL definitiva en Firestore.
  ///
  /// Aquí sí se usa transacción, al contrario que en el resto de la
  /// aplicación: hay que leer el array de evidencias y modificar un elemento
  /// concreto sin pisar los cambios de otra evidencia que se esté subiendo a
  /// la vez. Es seguro porque este código solo corre después de una subida a
  /// Storage que ha funcionado, así que la red existe; y si aun así falla, la
  /// tarea vuelve a la cola y se reintenta.
  Future<void> _anotarUrl(TareaOutbox tarea, String url) async {
    final auditoria = _db.collection('auditorias').doc(tarea.auditoriaId);

    switch (tarea.tipo) {
      case TipoTarea.evidencia:
        final respuesta = auditoria.collection('respuestas').doc(tarea.referencia!);
        await _db.runTransaction((tx) async {
          final snap = await tx.get(respuesta);
          final evidencias = List<Map<String, dynamic>>.from(
              (snap.data()?['evidencias'] as List? ?? const []));
          for (final e in evidencias) {
            if (e['id'] == tarea.id) {
              e['remoteUrl'] = url;
              e['estadoSync'] = 'sincronizada';
            }
          }
          tx.update(respuesta, {'evidencias': evidencias});
        });
      case TipoTarea.informePdf:
        await auditoria.update({
          'pdf.url': url,
          'pdf.storagePath': tarea.remotePath,
        });
      case TipoTarea.firma:
        await auditoria.update({'firmas.${tarea.referencia}.url': url});
    }
  }

  void _refrescarContador({bool? hayRed}) {
    _estado.value = EstadoSincronizacion(
      pendientes: _outbox.pendientesTotales,
      fallidas: _outbox.fallidas,
      trabajando: _drenando,
      hayRed: hayRed ?? _estado.value.hayRed,
    );
  }

  Future<void> reintentarFallidas() async {
    await _outbox.reintentarFallidas();
    await drenar();
  }

  /// Ocupación local pendiente de subir, para mostrarla al auditor.
  int get bytesPendientes => _almacen.bytesOcupados;

  static String _mime(TipoTarea t) =>
      t == TipoTarea.informePdf ? 'application/pdf' : 'image/jpeg';

  Future<void> dispose() async {
    await _subRed?.cancel();
    _reloj?.cancel();
    _estado.dispose();
  }
}
