import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Acceso con correo y contraseña.
///
/// Se elige este método y no Google Sign-In a propósito: con un solo auditor
/// no compensa configurar OAuth ni los SHA-1 de firma en Android. Si más
/// adelante entra más gente, cambiar de método es tocar solo esta pantalla.
///
/// Firebase Auth mantiene la sesión abierta entre arranques, así que esto
/// se ve una vez y no vuelve a aparecer salvo cierre de sesión explícito.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _correo.text.trim(),
        password: _clave.text,
      );
      // No hace falta navegar: `usuarioProvider` emite y AuditApp cambia sola.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mensaje(e.code));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Envía el correo de restablecimiento.
  ///
  /// Sin esto, quien olvidara su contraseña quedaba fuera hasta que alguien
  /// se la cambiara desde la consola de Firebase.
  Future<void> _recuperar() async {
    final correo = _correo.text.trim();
    if (correo.isEmpty) {
      setState(() => _error = 'Escribe tu correo y vuelve a pulsar.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: correo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Te hemos enviado un correo a $correo para que la '
              'cambies. Mira también la carpeta de no deseado.'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on FirebaseAuthException catch (e) {
      // No se distingue si la cuenta existe: decirlo permitiría averiguar
      // desde fuera qué correos están dados de alta.
      setState(() => _error = e.code == 'invalid-email'
          ? 'El correo no tiene un formato válido.'
          : 'No se pudo enviar el correo (${e.code}).');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static String _mensaje(String codigo) => switch (codigo) {
        'invalid-email' => 'El correo no tiene un formato válido.',
        'user-disabled' => 'Esta cuenta está deshabilitada.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Correo o contraseña incorrectos.',
        'network-request-failed' =>
          'Sin conexión. Necesitas red la primera vez que entras.',
        'too-many-requests' => 'Demasiados intentos. Prueba dentro de unos minutos.',
        _ => 'No se pudo iniciar sesión ($codigo).',
      };

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            // Tope de ancho: en un portátil o una tablet, los campos
            // estirados de lado a lado quedan ridículos.
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // El logotipo viene en un solo color plano, así que se tiñe
              // según el tema en vez de arrastrar dos ficheros distintos.
              SvgPicture.asset(
                'assets/branding/scaitt_logo.svg',
                height: 34,
                colorFilter: ColorFilter.mode(esquema.onSurface, BlendMode.srcIn),
              ),
              const SizedBox(height: 28),
              Text('Auditorías de taller',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Vehículo industrial',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 1.6,
                      color: esquema.onSurfaceVariant)),
              const SizedBox(height: 36),
              TextField(
                controller: _correo,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clave,
                obscureText: true,
                onSubmitted: (_) => _entrar(),
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _cargando ? null : _recuperar,
                  child: const Text('¿Olvidaste tu contraseña?',
                      style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _cargando ? null : _entrar,
                child: _cargando
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 40),
              Text('Uso interno del grupo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: esquema.outline)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
