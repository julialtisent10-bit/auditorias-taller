import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../../core/almacen/almacen_binarios.dart';

import '../../../../app/di/providers.dart';
import '../../domain/entities/auditoria.dart';
import '../providers/auditoria_controller.dart';
import 'resumen_page.dart';

/// Firmas y cierre. Es el punto de no retorno: aquí se genera el PDF,
/// se marca la auditoría como finalizada y se encola todo para subir.
class FirmaPage extends ConsumerStatefulWidget {
  const FirmaPage({super.key});

  @override
  ConsumerState<FirmaPage> createState() => _FirmaPageState();
}

class _FirmaPageState extends ConsumerState<FirmaPage> {
  late final SignatureController _auditor = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  late final SignatureController _gerente = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool _cerrando = false;
  String? _paso;

  @override
  void dispose() {
    _auditor.dispose();
    _gerente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditoria = ref.watch(auditoriaActualProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conformidad')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Al firmar se cierra la auditoría y se genera el informe. '
            'Después no podrás modificar las respuestas sin reabrirla.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _Panel(
            titulo: 'Auditor',
            nombre: auditoria?.auditorNombre ?? '',
            controller: _auditor,
          ),
          const SizedBox(height: 20),
          _Panel(
            titulo: 'Gerente del centro',
            nombre: auditoria?.responsables['gerente'] ?? '',
            controller: _gerente,
          ),
          const SizedBox(height: 28),
          if (_cerrando) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Center(child: Text(_paso ?? '', style: const TextStyle(fontSize: 12))),
          ] else
            FilledButton.icon(
              onPressed: _cerrar,
              icon: const Icon(Icons.lock),
              label: const Text('Cerrar auditoría y generar informe'),
            ),
        ],
      ),
    );
  }

  Future<void> _cerrar() async {
    // La validación va antes de cualquier `await`: así se puede usar
    // `context` sin comprobar `mounted`.
    if (_auditor.isEmpty || _gerente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faltan firmas: deben firmar auditor y gerente.')),
      );
      return;
    }

    final auditoria = ref.read(auditoriaActualProvider);
    if (auditoria == null) return;

    setState(() {
      _cerrando = true;
      _paso = 'Guardando firmas…';
    });

    try {
      final datos = await construirDatosReporte(ref);
      if (datos == null) throw StateError('No hay datos de auditoría en memoria');

      final firmaAuditor = await _guardarFirma(_auditor, auditoria, 'auditor');
      final firmaGerente = await _guardarFirma(_gerente, auditoria, 'gerente');

      setState(() => _paso = 'Generando el informe…');
      final pdf = await ref.read(generarReporteProvider).bytes(datos);

      setState(() => _paso = 'Cerrando la auditoría…');
      await ref.read(auditoriaRepositoryProvider).finalizar(
            auditoria.id,
            resultado: ref.read(auditoriaControllerProvider).resultado,
            firmaAuditor: Firma(
              nombre: auditoria.auditorNombre,
              claveLocal: firmaAuditor,
              firmadoEn: DateTime.now(),
            ),
            firmaGerente: Firma(
              nombre: auditoria.responsables['gerente'] ?? '',
              claveLocal: firmaGerente,
              firmadoEn: DateTime.now(),
            ),
            pdf: pdf,
          );

      await ref.read(centroRepositoryProvider).registrarCierre(
            auditoria.centroId,
            auditoriaId: auditoria.id,
            fecha: auditoria.fecha,
            puntuacion: ref.read(auditoriaControllerProvider).resultado.puntuacionGlobal,
          );

      if (!mounted) return;

      // Orden importante. Primero se sale del flujo y solo después se
      // limpia la sesión: si se vaciara antes, el cuestionario y el resumen
      // siguen montados observando `auditoriaControllerProvider` y su
      // reconstrucción reventaría con StateError.
      //
      // El contenedor se captura antes de navegar porque tras el pop este
      // widget queda desmontado y su `ref` deja de poder usarse.
      final contenedor = ProviderScope.containerOf(context, listen: false);
      final reporte = ref.read(generarReporteProvider);

      Navigator.of(context).popUntil((r) => r.isFirst);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        contenedor.read(sesionAbiertaProvider.notifier).state = null;
        contenedor.read(auditoriaActualProvider.notifier).state = null;
      });

      await reporte.compartir(pdf, datos);
    } catch (e) {
      if (mounted) {
        setState(() => _cerrando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo cerrar: $e')));
      }
    }
  }

  /// Guarda el PNG de la firma en el almacen local y devuelve su clave.
  /// Devuelve null si el lienzo no produjo imagen.
  Future<String?> _guardarFirma(
      SignatureController controller, Auditoria auditoria, String rol) async {
    final bytes = await controller.toPngBytes();
    if (bytes == null) return null;

    final clave = AlmacenBinarios.claveFirma(auditoria.id, rol);
    await ref.read(almacenProvider).guardar(clave, bytes);
    return clave;
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.titulo, required this.nombre, required this.controller});

  final String titulo;
  final String nombre;
  final SignatureController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(nombre,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey)),
            ),
            TextButton.icon(
              onPressed: controller.clear,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Borrar'),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          clipBehavior: Clip.antiAlias,
          child: Signature(
            controller: controller,
            height: 160,
            backgroundColor: Colors.white,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Firme con el dedo dentro del recuadro',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ],
    );
  }
}
