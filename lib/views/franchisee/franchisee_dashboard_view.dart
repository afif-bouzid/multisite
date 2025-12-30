// lib/views/franchisee/franchisee_dashboard_view.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';

class FranchiseeDashboardView extends StatelessWidget {
  // Le widget enfant qui sera affiché dans le corps du Scaffold.
  final Widget child;

  const FranchiseeDashboardView({super.key, required this.child});

  Widget _buildDrawer(BuildContext context, FranchiseUser? user) {
    final userModules = user?.enabledModules ?? {};
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const double iconSize = 26.0; // Taille unifiée pour les icônes

    List<Widget> topMenuItems = [
      ListTile(
        leading: Icon(Icons.point_of_sale_outlined,
            color: Colors.green.shade700, size: iconSize),
        title: const Text('Caisse (POS)'),
        onTap: () {
          Navigator.pop(context);
          context.go('/franchisee_dashboard'); // Route pour la caisse
        },
      ),
      ListTile(
        leading: Icon(Icons.leaderboard_outlined,
            color: Colors.deepPurple.shade400, size: iconSize),
        title: const Text('Statistiques & Clôture'),
        onTap: () {
          Navigator.pop(context);
          context.go('/franchisee_stats'); // Route pour les stats/clôture
        },
      ),
      const Divider(height: 20, thickness: 1),

      ListTile(
        leading: Icon(Icons.menu_book_outlined,
            color: Colors.brown.shade500, size: iconSize),
        title: const Text('Catalogue & Prix'),
        onTap: () {
          Navigator.pop(context);
          context.go('/franchisee_catalogue'); // Route catalogue
        },
      ),
      if (userModules['kiosk'] == true)
        ListTile(
          leading: Icon(Icons.lan_outlined,
              color: Colors.blueGrey.shade500, size: iconSize),
          title: const Text('Configuration Borne'),
          onTap: () {
            Navigator.pop(context);
            context.go('/franchisee_kiosk_config'); // Route config borne
          },
        ),

      // --- Groupe Modules Optionnels (si activés) ---
      if (userModules['deals'] == true)
        ListTile(
          leading: Icon(Icons.star_outline,
              color: Colors.orange.shade600, size: iconSize),
          title: const Text('Offres Promo'),
          onTap: () {
            Navigator.pop(context);
            context.go('/franchisee_deals'); // Route offres promo
          },
        ),
      // (Ajoutez ici d'autres modules s'il y en a, comme Click & Collect)
      // if (userModules['click_and_collect'] == true)
      //   ListTile(
      //     leading: Icon(Icons.shopping_bag_outlined, color: Colors.teal.shade400, size: iconSize),
      //     title: const Text('Click & Collect'),
      //     onTap: () {
      //       Navigator.pop(context);
      //       context.go('/franchisee_cc'); // Adaptez la route si nécessaire
      //     },
      //   ),
    ];

    List<Widget> bottomMenuItems = [
      const Divider(height: 1, thickness: 1),
      // Séparateur juste avant les derniers items
      ListTile(
        leading: Icon(Icons.settings_outlined,
            color: Colors.grey.shade700, size: iconSize),
        title: const Text('Configuration'),
        onTap: () {
          Navigator.pop(context);
          context.go('/franchisee_settings'); // Route configuration générale
        },
      ),
      ListTile(
        leading: Icon(Icons.logout, color: Colors.red.shade600, size: iconSize),
        title: const Text('Déconnexion'),
        onTap: () => authProvider.signOut(),
      ),
    ];

    return Drawer(
      child: Column(
        // Utilisation d'une Column pour organiser verticalement
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text(user?.companyName ?? "Utilisateur Franchisé",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(user?.email ?? ""),
            currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.storefront,
                    color: Theme.of(context).primaryColor, size: 36)),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
          ),
          // Partie supérieure du menu qui prend l'espace disponible
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero, // Important pour coller au header
              children: topMenuItems,
            ),
          ),
          // Partie inférieure fixe en bas
          ...bottomMenuItems,
          // Utilise l'opérateur spread (...) pour ajouter les éléments de la liste
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final franchisee = authProvider.franchiseUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('Portail ${franchisee?.companyName ?? ""}'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: "Menu de navigation",
          ),
        ),
      ),
      drawer: _buildDrawer(context, franchisee),
      body: child,
    );
  }
}
