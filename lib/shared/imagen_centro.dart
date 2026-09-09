/// Imagen de fondo para la tarjeta de un centro.
///
/// Cada centro del grupo tiene su propia foto; el que no aparezca en esta
/// lista (o uno nuevo que se dé de alta) cae en una genérica. Comparación sin
/// acentos a propósito: el nombre puede llegar como "Montmeló", "Montmelo" o
/// con mayúsculas distintas según quien lo diera de alta.
const _imagenesPorCentro = {
  'montmelo': 'assets/branding/centro_montmelo.png',
  'martorell': 'assets/branding/centro_martorell.jpg',
  'palma': 'assets/branding/centro_palma.jpg',
  'manresa': 'assets/branding/centro_manresa.jpg',
  'lleida': 'assets/branding/centro_lleida.jpg',
  'cim': 'assets/branding/centro_cim.jpg',
};

String assetImagenCentro(String nombre) {
  final normalizado = nombre
      .toLowerCase()
      .replaceAll('ó', 'o')
      .replaceAll('í', 'i')
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ú', 'u')
      .replaceAll('è', 'e');

  for (final entrada in _imagenesPorCentro.entries) {
    if (normalizado.contains(entrada.key)) return entrada.value;
  }
  return 'assets/branding/centro_generico.webp';
}
