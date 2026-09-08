# Auditorías de taller — vehículo industrial

Aplicación web instalable (PWA) para auditar los centros del grupo con el
cuestionario mensual de postventa: 47 preguntas repartidas en 7 áreas, trabajo
sin cobertura, evidencia fotográfica e informe PDF firmado.

**En producción:** https://julialtisent10-bit.github.io/auditorias-taller/

---

## 1. Instalarla en el móvil

No pasa por App Store ni Play Store: se añade a la pantalla de inicio.

- **iPhone:** abrir la URL en Safari → botón Compartir → *Añadir a pantalla de inicio*
- **Android:** abrir en Chrome → menú ⋮ → *Instalar aplicación*

A partir de ahí se abre a pantalla completa, como una app normal.

## 2. Desarrollo

Requiere Flutter estable (probado con 3.47.1).

```bash
flutter pub get
```

```bash
flutter run -d chrome
```

La configuración de Firebase vive en `lib/firebase_options.dart` y **está
versionada a propósito**: son las claves públicas del cliente web, no
secretos. Firebase lo documenta así; la seguridad real la dan las reglas de
`firestore.rules`.

## 3. Despliegue

Automático. Cada push a `main` dispara `.github/workflows/deploy.yml`, que
compila, pasa los tests y publica en GitHub Pages.

> **No añadir un segundo flujo que despliegue a Pages.** GitHub sugiere uno de
> Jekyll al activar la función; si se acepta, ambos compiten por el mismo
> entorno y gana el último en terminar, con lo que la URL acaba sirviendo el
> README en vez de la aplicación. Ya pasó una vez.

El `--base-href` del flujo es imprescindible: Pages sirve el repo bajo
`/auditorias-taller/`, no en la raíz, y sin ese ajuste la app pide sus propios
ficheros en rutas que no existen y se queda en blanco.

## 4. Si un despliegue rompe la app

Esto se puede arreglar sin ayuda y en dos minutos. **La app siempre se puede
devolver a la última versión que funcionaba.**

### Primero, desde el móvil

Abre la app y espera seis segundos. Si no arranca, la pantalla de carga
ofrece **«Volver a cargar»**: ese botón borra lo guardado en el navegador y
empieza de cero. Resuelve la mayoría de los casos, porque casi siempre lo
roto es la copia local, no lo publicado.

### Si eso no basta, volver a la versión anterior

1. Abre https://github.com/julialtisent10-bit/auditorias-taller/actions
2. Busca en la lista la **última ejecución con el círculo verde** anterior a
   la que rompió las cosas (la fecha te dice cuál)
3. Ábrela y pulsa **«Re-run all jobs»**, arriba a la derecha
4. Espera dos minutos y vuelve a abrir la app

Eso vuelve a publicar el código de ese día tal cual estaba. No se pierde
nada: los datos viven en Firestore, no en la aplicación, así que las
auditorías siguen donde estaban.

> Cada despliegue publica una versión completa y coherente, nunca media. Por
> eso volver atrás es seguro: se sustituye el conjunto entero.

## 5. Cómo puntúa

```
% Área  = Σ(peso × factor) / Σ(peso) × 100     [solo respuestas ≠ N/A]
Global  = Σ(pesoÁrea × %Área) / Σ(pesoÁrea)    [solo áreas evaluables]
```

| Respuesta | En el Excel | Factor |
|---|---|---|
| Cumple | 2 | 1.0 |
| Cumple parcialmente | 1 | 0.5 |
| No cumple | 0 | 0.0 |
| No aplica | N/A | se excluye del cálculo |

**Pesos de área.** Se calculan solos, proporcionales a cuántas preguntas tiene
cada área, de modo que **todas las preguntas valen lo mismo** aunque se añadan
o se retiren desde el editor. Con pesos fijos, retirar tres preguntas de un
área no cambiaba su peso y las que quedaban pasaban a valer más que las de
otra área sin que nada lo advirtiera. Se pueden fijar a mano poniendo
`pesosAutomaticos: false` en la plantilla.

