import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auditoria/presentation/pages/cuestionario_page.dart';
import '../features/auditoria/presentation/pages/firma_page.dart';
import '../features/auditoria/presentation/pages/inicio_auditoria_page.dart';
import '../features/auditoria/presentation/pages/resumen_page.dart';
import '../features/centros/presentation/pages/home_page.dart';
import '../features/plantillas/presentation/pages/editor_plantilla_page.dart';
import '../features/ranking/presentation/pages/ranking_page.dart';
import 'di/providers.dart';
import 'theme/app_theme.dart';
import 'login_page.dart';

class AuditApp extends ConsumerWidget {
  const AuditApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioProvider);

    return MaterialApp(
      title: 'Auditorías de taller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro(),
      darkTheme: AppTheme.oscuro(),
      home: usuario.when(
        loading: () => const _Cargando(),
        error: (e, _) => _ErrorArranque(error: e),
        // Sin sesión no se entra: las reglas de Firestore rechazan cualquier
        // lectura anónima, así que la app sin login solo mostraría errores.
        data: (u) => u == null ? const LoginPage() : const HomePage(),
      ),
      routes: {
        '/auditoria/inicio': (_) => const InicioAuditoriaPage(),
        '/auditoria': (_) => const CuestionarioPage(),
        '/auditoria/resumen': (_) => const ResumenPage(),
        '/auditoria/firma': (_) => const FirmaPage(),
        '/ranking': (_) => const RankingPage(),
        '/cuestionario/editar': (_) => const EditorPlantillaPage(),
      },
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorArranque extends StatelessWidget {
  const _ErrorArranque({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text('No se pudo iniciar la sesión'),
                const SizedBox(height: 8),
                Text('$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
}
