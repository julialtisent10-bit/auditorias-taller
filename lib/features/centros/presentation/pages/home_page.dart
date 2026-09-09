import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../shared/imagen_centro.dart';
import '../../../../shared/widgets/error_datos.dart';
import '../../../../shared/widgets/aviso_almacenamiento.dart';
import '../../../auditoria/presentation/borrar_auditoria.dart';
import '../../domain/entities/centro.dart';
import 'ficha_centro_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centros = ref.watch(centrosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditorías de taller'),
        actions: [
          const AvisoAlmacenamiento(),
          IconButton(
            tooltip: 'Ranking',
            icon: const Icon(Icons.leaderboard),
            onPressed: () => Navigator.of(context).pushNamed('/ranking'),
          ),
          PopupMenuButton<String>(
            onSelected: (opcion) {
              if (opcion == 'historico') {
                Navigator.of(context).pushNamed('/historico');
              } else if (opcion == 'cuestionario') {
                Navigator.of(context).pushNamed('/cuestionario/editar');
              } else if (opcion == 'seguridad') {
                Navigator.of(context).pushNamed('/seguridad/historico');
              } else if (opcion == 'salir') {
                FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'historico',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Auditorías'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'cuestionario',
                child: ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text('Editar cuestionario'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'seguridad',
                child: ListTile(
                  leading: Icon(Icons.health_and_safety_outlined),
                  title: Text('Revisión de seguridad'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'salir',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Cerrar sesión'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: centros.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorDatos(error: e, queSeIntentaba: 'los centros'),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay centros dados de alta.\n'
                  'Pulsa "Nueva auditoría" para crear el primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverToBoxAdapter(child: _AvisoEnCurso()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _TarjetaCentro(centro: lista[i]),
                    childCount: lista.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed('/auditoria/inicio'),
        icon: const Icon(Icons.add_task),
        label: const Text('Nueva auditoría'),
      ),
    );
  }
}

/// Auditorías abiertas. Si la app se cerró a media visita, esta tarjeta es
/// la única forma de volver a ella sin empezar de cero.
class _AvisoEnCurso extends ConsumerWidget {
  const _AvisoEnCurso();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abiertas = ref.watch(enCursoProvider).value ?? const [];
    if (abiertas.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final a in abiertas)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.pending_actions),
              title: Text('Auditoría sin terminar · ${a.centroNombre}'),
              subtitle: Text('Iniciada el ${_fecha(a.fecha)}',
                  style: const TextStyle(fontSize: 12)),
              onTap: () async {
                final navegador = Navigator.of(context);
                await reanudarAuditoria(ref, a);
                navegador.pushNamed('/auditoria');
              },
              trailing: PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (opcion) async {
                  if (opcion == 'continuar') {
                    final navegador = Navigator.of(context);
                    await reanudarAuditoria(ref, a);
                    navegador.pushNamed('/auditoria');
                  } else if (opcion == 'descartar') {
                    await confirmarYBorrarAuditoria(context, ref, a);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'continuar', child: Text('Continuar auditoría')),
                  PopupMenuItem(
                      value: 'descartar', child: Text('Descartar auditoría')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _fecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _TarjetaCentro extends StatelessWidget {
  const _TarjetaCentro({required this.centro});
  final Centro centro;

  @override
  Widget build(BuildContext context) {
    final puntuacion = centro.resumen.ultimaPuntuacion;
    final tendencia = centro.resumen.tendencia;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FichaCentroPage(centro: centro),
        )),
        child: Ink(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(assetImagenCentro(centro.nombre)),
              fit: BoxFit.cover,
              // Oscurece la foto para que el texto blanco siga siendo
              // legible encima, sea cual sea la imagen del centro.
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.45),
                BlendMode.darken,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  centro.nombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                if (puntuacion == null)
                  const Text('Sin auditorías',
                      style: TextStyle(fontSize: 12, color: Colors.white70))
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${puntuacion.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      if (tendencia != null) ...[
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _Tendencia(valor: tendencia),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Última: ${_fecha(centro.resumen.ultimaFecha)}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fecha(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _Tendencia extends StatelessWidget {
  const _Tendencia({required this.valor});
  final double valor;

  @override
  Widget build(BuildContext context) {
    // Media décima de margen: variaciones mínimas no son una tendencia.
    if (valor.abs() < 0.5) {
      return const Icon(Icons.trending_flat, size: 18, color: Colors.grey);
    }
    final sube = valor > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(sube ? Icons.trending_up : Icons.trending_down,
            size: 18, color: sube ? Colors.green : Colors.red),
        Text('${sube ? '+' : ''}${valor.toStringAsFixed(1)}',
            style: TextStyle(
                fontSize: 11, color: sube ? Colors.green : Colors.red)),
      ],
    );
  }
}
