import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';

// Import des vues vers lesquelles on veut naviguer
import 'franchisee_menu_view.dart';
import 'pos_view.dart';

class FranchiseeDashboardView extends StatelessWidget {
  const FranchiseeDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    // CORRECTION ICI : On utilise franchiseUser au lieu de firebaseUser
    final user = Provider.of<AuthProvider>(context).franchiseUser;
    final companyName = user?.companyName ?? "Mon Magasin";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Tableau de bord", style: TextStyle(fontSize: 14, color: Colors.grey)),
            Text(companyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).signOut();
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Accès Rapide", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [

                  // --- BOUTON 1 : OUVRIR LA CAISSE ---
                  _buildDashboardCard(
                    context,
                    title: "Ouvrir la Caisse",
                    subtitle: "Prise de commande",
                    icon: Icons.point_of_sale_rounded,
                    color: Colors.green,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const POSView()),
                      );
                    },
                  ),

                  // --- BOUTON 2 : GÉRER LE MENU ---
                  _buildDashboardCard(
                    context,
                    title: "Mon Menu & Prix",
                    subtitle: "Activer produits, changer prix",
                    icon: Icons.restaurant_menu_rounded,
                    color: Colors.blue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FranchiseeMenuView()),
                      );
                    },
                  ),

                  // --- BOUTON 3 : STOCKS ---
                  _buildDashboardCard(
                    context,
                    title: "Stocks",
                    subtitle: "Gérer les ingrédients",
                    icon: Icons.inventory_2_rounded,
                    color: Colors.orange,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Module Stock à venir"))
                      );
                    },
                  ),

                  // --- BOUTON 4 : STATISTIQUES ---
                  _buildDashboardCard(
                    context,
                    title: "Statistiques",
                    subtitle: "Ventes du jour",
                    icon: Icons.bar_chart_rounded,
                    color: Colors.purple,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Module Stats à venir"))
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}