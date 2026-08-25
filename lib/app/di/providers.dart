import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auditoria/presentation/providers/auditoria_controller.dart';

import '../../core/almacen/almacen_binarios.dart';
import '../../shared/area_vista.dart';
import '../../features/auditoria/data/datasources/evidencia_datasource.dart';
import '../../features/auditoria/data/repositories/auditoria_repository_impl.dart';
import '../../features/auditoria/domain/entities/auditoria.dart';
import '../../features/auditoria/domain/repositories/auditoria_repository.dart';
import '../../features/centros/data/repositories/centro_repository.dart';
import '../../features/centros/domain/entities/centro.dart';
import '../../features/plantillas/data/repositories/plantilla_repository.dart';
import '../../features/plantillas/domain/entities/plantilla.dart';
import '../../features/reporte/domain/usecases/generar_reporte.dart';

/// Se sobrescribe en main() con la instancia ya inicializada.
final almacenProvider = Provider<AlmacenBinarios>(
    (ref) => throw UnimplementedError('Sobrescribir en ProviderScope'));

final evidenciaDataSourceProvider = Provider<EvidenciaDataSource>(
    (ref) => EvidenciaDataSource(almacen: ref.watch(almacenProvider)));

final centroRepositoryProvider = Provider<CentroRepository>((ref) => CentroRepository());

final plantillaRepositoryProvider =
    Provider<PlantillaRepository>((ref) => PlantillaRepository());

final auditoriaRepositoryProvider = Provider<AuditoriaRepository>((ref) {
  return AuditoriaRepositoryImpl(
    evidencias: ref.watch(evidenciaDataSourceProvider),
    almacen: ref.watch(almacenProvider),
  );
});

final generarReporteProvider = Provider<GenerarReporte>((ref) => const GenerarReporte());

// ------------------------------------------------------------------- sesión

final usuarioProvider = StreamProvider<User?>(
    (ref) => FirebaseAuth.instance.authStateChanges());

/// Nombre a mostrar del auditor. Si el usuario no tiene displayName se cae
/// al correo, que siempre existe, antes que dejar el informe sin firmar.
final auditorNombreProvider = Provider<String>((ref) {
  final u = ref.watch(usuarioProvider).value;
  return u?.displayName?.trim().isNotEmpty == true
      ? u!.displayName!
      : (u?.email ?? 'Auditor');
});

final auditorUidProvider = Provider<String>((ref) {
  return ref.watch(usuarioProvider).value?.uid ?? 'anonimo';
});

// -------------------------------------------------------------------- datos

final centrosProvider = StreamProvider<List<Centro>>(
    (ref) => ref.watch(centroRepositoryProvider).observar());

/// Cabecera de la auditoría en curso: centro, responsables, firmas.
/// La sesión de respuestas vive aparte, en `sesionAbiertaProvider`.
final auditoriaActualProvider = StateProvider<Auditoria?>((ref) => null);

final plantillaProvider = FutureProvider.family<Plantilla, String?>(
    (ref, plantillaId) =>
        ref.watch(plantillaRepositoryProvider).cargar(plantillaId: plantillaId));

/// Histórico global de auditorías cerradas. Alimenta la pantalla de ranking.
final historicoProvider = StreamProvider<List<Auditoria>>(
    (ref) => ref.watch(auditoriaRepositoryProvider).historico());

/// Auditorías abiertas del usuario actual, para poder retomarlas.
final enCursoProvider = StreamProvider<List<Auditoria>>((ref) => ref
    .watch(auditoriaRepositoryProvider)
    .enCurso(auditorUid: ref.watch(auditorUidProvider)));

/// Reabre una auditoría a medias: recarga su plantilla y sus respuestas ya
/// guardadas, y deja la sesión lista para continuar donde se dejó.
Future<void> reanudarAuditoria(WidgetRef ref, Auditoria auditoria) async {
  final plantilla = await ref
      .read(plantillaRepositoryProvider)
      .cargar(plantillaId: auditoria.plantillaId);

  final respuestas =
      await ref.read(auditoriaRepositoryProvider).respuestasDe(auditoria.id);

  ref.read(auditoriaActualProvider.notifier).state = auditoria;
  ref.read(sesionAbiertaProvider.notifier).state = AuditoriaState.desde(
    auditoriaId: auditoria.id,
    centroNombre: auditoria.centroNombre,
    fecha: auditoria.fecha,
    preguntas: plantilla.preguntas,
    pesosArea: plantilla.pesosArea,
    areas: AreaVista.listaDesde(plantilla.areas),
    respuestasPrevias: respuestas,
  );
}

/// Ranking: última auditoría cerrada de cada centro, de mayor a menor.
///
/// Se calcula en el cliente porque Firestore no agrupa. Con 5-10 centros es
/// instantáneo; si el grupo creciera a cientos, tocaría una Cloud Function
/// que mantuviera una colección `ranking` ya agregada.
final rankingProvider = Provider<List<Auditoria>>((ref) {
  final historico = ref.watch(historicoProvider).value ?? const [];
  final ultimaPorCentro = <String, Auditoria>{};
  for (final a in historico) {
    final actual = ultimaPorCentro[a.centroId];
    if (actual == null || a.fecha.isAfter(actual.fecha)) {
      ultimaPorCentro[a.centroId] = a;
    }
  }
  return ultimaPorCentro.values.toList()
    ..sort((x, y) => y.puntuacionGlobal.compareTo(x.puntuacionGlobal));
});
