import 'package:hive_ce_flutter/hive_flutter.dart';

enum TipoTarea { evidencia, informePdf, firma }

enum EstadoTarea { pendiente, subiendo, completada, error }

class TareaOutbox {
  const TareaOutbox({
    required this.id,
    required this.tipo,
    required this.auditoriaId,
    required this.claveBinario,
    required this.remotePath,
    this.referencia,
    this.intentos = 0,
    this.proximoIntento = 0,
    this.estado = EstadoTarea.pendiente,
    this.ultimoError,
  });

  final String id;
  final TipoTarea tipo;
  final String auditoriaId;

  /// Clave en AlmacenBinarios, no una ruta de fichero: en el navegador no
  /// hay rutas.
  final String claveBinario;
  final String remotePath;

  /// Discriminante secundario: preguntaId para evidencias, rol para firmas.
  final String? referencia;

  final int intentos;

  /// Epoch ms a partir del cual se puede reintentar (espera exponencial).
  final int proximoIntento;
  final EstadoTarea estado;
  final String? ultimoError;

  TareaOutbox copyWith({
    int? intentos,
    int? proximoIntento,
    EstadoTarea? estado,
    String? ultimoError,
  }) =>
      TareaOutbox(
        id: id,
        tipo: tipo,
        auditoriaId: auditoriaId,
        claveBinario: claveBinario,
        remotePath: remotePath,
        referencia: referencia,
        intentos: intentos ?? this.intentos,
        proximoIntento: proximoIntento ?? this.proximoIntento,
        estado: estado ?? this.estado,
        ultimoError: ultimoError ?? this.ultimoError,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'tipo': tipo.name,
        'auditoriaId': auditoriaId,
        'claveBinario': claveBinario,
        'remotePath': remotePath,
        'referencia': referencia,
        'intentos': intentos,
        'proximoIntento': proximoIntento,
        'estado': estado.name,
        'ultimoError': ultimoError,
      };

  factory TareaOutbox.fromMap(Map<dynamic, dynamic> m) => TareaOutbox(
        id: m['id'] as String,
        tipo: TipoTarea.values.byName(m['tipo'] as String),
        auditoriaId: m['auditoriaId'] as String,
        claveBinario: m['claveBinario'] as String,
        remotePath: m['remotePath'] as String,
        referencia: m['referencia'] as String?,
        intentos: (m['intentos'] as num?)?.toInt() ?? 0,
        proximoIntento: (m['proximoIntento'] as num?)?.toInt() ?? 0,
        estado: EstadoTarea.values.byName(m['estado'] as String? ?? 'pendiente'),
        ultimoError: m['ultimoError'] as String?,
      );
}

/// Cola local persistente de subidas a Firebase Storage.
///
/// Por qué existe: el SDK de Firestore ya encola las escrituras de DOCUMENTOS
/// y las reenvía al recuperar red, incluso tras cerrar la aplicación. Pero
/// Firebase Storage no hace eso: sin cobertura la subida falla y la foto se
/// pierde. En una nave metálica eso pasa constantemente, así que los binarios
/// necesitan su propia cola.
class OutboxStore {
  OutboxStore._(this._caja);

  final Box<Map> _caja;
  static const _nombreCaja = 'outbox';

  /// Tras 8 intentos (unas 4 h de espera acumulada) la tarea se marca en
  /// error y requiere reintento manual desde la interfaz.
  static const int maxIntentos = 8;

  static Future<OutboxStore> abrir() async {
    final caja = await Hive.openBox<Map>(_nombreCaja);
    return OutboxStore._(caja);
  }

  Future<void> encolar(TareaOutbox tarea) => _caja.put(tarea.id, tarea.toMap());

  TareaOutbox? obtener(String id) {
    final m = _caja.get(id);
    return m == null ? null : TareaOutbox.fromMap(m);
  }

  List<TareaOutbox> get _todas => _caja.values.map(TareaOutbox.fromMap).toList();

  /// Tareas listas para intentar ahora mismo, las más antiguas primero.
  List<TareaOutbox> pendientes({required int ahoraMs, int limite = 20}) {
    final listas = _todas
        .where((t) =>
            (t.estado == EstadoTarea.pendiente ||
                t.estado == EstadoTarea.subiendo) &&
            t.proximoIntento <= ahoraMs)
        .toList()
      ..sort((a, b) => a.proximoIntento.compareTo(b.proximoIntento));
    return listas.take(limite).toList();
  }

  int get pendientesTotales =>
      _todas.where((t) => t.estado != EstadoTarea.completada).length;

  /// Tareas agotadas: se muestran en rojo para que el auditor decida.
  int get fallidas => _todas.where((t) => t.estado == EstadoTarea.error).length;

  Future<void> marcarSubiendo(String id) async {
    final t = obtener(id);
    if (t != null) await encolar(t.copyWith(estado: EstadoTarea.subiendo));
  }

  Future<void> completar(String id) => _caja.delete(id);

  /// Espera exponencial con techo: 30 s, 1 min, 2 min, 4 min… hasta 30 min.
  Future<void> fallar(TareaOutbox tarea, Object error, {required int ahoraMs}) {
    final intentos = tarea.intentos + 1;
    return encolar(tarea.copyWith(
      intentos: intentos,
      proximoIntento: ahoraMs + _espera(intentos),
      estado: intentos >= maxIntentos ? EstadoTarea.error : EstadoTarea.pendiente,
      ultimoError: error.toString(),
    ));
  }

  /// Reactiva las tareas agotadas (botón "reintentar" de la interfaz).
  Future<void> reintentarFallidas() async {
    for (final t in _todas.where((t) => t.estado == EstadoTarea.error)) {
      await encolar(t.copyWith(
        estado: EstadoTarea.pendiente,
        intentos: 0,
        proximoIntento: 0,
      ));
    }
  }

  static int _espera(int intentos) {
    const baseMs = 30000;
    const techoMs = 1800000;
    final ms = baseMs * (1 << (intentos - 1).clamp(0, 10));
    return ms > techoMs ? techoMs : ms;
  }
}
