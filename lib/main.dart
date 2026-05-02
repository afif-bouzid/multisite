import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ouiborne/screens/login/quick_login_screen.dart';
import 'package:provider/provider.dart';

// --- IMPORTS DES VUES DU PROJET ---
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

// --- IMPORT DE LA VUE MOBILE STATS ---
import 'back_office/views/franchisee/mobile_stats_view.dart';
import 'models/click_and_collect_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 600;
  PaintingBinding.instance.imageCache.maximumSize = 5000;

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
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
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: Center(child: CircularProgressIndicator())),
            );
          }
          return MaterialApp.router(
            title: 'Ouiborne Caisse',
            debugShowCheckedModeBanner: false,
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
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      inherit: false),
                ),
              ),
            ),
            routerConfig: AppRouter(authProvider: auth).router,
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
            path: '/launcher',
            builder: (context, state) => const AppLauncher()),
        GoRoute(
            path: '/mobile_stats',
            builder: (context, state) => const MobileStatsView()),
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
                path: '/franchisee_click_collect',
                builder: (context, state) => const ClickAndCollectManager()),
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
        final String location = state.uri.toString();
        final isLoggingIn = location == '/login';
        final user = authProvider.franchiseUser;

        // 1. Protection de base : Pas de session = Login
        if (!isLoggedIn) return isLoggingIn ? null : '/login';

        // 2. Aiguillage au moment de la connexion
        if (isLoggingIn && isLoggedIn) {
          if (user?.isFranchisor == true) {
            return '/franchisor_dashboard';
          }

          // 🔥 SÉPARATION STRICTE DES FLUX
          if (user?.isEmployee == true) {
            // L'employé (Caissier) est aspiré directement par la caisse
            return '/franchisee_dashboard';
          }

          if (user?.isAssociate == true) {
            // L'associé (Partenaire) va consulter les stats mobiles
            return '/mobile_stats';
          }

          // Le franchisé (Patron) choisit son mode sur le launcher
          return '/launcher';
        }

        // 3. SÉCURITÉ ACTIVE : Le Vigile (Route Guard)
        // On bloque l'accès de l'employé aux routes interdites
        if (user?.isEmployee == true) {
          final forbiddenRoutes = [
            '/mobile_stats',
            '/launcher', // Pas de choix de mode pour lui
            '/franchisee_stats',
            '/franchisee_settings',
            '/franchisee_team',
            '/franchisee_kiosk_config'
          ];

          if (forbiddenRoutes.contains(location)) {
            debugPrint("🔒 ACCÈS REFUSÉ : Tentative illégale de l'employé sur $location");
            return '/franchisee_dashboard';
          }
        }

        return null;
      },
    );
  }
}

// ----------------------------------------------------------------
// WIDGET : APP LAUNCHER (SÉLECTEUR DE MODE)
// ----------------------------------------------------------------
class AppLauncher extends StatelessWidget {
  const AppLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bkOffWhite,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.restaurant_menu,
                size: 80, color: AppColors.bkBlack),
            const SizedBox(height: 20),
            const Text(
              "OUIBORNE",
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: AppColors.bkBlack,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "SÉLECTION DU MODE DE TRAVAIL",
              style: TextStyle(
                  fontSize: 16, color: AppColors.bkBlack, letterSpacing: 1.2),
            ),
            const SizedBox(height: 60),
            _buildModeButton(
              context,
              title: "ACCÉDER À LA CAISSE",
              subtitle: "Vente, encaissement et commandes",
              icon: Icons.tablet_android,
              color: AppColors.bkYellow,
              textColor: AppColors.bkBlack,
              onTap: () => context.go('/franchisee_dashboard'),
            ),
            const SizedBox(height: 25),
            _buildModeButton(
              context,
              title: "STATS EN DIRECT",
              subtitle: "Suivi du CA et commandes à distance",
              icon: Icons.query_stats,
              color: AppColors.bkBlack,
              textColor: AppColors.bkYellow,
              onTap: () => context.go('/mobile_stats'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required Color textColor,
        required VoidCallback onTap,
      }) {
    return Container(
      width: 450,
      height: 110,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: const TextStyle(inherit: false),
        ),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          inherit: false)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 14,
                          color: textColor.withValues(alpha: 0.7),
                          inherit: false)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 18, color: textColor),
          ],
        ),
      ),
    );
  }
}