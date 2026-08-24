# Auditorías de taller — vehículo industrial

App móvil para auditar los centros del grupo en 4 áreas (Administración,
Asesores de Servicio, Recambios y Taller), con trabajo offline, evidencia
fotográfica e informe PDF firmado.

---

## 1. Requisitos

- Flutter estable (probado con 3.47.1)
- Una cuenta de Google para crear el proyecto Firebase
- Android Studio (SDK de Android) o Xcode si vas a compilar para iOS

## 2. Puesta en marcha

```bash
flutter create . --org com.scaitt --platforms android,ios
```

Ese comando **no borra** `lib/`, `assets/` ni `pubspec.yaml`: solo genera las
carpetas nativas `android/` e `ios/` que faltan.

```bash
flutter pub get
```

### 2.1 Firebase (este paso lo haces tú, necesita tu cuenta)

```bash
dart pub global activate flutterfire_cli
```

```bash
flutterfire configure --project=<id-de-tu-proyecto>
```

Genera `lib/firebase_options.dart` y coloca `google-services.json` y
`GoogleService-Info.plist` en su sitio. Después, en la consola de Firebase:

1. **Authentication** → activar *Correo electrónico/contraseña* y crear tu usuario.
2. **Firestore Database** → crear en modo producción, región `eur3`.
3. **Storage** → crear bucket.
4. Publicar las reglas incluidas en el repo:

```bash
firebase deploy --only firestore:rules,storage:rules
```

> `firebase_bootstrap.dart` llama a `Firebase.initializeApp()` sin opciones.
> Si `flutterfire configure` genera `firebase_options.dart`, cambia esa línea
> por `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.

### 2.2 Cargar el cuestionario en Firestore

La plantilla vive en `assets/plantillas/plantilla_taller_vi_v1.json` y la app
funciona solo con ella. Para poder editar preguntas desde la consola de
Firebase sin recompilar, súbela una vez:

```dart
await PlantillaRepository().sembrarEnFirestore();
```

### 2.3 Permisos nativos

`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Para adjuntar evidencia fotográfica a las auditorías.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Para adjuntar fotos existentes como evidencia.</string>
```

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

## 3. Comprobar que funciona

```bash
flutter test
```

```bash
flutter run
```

---

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
Taller 30 %. Se editan en el JSON de la plantilla; deben sumar 1.0 y la app
se niega a cargar una plantilla donde no sumen.

**Regla de crítica:** una pregunta marcada `critica: true` respondida
*No cumple* topa su área al **79 %**. Sin esta regla un fallo de EPIs queda
diluido entre 30 preguntas correctas. Se desactiva con
`CalcularPuntuacion(aplicarTopeCritica: false)`.

**Niveles:** A ≥ 90 · B ≥ 80 · C ≥ 65 · D < 65.

## 5. Por qué funciona sin cobertura

| Qué | Dónde | Motivo |
|---|---|---|
| Respuestas, comentarios, resultados | Firestore directo | El SDK persiste en disco y reenvía solo al recuperar red, incluso tras cerrar la app. |
| Fotos, PDF, firmas | SQLite (`core/sync/`) | **Firebase Storage no tiene cola offline**: sin red la subida falla y el fichero se pierde. |

La cola reintenta con espera exponencial (30 s → 30 min, 8 intentos) y sube
**en serie**: 8 fotos en paralelo por 4G desde un polígono fallan todas.

El icono de nube de la barra superior indica cuántos ficheros quedan por
subir. Mientras haya número, esas fotos solo existen en el móvil.

## 6. Estructura

```
lib/
├─ app/           MaterialApp, rutas, tema, inyección de dependencias
├─ core/          Firebase bootstrap y cola de sincronización
├─ features/
│  ├─ auditoria/  el núcleo: cuestionario, scoring, evidencias, firma
│  ├─ centros/    alta de centros y su histórico
│  ├─ plantillas/ carga y validación del cuestionario
│  ├─ ranking/    clasificación entre centros
│  └─ reporte/    generación del PDF y gráfico de araña
└─ shared/        widgets reutilizables
```

Cada feature sigue `data / domain / presentation`. Regla que sostiene todo:
**`domain/` no importa Flutter, ni Firebase, ni `dart:io`**. Por eso
`calcular_puntuacion.dart` se puede testear en milisegundos y sin emulador.

## 7. Tipografía del informe

`assets/fonts/NotoSans-*.ttf` se incrusta en el PDF. Las fuentes internas del
formato PDF (Helvetica y compañía) usan codificación WinAnsi y **descartan en
silencio** cualquier carácter fuera de Latin-1. Los teclados de móvil generan
apóstrofos curvos (’), guiones largos (—) y puntos suspensivos tipográficos
(…) constantemente, así que sin fuente incrustada un comentario del auditor
llegaría al informe con caracteres perdidos y sin ningún aviso.

Noto Sans está bajo SIL Open Font License; el texto de la licencia va en
`assets/fonts/OFL.txt` y debe distribuirse con la aplicación.

Si la carga de fuentes falla, el informe se genera igual con las internas:
mejor un PDF imperfecto que ningún PDF.

## 8. Licencia del logotipo

`assets/branding/scaitt_logo.svg` se ha tomado del sitio corporativo y
recoloreado para que se vea sobre fondo blanco. Es una marca de la empresa:
úsalo solo para documentación interna del grupo y sustitúyelo por el fichero
oficial de marketing si el informe va a salir fuera.

## 9. Estado de verificación

Comprobado con Flutter 3.47.1 / Dart 3.13.1:

- `dart analyze lib test` · **sin incidencias**
- `flutter test` · **14 de 14 pruebas correctas**

Lo que **no** está verificado: la app no se ha ejecutado en un dispositivo
real, porque eso exige el proyecto Firebase configurado (paso 2.1). La cámara,
la sincronización con Storage y la firma manuscrita están escritas pero sin
probar contra hardware.
