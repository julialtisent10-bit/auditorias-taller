import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.fact_check_outlined,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Auditorías de taller',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
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
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _cargando ? null : _entrar,
                child: _cargando
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
