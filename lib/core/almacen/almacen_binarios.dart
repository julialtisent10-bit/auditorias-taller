import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';

/// Almacén local de ficheros binarios: fotos, firmas e informes.
///
/// Por qué no se usa el sistema de ficheros: la aplicación se despliega como
/// PWA y en el navegador no existe `dart:io`. Hive escribe sobre IndexedDB en
/// web y sobre ficheros en móvil, con la misma API, así que el resto del
/// código no tiene que saber en cuál de los dos está corriendo.
///
/// Consecuencia de diseño: una evidencia ya no es una ruta, es una CLAVE.
/// Quien necesite los bytes se los pide a este almacén.
class AlmacenBinarios {
  AlmacenBinarios._(this._caja);

  final Box<Uint8List> _caja;

  static const _nombreCaja = 'binarios';

  static Future<AlmacenBinarios> abrir() async {
    final caja = await Hive.openBox<Uint8List>(_nombreCaja);
    return AlmacenBinarios._(caja);
  }

  // --- Convenciones de clave. Centralizadas aquí para que no se inventen
  // --- rutas por ahí sueltas y luego no haya forma de limpiar por auditoría.

  static String claveEvidencia(String evidenciaId) => 'ev/$evidenciaId';
  static String claveMiniatura(String evidenciaId) => 'ev/$evidenciaId/min';
  static String claveInforme(String auditoriaId) => 'pdf/$auditoriaId';
  static String claveFirma(String auditoriaId, String rol) =>
      'firma/$auditoriaId/$rol';

  Future<void> guardar(String clave, Uint8List datos) => _caja.put(clave, datos);

  Uint8List? leer(String clave) => _caja.get(clave);

  Future<void> borrar(String clave) => _caja.delete(clave);

  Future<void> borrarEvidencia(String evidenciaId) async {
    await _caja.delete(claveEvidencia(evidenciaId));
    await _caja.delete(claveMiniatura(evidenciaId));
  }

  bool existe(String clave) => _caja.containsKey(clave);

  /// Ocupación aproximada. La usa la pantalla de sincronización: en iOS el
  /// navegador puede desalojar el almacenamiento del sitio, así que conviene
  /// que el auditor vea cuánto tiene pendiente de subir.
  int get bytesOcupados =>
      _caja.values.fold<int>(0, (suma, datos) => suma + datos.lengthInBytes);

  int get numeroElementos => _caja.length;

  /// Libera lo que ya está en el servidor. Se llama tras confirmar la subida.
  Future<void> purgar(Iterable<String> claves) => _caja.deleteAll(claves);
}
