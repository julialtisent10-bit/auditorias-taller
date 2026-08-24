import 'dart:typed_data';

/// Una foto adjunta a una respuesta.
///
/// Los bytes viven SOLO en AlmacenBinarios, en este dispositivo, bajo una
/// clave derivada del [id]. No hay copia en la nube: el plan gratuito de
/// Firebase no incluye Cloud Storage.
///
/// Lo que se guarda en Firestore es únicamente el registro de que la foto
/// existió (id, fecha, tamaño), para que el histórico refleje que hubo
/// evidencia aunque el dispositivo original ya no la tenga. La copia
/// duradera de la imagen es el PDF que se genera al cerrar la auditoría.
class Evidencia {
  const Evidencia({
    required this.id,
    required this.capturadaEn,
    this.bytes = 0,
    this.miniatura,
  });

  final String id;
  final DateTime capturadaEn;

  /// Tamaño de la imagen completa, en bytes.
  final int bytes;

  /// Miniatura en memoria para pintar la tira de fotos sin ir al almacén en
  /// cada reconstrucción. Es transitoria: NO se serializa a Firestore, donde
  /// engordaría el documento sin aportar nada.
  final Uint8List? miniatura;

  Evidencia copyWith({Uint8List? miniatura}) => Evidencia(
        id: id,
        capturadaEn: capturadaEn,
        bytes: bytes,
        miniatura: miniatura ?? this.miniatura,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'capturadaEn': capturadaEn.toIso8601String(),
        'bytes': bytes,
      };

  factory Evidencia.fromJson(Map<String, dynamic> j) => Evidencia(
        id: j['id'] as String,
        capturadaEn: DateTime.parse(j['capturadaEn'] as String),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      );
}
