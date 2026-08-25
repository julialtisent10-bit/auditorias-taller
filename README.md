# Auditorías de taller — vehículo industrial

Aplicación web instalable (PWA) para auditar los centros del grupo en 4 áreas
—Administración, Asesores de Servicio, Recambios y Taller— con trabajo sin
cobertura, evidencia fotográfica e informe PDF firmado.

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

## 4. Cómo puntúa

```
% Área  = Σ(peso × factor) / Σ(peso) × 100     [solo respuestas ≠ N/A]
Global  = Σ(pesoÁrea × %Área) / Σ(pesoÁrea)    [solo áreas evaluables]
```

| Respuesta | Factor |
|---|---|
| Cumple | 1.0 |
| Cumple parcialmente | 0.5 |
| No cumple | 0.0 |
| No aplica | se excluye del cálculo |

**Pesos de pregunta:** 3 = crítica · 2 = importante · 1 = normal.

**Pesos de área:** Administración 20 % · Asesores 30 % · Recambios 20 % ·
Taller 30 %. Se editan en `assets/plantillas/plantilla_taller_vi_v1.json`;
deben sumar 1.0 y la app se niega a cargar una plantilla donde no sumen.

**Regla de crítica:** una pregunta marcada `critica: true` respondida
*No cumple* topa su área al **79 %**. Sin esta regla un fallo de EPIs queda
diluido entre 30 preguntas correctas. Se desactiva con
`CalcularPuntuacion(aplicarTopeCritica: false)`.

**Niveles:** A ≥ 90 · B ≥ 80 · C ≥ 65 · D < 65.

## 5. Dónde vive cada cosa

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

## 6. Estructura

```
lib/
├─ app/           MaterialApp, rutas, tema, inyección de dependencias
├─ core/          arranque de Firebase y almacén local de binarios
├─ features/
│  ├─ auditoria/  el núcleo: cuestionario, scoring, evidencias, firma
│  ├─ centros/    alta de centros y su histórico
│  ├─ plantillas/ carga y validación del cuestionario
│  ├─ ranking/    clasificación entre centros
│  └─ reporte/    generación del PDF y gráfico de araña
└─ shared/        widgets reutilizables
```

Cada feature sigue `data / domain / presentation`. La regla que lo sostiene:
**`domain/` no importa Flutter, ni Firebase, ni `dart:io`**. Por eso
`calcular_puntuacion.dart` se testea en milisegundos y sin navegador.

## 7. Tipografía del informe

`assets/fonts/NotoSans-*.ttf` se incrusta en el PDF. Las fuentes internas del
formato PDF usan codificación WinAnsi y **descartan en silencio** cualquier
carácter fuera de Latin-1. Los teclados de móvil generan apóstrofos curvos (’),
guiones largos (—) y puntos suspensivos (…) constantemente, así que sin fuente
incrustada un comentario del auditor llegaría al informe con huecos y sin
ningún aviso.

Noto Sans está bajo SIL Open Font License; el texto va en `assets/fonts/OFL.txt`
y debe distribuirse con la aplicación.

## 8. Logotipo

`assets/branding/scaitt_logo.svg` se tomó del sitio corporativo y se recoloreó
para que se vea sobre fondo blanco. Es una marca de la empresa: úsalo solo para
documentación interna y sustitúyelo por el fichero oficial de marketing si el
informe va a salir fuera.

## 9. Estado de verificación

Comprobado con Flutter 3.47.1 / Dart 3.13.1:

- `dart analyze lib test` · sin incidencias
- `flutter test` · 14 de 14 pruebas correctas
- `flutter build web --release` · compila

**No verificado todavía:** el flujo completo contra el Firebase real. La
cámara, la firma manuscrita y el guardado en Firestore están escritos pero sin
probar con un usuario autenticado en un dispositivo real.
