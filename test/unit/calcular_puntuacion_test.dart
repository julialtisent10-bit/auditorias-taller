import 'package:flutter_test/flutter_test.dart';
import 'package:audit_app/features/auditoria/domain/entities/respuesta.dart';
import 'package:audit_app/features/auditoria/domain/entities/valor_respuesta.dart';
import 'package:audit_app/features/auditoria/domain/usecases/calcular_puntuacion.dart';

var _seq = 0;

Respuesta _r(String area, int peso, ValorRespuesta? v, {bool critica = false}) {
  _seq++;
  return Respuesta(
    preguntaId: 'q_$_seq',
    areaCodigo: area,
    textoPregunta: 'pregunta de prueba',
    peso: peso,
    critica: critica,
    valor: v,
  );
}

const pesos = <String, double>{
  'administracion': 0.20,
  'asesores': 0.30,
  'recambios': 0.20,
  'taller': 0.30,
};

void main() {
  const uc = CalcularPuntuacion();

  test('N/A se excluye del denominador y no penaliza', () {
    final res = uc(
      respuestas: [
        _r('taller', 3, ValorRespuesta.cumple),
        _r('taller', 3, ValorRespuesta.noAplica),
      ],
      pesosArea: pesos,
    );
    expect(res.areas['taller']!.porcentaje, 100.0);
    expect(res.areas['taller']!.puntosPosibles, 3.0);
    expect(res.areas['taller']!.nNoAplica, 1);
  });

  test('cumple parcialmente vale la mitad del peso', () {
    final res = uc(
      respuestas: [
        _r('recambios', 2, ValorRespuesta.parcial),
        _r('recambios', 2, ValorRespuesta.cumple),
      ],
      pesosArea: pesos,
    );
    expect(res.areas['recambios']!.porcentaje, 75.0);
  });

  test('el peso 3 pesa el triple que el peso 1', () {
    final res = uc(
      respuestas: [
        _r('asesores', 3, ValorRespuesta.noCumple),
        _r('asesores', 1, ValorRespuesta.cumple),
      ],
      pesosArea: pesos,
    );
    expect(res.areas['asesores']!.porcentaje, 25.0);
  });

  test('una critica en NO_CUMPLE topa el area al 79', () {
    final respuestas = <Respuesta>[
      _r('taller', 3, ValorRespuesta.noCumple, critica: true),
    ];
    for (var i = 0; i < 30; i++) {
      respuestas.add(_r('taller', 1, ValorRespuesta.cumple));
    }
    final res = uc(respuestas: respuestas, pesosArea: pesos);
    expect(res.areas['taller']!.topadaPorCritica, isTrue);
    expect(res.areas['taller']!.porcentaje, 79.0);
    expect(res.totalCriticasFalladas, 1);
  });

  test('un area entera en N/A no arrastra la puntuacion global', () {
    final res = uc(
      respuestas: [
        _r('administracion', 1, ValorRespuesta.noAplica),
        _r('taller', 1, ValorRespuesta.cumple),
      ],
      pesosArea: pesos,
    );
    expect(res.areas['administracion']!.evaluable, isFalse);
    expect(res.puntuacionGlobal, 100.0);
  });

  test('sin responder no cuenta como fallo pero baja el progreso', () {
    final res = uc(
      respuestas: [
        _r('asesores', 1, ValorRespuesta.cumple),
        _r('asesores', 1, null),
      ],
      pesosArea: pesos,
    );
    expect(res.areas['asesores']!.porcentaje, 100.0);
    expect(res.areas['asesores']!.completa, isFalse);
    expect(res.progresoGlobal, 0.5);
  });

  test('la global pondera por peso de area, no por numero de preguntas', () {
    final res = uc(
      respuestas: [
        _r('taller', 1, ValorRespuesta.cumple),
        _r('administracion', 1, ValorRespuesta.noCumple),
      ],
      pesosArea: const {'administracion': 0.20, 'taller': 0.30},
    );
    expect(res.puntuacionGlobal, 60.0);
    expect(res.nivel, 'D');
  });
}
