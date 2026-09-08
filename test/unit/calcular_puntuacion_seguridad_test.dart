import 'package:audit_app/features/auditoria/domain/entities/respuesta.dart';
import 'package:audit_app/features/auditoria/domain/entities/valor_respuesta.dart';
import 'package:audit_app/features/auditoria/domain/usecases/calcular_puntuacion.dart';
import 'package:flutter_test/flutter_test.dart';

/// La revisión de seguridad reutiliza `CalcularPuntuacion` tal cual: es un
/// caso de uso genérico sobre `Respuesta`/`ValorRespuesta`, sin nada propio
/// del cuestionario de postventa. Este test comprueba que se comporta bien
/// con la forma real del checklist de seguridad: una sola área, preguntas de
/// peso 1 y estrictamente Sí/No (nunca "Cumple parcialmente" ni N/A).
Respuesta _r(String id, ValorRespuesta? v) => Respuesta(
      preguntaId: id,
      areaCodigo: 'SEG',
      textoPregunta: 'Pregunta de seguridad $id',
      peso: 1,
      critica: false,
      valor: v,
    );

void main() {
  const uc = CalcularPuntuacion(aplicarTopeCritica: false);
  const pesos = <String, double>{'SEG': 1.0};

  test('con 33 preguntas en Sí, la puntuación es 100 %', () {
    final respuestas = [
      for (var i = 1; i <= 33; i++) _r('seg_$i', ValorRespuesta.cumple),
    ];

    final res = uc(respuestas: respuestas, pesosArea: pesos);

    expect(res.areas['SEG']!.porcentaje, 100.0);
    expect(res.puntuacionGlobal, 100.0);
    expect(res.nivel, 'A');
    expect(res.completa, isTrue);
  });

  test('cada "No" resta lo mismo, al ser todas de peso 1', () {
    final respuestas = [
      for (var i = 1; i <= 30; i++) _r('seg_$i', ValorRespuesta.cumple),
      _r('seg_31', ValorRespuesta.noCumple),
      _r('seg_32', ValorRespuesta.noCumple),
      _r('seg_33', ValorRespuesta.noCumple),
    ];

    final res = uc(respuestas: respuestas, pesosArea: pesos);

    // 30/33 ≈ 90.9 %.
    expect(res.areas['SEG']!.porcentaje, closeTo(90.9, 0.1));
    expect(res.areas['SEG']!.nAplicables, 33);
  });

  test('sin responder todavía no cuenta como fallo, pero baja el progreso', () {
    final respuestas = [
      _r('seg_1', ValorRespuesta.cumple),
      _r('seg_2', null),
    ];

    final res = uc(respuestas: respuestas, pesosArea: pesos);

    expect(res.areas['SEG']!.porcentaje, 100.0);
    expect(res.completa, isFalse);
    expect(res.progresoGlobal, 0.5);
  });
}
