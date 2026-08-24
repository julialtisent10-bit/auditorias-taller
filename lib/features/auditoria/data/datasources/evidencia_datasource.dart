import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/almacen/almacen_binarios.dart';
import '../../domain/entities/evidencia.dart';

/// Captura y comprime evidencias.
///
/// NUNCA sube nada aquí: los bytes quedan en el almacén local y la cola de
/// outbox los sincroniza cuando hay red. En un taller con naves metálicas no
/// se puede dar por hecha la cobertura.
///
/// El redimensionado va con el paquete `image`, en Dart puro, y no con
/// flutter_image_compress: aquel es código nativo y no existe en el navegador.
class EvidenciaDataSource {
  EvidenciaDataSource({required AlmacenBinarios almacen, ImagePicker? picker})
      : _almacen = almacen,
        _picker = picker ?? ImagePicker();

  final AlmacenBinarios _almacen;
  final ImagePicker _picker;
  static const _uuid = Uuid();

  /// ~1600 px de lado largo y calidad 72 deja fotos de 150-250 KB: legibles
  /// como prueba en el informe y baratas de subir por 4G desde el taller.
  static const int ladoMaximo = 1600;
  static const int calidad = 72;

  /// La miniatura es lo único que se mantiene en memoria mientras dura la
  /// auditoría. A 240 px son unos 10 KB por foto: con 160 evidencias siguen
  /// siendo menos de 2 MB, mientras que las completas pasarían de 30.
  static const int ladoMiniatura = 240;
  static const int calidadMiniatura = 60;

  Future<Evidencia?> capturar({required bool desdeCamara}) async {
    final XFile? origen = await _picker.pickImage(
      source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
      maxWidth: ladoMaximo.toDouble(),
      imageQuality: 90, // primer recorte; el fino lo hace el redimensionado
    );
    if (origen == null) return null;

    final original = await origen.readAsBytes();
    final decodificada = img.decodeImage(original);
    if (decodificada == null) return null;

    final completa = _reescalar(decodificada, ladoMaximo, calidad);
    final miniatura = _reescalar(decodificada, ladoMiniatura, calidadMiniatura);

    final id = _uuid.v4();
    await _almacen.guardar(AlmacenBinarios.claveEvidencia(id), completa);
    await _almacen.guardar(AlmacenBinarios.claveMiniatura(id), miniatura);

    return Evidencia(
      id: id,
      capturadaEn: DateTime.now(),
      bytes: completa.lengthInBytes,
      estadoSync: EstadoSync.pendiente,
      miniatura: miniatura,
    );
  }

  Future<void> eliminar(Evidencia evidencia) =>
      _almacen.borrarEvidencia(evidencia.id);

  /// Bytes de la imagen completa. Los usan el informe y la subida.
  Uint8List? completa(String evidenciaId) =>
      _almacen.leer(AlmacenBinarios.claveEvidencia(evidenciaId));

  Uint8List? miniatura(String evidenciaId) =>
      _almacen.leer(AlmacenBinarios.claveMiniatura(evidenciaId));

  static Uint8List _reescalar(img.Image origen, int ladoMaximo, int calidad) {
    // Solo se reduce, nunca se amplía: reescalar hacia arriba una foto ya
    // pequeña añade peso sin añadir un solo detalle.
    final necesitaReducir =
        origen.width > ladoMaximo || origen.height > ladoMaximo;

    final destino = necesitaReducir
        ? img.copyResize(
            origen,
            width: origen.width >= origen.height ? ladoMaximo : null,
            height: origen.height > origen.width ? ladoMaximo : null,
            interpolation: img.Interpolation.average,
          )
        : origen;

    // JPEG y no PNG: una foto de taller en PNG pesa cinco veces más.
    return img.encodeJpg(destino, quality: calidad);
  }

  /// Ruta destino en Firebase Storage. La usa el trabajador de la cola.
  static String rutaStorage(
          String auditoriaId, String preguntaId, String evidenciaId) =>
      'auditorias/$auditoriaId/$preguntaId/$evidenciaId.jpg';
}
