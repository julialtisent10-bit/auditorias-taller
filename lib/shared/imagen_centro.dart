/// Imagen de fondo para la tarjeta de un centro.
///
/// Montmeló repara remolques Schmitz, así que lleva la foto de ese fabricante;
/// el resto de centros (turismo/industrial Scania) comparten una genérica.
/// Sin acentuar la comparación a propósito: el nombre puede llegar como
/// "Montmeló", "Montmelo" o con mayúsculas distintas según quien lo diera de
/// alta.
String assetImagenCentro(String nombre) {
  final normalizado = nombre
      .toLowerCase()
      .replaceAll('ó', 'o')
      .replaceAll('í', 'i')
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ú', 'u');
  return normalizado.contains('montmelo')
      ? 'assets/branding/centro_montmelo.webp'
      : 'assets/branding/centro_generico.webp';
}
