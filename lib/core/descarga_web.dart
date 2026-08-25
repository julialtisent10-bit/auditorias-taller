import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Entrega un fichero al usuario desde el navegador.
///
/// En una aplicación web no se puede «guardar en disco»: hay que crear un
/// enlace a un blob en memoria y pulsarlo por código, que es lo que el
/// navegador entiende como una descarga. La URL se libera después para no
/// dejar el blob retenido en memoria mientras dure la sesión.
void descargarBytes(Uint8List datos, String nombre, String tipoMime) {
  final blob = web.Blob(
    [datos.toJS].toJS,
    web.BlobPropertyBag(type: tipoMime),
  );
  final url = web.URL.createObjectURL(blob);

  final enlace = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nombre;

  // Hay que insertarlo en el documento: Safari ignora el clic sobre un
  // elemento que no está en el árbol.
  web.document.body!.append(enlace);
  enlace.click();
  enlace.remove();

  web.URL.revokeObjectURL(url);
}
