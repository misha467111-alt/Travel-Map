import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'controllers/profile_controller.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_design.dart';
import 'screens/auth_screens.dart';
import 'features/friends/presentation/friends_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/navigation/presentation/main_navigation_screen.dart';
import 'features/social/presentation/user_profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _AppBootstrap()));
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    AppConfig.validate();

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
        detectSessionInUriPredicate: _isOAuthCallback,
      ),
    );

    await profileController.initialize().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'Supabase не відповів протягом 20 секунд. Перевірте інтернет і налаштування проєкту.',
          ),
        );
  }

  void _retry() {
    setState(() => _initialization = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootstrapLoadingScreen();
          }
          if (snapshot.hasError) {
            return _BootstrapErrorScreen(
              error: snapshot.error!,
              onRetry: _retry,
            );
          }
          return const ExpeditionApp();
        },
      ),
    );
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore, size: 64, color: Colors.amber),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Запуск Travel Map…'),
          ],
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  'Не вдалося запустити Travel Map',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Спробувати знову'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _isOAuthCallback(Uri uri) {
  return uri.scheme == 'io.supabase.travelmap' &&
      uri.host == 'login-callback' &&
      (uri.queryParameters.containsKey('code') ||
          uri.queryParameters.containsKey('error') ||
          uri.queryParameters.containsKey('error_code') ||
          uri.queryParameters.containsKey('error_description'));
}

class ExpeditionApp extends StatelessWidget {
  const ExpeditionApp({super.key});

  static final GoRouter _router = GoRouter(
    refreshListenable: profileController,
    redirect: (context, state) {
      if (!profileController.isAuthorized && state.matchedLocation != '/') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _RootScreen(),
      ),
      GoRoute(
        path: '/friends',
        builder: (context, state) => const FriendsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/users/:id',
        builder: (context, state) =>
            UserProfileScreen(userId: state.pathParameters['id']!),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: buildAppTheme(),
    );
  }
}

class _RootScreen extends StatelessWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: profileController,
      builder: (context, _) {
        if (profileController.isAuthorized) {
          return const MainNavigationScreen();
        }
        if (profileController.needsInviteStep) return const InviteStepScreen();
        return const LoginScreen();
      },
    );
  }
}
