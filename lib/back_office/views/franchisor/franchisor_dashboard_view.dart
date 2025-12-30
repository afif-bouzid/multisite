import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import 'dialogs/category_dialog.dart';
import 'franchisor_catalogue_view.dart';
import 'franchisor_filters_view.dart';
import 'franchisor_franchisees_view.dart';
import 'franchisor_groups_view.dart';
import 'franchisor_kiosk_view.dart' hide CategoryEditorDialog;
import 'franchisor_sections_view.dart';

class FranchisorDashboardView extends StatefulWidget {
  const FranchisorDashboardView({super.key});

  @override
  State<FranchisorDashboardView> createState() =>
      _FranchisorDashboardViewState();
}

class _FranchisorDashboardViewState extends State<FranchisorDashboardView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Portail Franchiseur',
            style: Theme.of(context).textTheme.titleLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Chip(
              avatar: const Icon(Icons.person_outline),
              label: Text(authProvider.franchiseUser?.email ?? ""),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Déconnexion",
            onPressed: () => authProvider.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.store_outlined), text: "Franchisés"),
            Tab(icon: Icon(Icons.lan), text: "Catégories et sous catégorie"),
            Tab(icon: Icon(Icons.fastfood_outlined), text: "Produits"),
            Tab(icon: Icon(Icons.view_stream_outlined), text: "Sections"),
            Tab(
                icon: Icon(Icons.collections_bookmark_outlined),
                text: "Groupes"),
            Tab(icon: Icon(Icons.label_outline), text: "Filtres"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FranchiseesView(),
          KioskView(),
          CatalogueView(),
          SectionsView(),
          SectionGroupsView(),
          FiltersView(),
        ],
      ),
      floatingActionButton:
          _buildFloatingActionButton(context, _tabController.index),
    );
  }

  Widget? _buildFloatingActionButton(BuildContext context, int index) {
    switch (index) {
      case 0:
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouveau Franchisé"),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const FranchiseeFormView())),
        );
      case 1:
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouvelle Catégorie"),
          onPressed: () {
            // ✅ ON REMPLACE L'ANCIEN APPEL PAR CELUI-CI
            showDialog(
              context: context,
              builder: (context) => const CategoryEditorDialog(),
            );
          },
        );
      case 2:
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouveau Produit"),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (context) => const ProductFormView())),
        );
      case 3:
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouvelle Section"),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (context) => const SectionFormView())),
        );
      case 4:
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouveau Groupe"),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const SectionGroupFormView())),
        );
      case 5:
        return FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouveau Filtre"),
          onPressed: () => FiltersView.showFilterDialog(context),
        );
      default:
        return null;
    }
  }
}
