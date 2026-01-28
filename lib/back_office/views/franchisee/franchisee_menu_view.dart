import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';

class FranchiseeMenuView extends StatefulWidget {
  const FranchiseeMenuView({super.key});

  @override
  State<FranchiseeMenuView> createState() => _FranchiseeMenuViewState();
}

class _FranchiseeMenuViewState extends State<FranchiseeMenuView> {
  final _searchController = TextEditingController();
  String _searchQuery = "";
  List<MasterProduct> _masterProducts = [];
  Map<String, FranchiseeMenuItem> _franchiseeMenu = {};
  bool _isLoading = true;
  StreamSubscription? _menuSub;
  StreamSubscription? _masterSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _menuSub?.cancel();
    _masterSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.franchiseUser;

    if (user == null || user.franchisorId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = FranchiseRepository();

    // 1. Charger Master
    _masterSub = repo.getMasterProductsStream(user.franchisorId!).listen((products) {
      if (mounted) {
        products.sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));
        setState(() => _masterProducts = products);
        if (_franchiseeMenu.isNotEmpty) setState(() => _isLoading = false);
      }
    });

    // 2. Charger Config Franchisé
    _menuSub = repo.getFranchiseeMenuStream(user.uid).listen((menuItems) {
      final map = <String, FranchiseeMenuItem>{};
      for (var item in menuItems) map[item.masterProductId] = item;
      if (mounted) {
        setState(() {
          _franchiseeMenu = map;
          if (_masterProducts.isNotEmpty) _isLoading = false;
        });
      }
    });
  }

  /// Filtre (on ne cache rien pour le moment pour voir tout ce qui se passe)
  List<MasterProduct> _getFilteredList() {
    return _masterProducts.where((p) {
      if (_searchQuery.isNotEmpty) return p.name.toLowerCase().contains(_searchQuery);
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _getFilteredList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text("Menu & Prix (DEBUG)"), backgroundColor: Colors.red.shade100, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher...",
                prefixIcon: const Icon(Icons.search),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final master = filteredList[index];
                final config = _franchiseeMenu[master.productId];

                // --- TEST DE DÉTECTION ---
                // On vérifie le booléen OU si la liste des enfants n'est pas vide
                final bool isTrulyContainer = master.isContainer || master.containerProductIds.isNotEmpty;

                if (isTrulyContainer) {
                  return _buildContainerCard(master);
                } else {
                  return _buildStandardProductCard(master, config);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// CARTE CONTENEUR
  Widget _buildContainerCard(MasterProduct container) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      color: Colors.orange.shade100, // Fond Orange foncé pour le debug
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(Icons.folder, size: 40, color: Colors.orange.shade900),
        title: Text(
          "${container.name} (DETECTÉ !)", // Texte de debug
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
        ),
        subtitle: Text(
          "isContainer: ${container.isContainer}\nIds: ${container.containerProductIds.length}", // Infos de debug
          style: const TextStyle(fontSize: 10),
        ),
        trailing: ElevatedButton(
          onPressed: () => _openContainerManager(container),
          child: const Text("OUVRIR"),
        ),
      ),
    );
  }

  /// CARTE STANDARD
  Widget _buildStandardProductCard(MasterProduct product, FranchiseeMenuItem? config) {
    final isVisible = config?.isVisible ?? false;
    final price = config?.price ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      child: ListTile(
        leading: Icon(Icons.fastfood, color: Colors.grey.shade400),
        title: Text(product.name),
        subtitle: Text("isContainer: ${product.isContainer}", style: const TextStyle(fontSize: 10, color: Colors.grey)), // Info de debug
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${price.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Switch(
              value: isVisible,
              activeColor: Colors.green,
              onChanged: (val) => _updateConfig(product, val, config?.isAvailable ?? true, price),
            ),
          ],
        ),
      ),
    );
  }

  void _openContainerManager(MasterProduct container) {
    final children = _masterProducts.where((p) => container.containerProductIds.contains(p.id)).toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text("Contenu de ${container.name}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: children.length,
                itemBuilder: (ctx, i) => ListTile(title: Text(children[i].name)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // (Le reste est inchangé pour le test)
  Future<void> _showPriceDialog(MasterProduct master, double currentPrice) async {}
  void _updateConfig(MasterProduct master, bool isVisible, bool isAvailable, double price) {
    // ... update logique
  }
}