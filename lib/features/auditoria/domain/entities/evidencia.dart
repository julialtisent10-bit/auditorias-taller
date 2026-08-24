import 'dart:typed_data';

enum EstadoSync { pendiente, subiendo, sincronizada, error }

/// Una foto adjunta a una respuesta.
///
/// No guarda la ruta de un fichero: en la PWA no hay sistema de ficheros.
/// Los bytes viven en AlmacenBinarios bajo una clave derivada del [id].
class Evidencia {
  const Evidencia({
    required this.id,
    required this.capturadaEn,
    this.remoteUrl,
    this.bytes = 0,
    this.estadoSync = EstadoSync.pendiente,
    this.miniatura,
  });

  final String id;
  final String? remoteUrl;
  final DateTime capturadaEn;

  /// Tamaño de la imagen completa, en bytes.
  final int bytes;
  final EstadoSync estadoSync;

  /// Miniatura en memoria para pintar la tira de fotos sin ir al almacén en
  /// cada reconstrucción. Es transitoria: NO se serializa a Firestore, donde
  /// engordaría el documento sin aportar nada.
  final Uint8List? miniatura;

  bool get subida => remoteUrl != null && estadoSync == EstadoSync.sincronizada;

  Evidencia copyWith({
    String? remoteUrl,
    EstadoSync? estadoSync,
    Uint8List? miniatura,
  }) =>
      Evidencia(
        id: id,
        capturadaEn: capturadaEn,
        bytes: bytes,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        estadoSync: estadoSync ?? this.estadoSync,
        miniatura: miniatura ?? this.miniatura,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'remoteUrl': remoteUrl,
        'capturadaEn': capturadaEn.toIso8601String(),
        'bytes': bytes,
        'estadoSync': estadoSync.name,
      };

  factory Evidencia.fromJson(Map<String, dynamic> j) => Evidencia(
        id: j['id'] as String,
        remoteUrl: j['remoteUrl'] as String?,
        capturadaEn: DateTime.parse(j['capturadaEn'] as String),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        estadoSync:
            EstadoSync.values.byName(j['estadoSync'] as String? ?? 'pendiente'),
      );
}
