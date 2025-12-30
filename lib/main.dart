import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ouiborne/screens/login/quick_login_screen.dart';
import 'package:provider/provider.dart';

import 'back_office/views/franchisee/franchisee_about_view.dart';
import 'back_office/views/franchisee/franchisee_catalogue_view.dart';
import 'back_office/views/franchisee/franchisee_dashboard_view.dart';
import 'back_office/views/franchisee/franchisee_deals_view.dart';
import 'back_office/views/franchisee/franchisee_kiosk_config_view.dart';
import 'back_office/views/franchisee/franchisee_settings_view.dart';
import 'back_office/views/franchisee/franchisee_stats_view.dart';
import 'back_office/views/franchisee/team_management_view.dart';
import 'back_office/views/franchisee/till/franchisee_till_view.dart';
import 'back_office/views/franchisee/till/widgets/app_scaler.dart';
import 'back_office/views/franchisor/franchisor_dashboard_view.dart';
import 'core/auth_provider.dart';
import 'core/cart_provider.dart';
import 'core/firebase_options.dart';
import 'core/providers/update_provider.dart';
import 'core/theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeDateFormatting('fr_FR', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => CartProvider()),
        ChangeNotifierProvider(create: (context) => UpdateProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          if (auth.isLoading) {
            return const MaterialApp(
              home: Scaffold(body: Center(child: CircularProgressIndicator())),
            );
          }
          return MaterialApp.router(
            title: 'Ouiborne Caisse',
            builder: (context, child) {
              return AppScaler(
                scale: 0.80,
                child: child!,
              );
            },
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.bkYellow,
                primary: AppColors.bkBlack,
                secondary: AppColors.bkYellow,
                background: AppColors.bkOffWhite,
                surface: Colors.white,
              ),
              scaffoldBackgroundColor: AppColors.bkOffWhite,
              fontFamily: 'Flame',
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.comfortable,
              checkboxTheme: CheckboxThemeData(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                side: const BorderSide(width: 2, color: AppColors.bkBlack),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  side: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.bkBlack,
                elevation: 0,
                centerTitle: false,
                titleTextStyle: TextStyle(
                    fontFamily: 'Flame',
                    color: AppColors.bkBlack,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.bkYellow, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bkYellow,
                  foregroundColor: AppColors.bkBlack,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ),
            routerConfig: AppRouter(authProvider: auth).router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AppRouter {
  final AuthProvider authProvider;
  late final GoRouter router;

  AppRouter({required this.authProvider}) {
    router = GoRouter(
      refreshListenable: authProvider,
      initialLocation: '/login',
      routes: [
        GoRoute(
            path: '/login',
            builder: (context, state) => const QuickLoginScreen()),
        GoRoute(
            path: '/franchisor_dashboard',
            builder: (context, state) => const FranchisorDashboardView()),
        ShellRoute(
          builder: (context, state, child) {
            return FranchiseeDashboardView(child: child);
          },
          routes: [
            GoRoute(
                path: '/franchisee_dashboard',
                builder: (context, state) => const FranchiseeTillView()),
            GoRoute(
                path: '/franchisee_catalogue',
                builder: (context, state) => const FranchiseeCatalogueView()),
            GoRoute(
                path: '/franchisee_deals',
                builder: (context, state) => const FranchiseeDealsView()),
            GoRoute(
                path: '/franchisee_kiosk_config',
                builder: (context, state) => const FranchiseeKioskConfigView()),
            GoRoute(
                path: '/franchisee_stats',
                builder: (context, state) => const FranchiseeStatsView()),
            GoRoute(
                path: '/franchisee_team',
                builder: (context, state) => const TeamManagementView()),
            GoRoute(
                path: '/franchisee_settings',
                builder: (context, state) => const FranchiseeSettingsView()),
            GoRoute(
                path: '/franchisee_about',
                builder: (context, state) => const FranchiseeAboutView()),
          ],
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final isLoggedIn = authProvider.firebaseUser != null;
        final isLoggingIn = state.matchedLocation == '/login';

        if (!isLoggedIn) return isLoggingIn ? null : '/login';
        if (isLoggingIn && isLoggedIn) {
          if (authProvider.franchiseUser?.isFranchisor == true) {
            return '/franchisor_dashboard';
          } else {
            return '/franchisee_dashboard';
          }
        }
        return null;
      },
    );
  }
}

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Connexion Back-Office',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: Icon(Icons.lock_outline)),
                      obscureText: true),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final authProvider =
                            Provider.of<AuthProvider>(context, listen: false);
                        final error = await authProvider.signIn(
                            _emailController.text.trim(),
                            _passwordController.text.trim());
                        if (error != null) {
                          setState(() => _errorMessage = error);
                        }
                      },
                      child: const Text('Se connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