**Preguntas eliminatorias.** Una pregunta marcada `critica: true` respondida
*No cumple* topa su área al **79 %**. El cuestionario actual no usa ninguna,
porque el Excel original no distingue importancia entre preguntas. Se activa
por pregunta desde *Editar cuestionario*.

**La foto nunca es obligatoria.** En un taller hay cosas que no se pueden
fotografiar, y quedarse sin poder cerrar la auditoría por eso no tiene
sentido. La cámara está para cuando la evidencia aporte.

**Niveles:** A ≥ 90 · B ≥ 80 · C ≥ 65 · D < 65.

El cuestionario vive en `assets/plantillas/plantilla_postventa_v1.json`, y una
vez subido a Firestore se edita desde la propia aplicación sin recompilar.

## 6. Dónde vive cada cosa

| Qué | Dónde | Nota |
|---|---|---|
| Respuestas, comentarios, puntuaciones, ranking | Firestore | El SDK persiste en IndexedDB y reenvía solo al recuperar red, incluso tras cerrar la pestaña |
| Fotos, firmas, informes | IndexedDB del navegador | **Solo en este dispositivo** |

### El límite que hay que tener presente

El plan gratuito de Firebase no incluye Cloud Storage, así que **las fotos no
tienen copia en la nube**. Viven en el almacenamiento del navegador, que iOS
puede vaciar si le falta espacio o si el sitio pasa mucho tiempo sin abrirse.

Por eso **el PDF es la copia duradera de la evidencia**: lleva las imágenes
incrustadas. Guardarlo o enviarlo al cerrar cada auditoría no es opcional.

El indicador de la barra superior muestra cuánto ocupa lo guardado en local,
y pasa a ámbar por encima de 40 MB para recordar que hay material sin exportar.

Si algún día se contrata el plan Blaze, recuperar la subida a la nube consiste
en reintroducir una cola de salida: el almacén local (`AlmacenBinarios`) ya
está aislado tras su propia interfaz.

## 7. Estructura

```
lib/
├─ app/           MaterialApp, rutas, tema, inyección de dependencias
├─ core/          arranque de Firebase y almacén local de binarios
├─ features/
│  ├─ auditoria/  el núcleo: cuestionario, scoring, evidencias, firma
│  ├─ centros/    alta de centros y su histórico
│  ├─ plantillas/ carga y validación del cuestionario
│  ├─ ranking/    clasificación entre centros
│  └─ reporte/    generación del PDF: donut de puntuación y barras por área
└─ shared/        widgets reutilizables
```

Cada feature sigue `data / domain / presentation`. La regla que lo sostiene:
**`domain/` no importa Flutter, ni Firebase, ni `dart:io`**. Por eso
`calcular_puntuacion.dart` se testea en milisegundos y sin navegador.

## 8. Tipografía del informe

`assets/fonts/NotoSans-*.ttf` se incrusta en el PDF. Las fuentes internas del
formato PDF usan codificación WinAnsi y **descartan en silencio** cualquier
carácter fuera de Latin-1. Los teclados de móvil generan apóstrofos curvos (’),
guiones largos (—) y puntos suspensivos (…) constantemente, así que sin fuente
incrustada un comentario del auditor llegaría al informe con huecos y sin
ningún aviso.

Noto Sans está bajo SIL Open Font License; el texto va en `assets/fonts/OFL.txt`
y debe distribuirse con la aplicación.

## 9. Logotipo

`assets/branding/scaitt_logo.svg` se tomó del sitio corporativo y se recoloreó
para que se vea sobre fondo blanco. Es una marca de la empresa: úsalo solo para
documentación interna y sustitúyelo por el fichero oficial de marketing si el
informe va a salir fuera.

## 10. Estado de verificación

Comprobado con Flutter 3.47.1 / Dart 3.13.1:

- `dart analyze lib test` · sin incidencias
- `flutter test` · 14 de 14 pruebas correctas
- `flutter build web --release` · compila

**Verificado en uso real:** acceso, alta de centros y lectura de datos contra
el Firebase de producción.

**No verificado todavía:** la cámara, la firma manuscrita y la generación del
PDF en un iPhone. El service worker tampoco se puede comprobar desde un
entorno de desarrollo: hay que probarlo en el dispositivo.
