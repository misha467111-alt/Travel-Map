import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';
import 'login_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({this.authenticatedChild, super.key});

  /// Defaults to a temporary map placeholder. The app may inject its real
  /// authenticated shell without coupling this feature to `main.dart`.
  final Widget? authenticatedChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          data: (session) => session == null
              ? const LoginScreen()
              : authenticatedChild ??
                  const Scaffold(
                    body: Center(child: Text('Map Screen')),
                  ),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Не вдалося перевірити сесію: $error',
                    textAlign: TextAlign.center),
              ),
            ),
          ),
        );
  }
}
