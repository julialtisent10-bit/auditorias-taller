'use strict';

// Service worker propio.
//
// Flutter dejó de generar uno que guarde la aplicación: el suyo se limita a
// desregistrarse y recargar la página, lo que dejaba la app inservible sin
// cobertura, que es justo la situación para la que se hizo. Este la guarda
// entera en el navegador para que abra dentro de una nave sin señal.
//
// La versión la sustituye el flujo de publicación por el identificador del
// commit, de modo que cada despliegue estrena almacén y no quedan restos del
// anterior mezclados.
const VERSION = '__VERSION__';
const ALMACEN = `auditorias-${VERSION}`;

// Lo imprescindible para arrancar. El resto (canvaskit, fuentes, imágenes) se
// va guardando conforme se pide: enumerarlo aquí obligaría a mantener a mano
// una lista que cambia en cada compilación.
const ESENCIALES = [
  './',
  'index.html',
  'manifest.json',
  'flutter_bootstrap.js',
  'favicon.png',
  'icons/Icon-192.png',
];

self.addEventListener('install', (evento) => {
  evento.waitUntil(
    caches.open(ALMACEN).then(async (almacen) => {
      // Con `reload` se evita que el propio navegador sirva una copia vieja
      // de su caché HTTP al rellenar la nuestra.
      //
      // Si alguno de los imprescindibles falla al guardarse, esta versión
      // quedaría a medio instalar: capaz de activarse pero incapaz de
      // arrancar. Se comprueba explícitamente y, si falta algo, se aborta la
      // instalación entera para que el usuario se quede en la versión
      // anterior —que sí funciona— en vez de heredar una rota.
      await almacen.addAll(ESENCIALES.map((u) => new Request(u, { cache: 'reload' })));
      const guardados = await Promise.all(ESENCIALES.map((u) => almacen.match(u)));
      if (guardados.some((r) => !r)) {
        await caches.delete(ALMACEN);
        throw new Error('No se pudieron guardar todos los ficheros imprescindibles');
      }
    })
  );
  // No se llama a skipWaiting aquí a propósito: la versión nueva espera a que
  // el usuario acepte, para no cambiarle la aplicación bajo los pies en mitad
  // de una auditoría.
});

self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    (async () => {
      const nombres = await caches.keys();
      await Promise.all(
        nombres
          .filter((n) => n.startsWith('auditorias-') && n !== ALMACEN)
          .map((n) => caches.delete(n))
      );
      await self.clients.claim();
    })()
  );
});

// La página pide el relevo cuando el usuario pulsa «Actualizar».
self.addEventListener('message', (evento) => {
  if (evento.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (evento) => {
  const peticion = evento.request;
  if (peticion.method !== 'GET') return;

  const url = new URL(peticion.url);

  // Todo lo de fuera va directo a la red sin tocar: Firestore y la
  // autenticación llevan su propia gestión de estado y guardarles las
  // respuestas rompería la sesión y los datos.
  if (url.origin !== self.location.origin) return;

  // Navegación: también desde lo guardado, igual que el resto.
  //
  // Antes iba a la red primero, y ahí estaba el fallo: tras un despliegue se
  // servía el index.html NUEVO mientras los ficheros que este pide seguían
  // saliendo de la caché VIEJA. La aplicación arrancaba con el HTML de una
  // versión y el código de otra, no encajaban, y la pantalla se quedaba en
  // gris sin ningún error visible.
  //
  // Sirviendo también la navegación desde la caché, el usuario se queda con
  // una versión entera y coherente hasta que acepta el aviso de actualizar,
  // que es cuando se cambian todos los ficheros a la vez.
  if (peticion.mode === 'navigate') {
    evento.respondWith(
      caches.match('index.html', { ignoreSearch: true }).then(
        (guardado) => guardado || fetch(peticion)
      )
    );
    return;
  }

  // El resto: primero lo guardado, que es lo que hace que arranque sin red, y
  // en paralelo se refresca la copia para la próxima vez.
  evento.respondWith(
    caches.match(peticion, { ignoreSearch: true }).then((guardado) => {
      const enRed = fetch(peticion)
        .then((respuesta) => {
          if (respuesta && respuesta.status === 200 && respuesta.type === 'basic') {
            const copia = respuesta.clone();
            caches.open(ALMACEN).then((almacen) => almacen.put(peticion, copia));
          }
          return respuesta;
        })
        .catch(() => guardado);

      return guardado || enRed;
    })
  );
});
