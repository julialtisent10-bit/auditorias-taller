import 'package:audit_app/app/di/providers.dart';
import 'package:audit_app/features/auditoria/domain/entities/auditoria.dart';
import 'package:audit_app/features/auditoria/domain/entities/evidencia.dart';
import 'package:audit_app/features/auditoria/domain/entities/pregunta.dart';
import 'package:audit_app/features/auditoria/domain/entities/respuesta.dart';
import 'package:audit_app/features/auditoria/domain/repositories/auditoria_repository.dart';
import 'package:audit_app/features/auditoria/domain/usecases/calcular_puntuacion.dart';
import 'package:audit_app/features/auditoria/presentation/pages/cuestionario_page.dart';
import 'package:audit_app/features/auditoria/presentation/providers/auditoria_controller.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio en memoria: el test no debe tocar Firebase ni la cámara.
class RepoFalso implements AuditoriaRepository {
  final guardadas = <String, Respuesta>{};

  @override
  Future<void> guardarRespuesta(String auditoriaId, Respuesta respuesta) async {
    guardadas[respuesta.preguntaId] = respuesta;
  }

  @override
  Future<void> guardarResultados(String a, ResultadoAuditoria r) async {}

  @override
  Future<Evidencia?> capturarEvidencia({
    required String auditoriaId,
    required String preguntaId,
    required bool desdeCamara,
  }) async =>
      null;

  @override
  Future<void> eliminarEvidencia(String a, String p, Evidencia e) async {}

  @override
  Future<Auditoria> crear({
    required String centroId,
    required String centroNombre,
    required String plantillaId,
    required int plantillaVersion,
    required DateTime fecha,
    required String auditorUid,
    required String auditorNombre,
    required Map<String, String> responsables,
  }) =>
      throw UnimplementedError();

  @override
  Future<Auditoria?> obtener(String auditoriaId) async => null;

  @override
  Future<List<Respuesta>> respuestasDe(String auditoriaId) async => [];

  @override
  Stream<List<Auditoria>> historico({String? centroId, int limite = 50}) =>
      const Stream.empty();

  @override
  Stream<List<Auditoria>> enCurso({required String auditorUid, int limite = 20}) =>
      const Stream.empty();

  @override
  Future<void> finalizar(
    String auditoriaId, {
    required ResultadoAuditoria resultado,
    required Firma firmaAuditor,
    required Firma firmaGerente,
    required Uint8List pdf,
  }) async {}
}

final preguntas = <Pregunta>[
  const Pregunta(
    id: 'q1',
    areaCodigo: 'taller',
    bloque: 'Seguridad',
    orden: 1,
    texto: 'Todo el personal utiliza calzado de seguridad',
    peso: 3,
    critica: true,
    permiteNA: false,
    fotoObligatoriaSi: [],
  ),
  const Pregunta(
    id: 'q2',
    areaCodigo: 'taller',
    bloque: 'Seguridad',
    orden: 2,
    texto: 'El botiquín está completo',
    peso: 1,
    fotoObligatoriaSi: [],
  ),
];

const pesos = <String, double>{
  'administracion': 0.20,
  'asesores': 0.30,
  'recambios': 0.20,
  'taller': 0.30,
};

Widget montar(RepoFalso repo) {
  final estado = AuditoriaState.desde(
    auditoriaId: 'a1',
    centroNombre: 'Centro de prueba',
    fecha: DateTime(2026, 8, 21),
    preguntas: preguntas,
    pesosArea: pesos,
  );

  return ProviderScope(
    overrides: [
      auditoriaRepositoryProvider.overrideWithValue(repo),
      sesionAbiertaProvider.overrideWith((ref) => estado),
    ],
    child: const MaterialApp(home: CuestionarioPage()),
  );
}

void main() {
  testWidgets('muestra las 4 pestañas de área', (tester) async {
    await tester.pumpWidget(montar(RepoFalso()));
    await tester.pumpAndSettle();

    expect(find.text('Administración'), findsOneWidget);
    expect(find.text('Asesores'), findsOneWidget);
    expect(find.text('Recambios'), findsOneWidget);
    expect(find.text('Taller'), findsOneWidget);
  });

  testWidgets('responder actualiza la puntuación global y persiste', (tester) async {
    final repo = RepoFalso();
    await tester.pumpWidget(montar(repo));
    await tester.pumpAndSettle();

    // La pestaña de Taller es la cuarta; sus preguntas son las del test.
    await tester.tap(find.text('Taller'));
    await tester.pumpAndSettle();

    expect(find.text('Todo el personal utiliza calzado de seguridad'), findsOneWidget);

    await tester.tap(find.text('Cumple').first);
    await tester.pumpAndSettle();

    expect(repo.guardadas['q1']?.valor?.codigo, 'CUMPLE');
    expect(find.textContaining('Global 100.0%'), findsOneWidget);
  });

  testWidgets('No cumple en una crítica se avisa en la cabecera del área',
      (tester) async {
    final repo = RepoFalso();
    await tester.pumpWidget(montar(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Taller'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No cumple').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('crítica(s) incumplida(s)'), findsOneWidget);

    // Aquí NO aparece el aviso de tope: con la crítica fallada el área saca
    // un 0 %, y el tope del 79 % solo recorta cuando la media sale por
    // encima. Ese caso se cubre en el test unitario del cálculo, que puede
    // montar las 30 preguntas correctas que hacen falta para provocarlo.
    expect(find.textContaining('topada al 79%'), findsNothing);
  });
}
