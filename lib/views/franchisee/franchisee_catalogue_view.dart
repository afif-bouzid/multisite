import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';

class FranchiseeCatalogueView extends StatefulWidget {
  const FranchiseeCatalogueView({super.key});

  @override
  State<FranchiseeCatalogueView> createState() =>
      _FranchiseeCatalogueViewState();
}

class _FranchiseeCatalogueViewState extends State<FranchiseeCatalogueView> {
  String? _selectedFilterId;
  String? _selectedKioskFilterId;

  // --- NOUVEAU: Variables pour la mise en cache des filtres ---
  List<ProductFilter> _allBackOfficeFilters = [];
  List<KioskCategory> _allKioskCategories = [];
  bool _isLoadingFilters =
      true; // Pour afficher un indicateur de chargement initial

  @override
  void initState() {
    super.initState();
    // Charge les filtres une seule fois au démarrage
    _loadAndCacheFilters();
  }

  Future<void> _loadAndCacheFilters() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.franchiseUser?.franchisorId == null) return;
    final franchisorId = authProvider.franchiseUser!.franchisorId!;
    final repository = FranchiseRepository();

    // Récupère les deux flux de filtres en parallèle
    final results = await Future.wait([
      repository.getFiltersStream(franchisorId).first,
      repository.getKioskCategoriesStream(franchisorId).first,
    ]);

    if (mounted) {
      setState(() {
        _allBackOfficeFilters = results[0] as List<ProductFilter>;
        _allKioskCategories = results[1] as List<KioskCategory>;
        _isLoadingFilters = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.franchiseUser?.franchisorId == null ||
        authProvider.firebaseUser?.uid == null) {
      return const Center(
          child: Text("Erreur: Données utilisateur introuvables."));
    }
    final franchisorId = authProvider.franchiseUser!.franchisorId!;
    final franchiseeId = authProvider.firebaseUser!.uid;
    final repository = FranchiseRepository();
    final franchiseeMenuRef = FirebaseFirestore.instance
        .collection('users')
        .doc(franchiseeId)
        .collection('menu');

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- ZONE DE FILTRAGE ---
          // Affiche un indicateur de chargement ou les filtres mis en cache
          _isLoadingFilters
              ? const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: LinearProgressIndicator()),
                )
              : _buildFilterBars(repository, franchisorId),

          const Divider(height: 1, thickness: 1),

          // --- LISTE DES PRODUITS ---
          Expanded(
            child: StreamBuilder<List<MasterProduct>>(
              stream: repository.getMasterProductsStream(franchisorId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text("Le catalogue du franchiseur est vide."));
                }

                List<MasterProduct> masterProducts = snapshot.data!
                    .where((product) => !product.isIngredient)
                    .toList();

                // Application du filtre de rangement (Back-Office)
                if (_selectedFilterId != null) {
                  masterProducts = masterProducts
                      .where((p) => p.filterIds.contains(_selectedFilterId))
                      .toList();
                }

                // Application du filtre de Borne (Kiosk)
                if (_selectedKioskFilterId != null) {
                  masterProducts = masterProducts
                      .where((p) =>
                          p.kioskFilterIds.contains(_selectedKioskFilterId))
                      .toList();
                }

                if (masterProducts.isEmpty) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("Aucun produit ne correspond à ces filtres.",
                        textAlign: TextAlign.center),
                  ));
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: franchiseeMenuRef.snapshots(),
                  builder: (context, menuSnapshot) {
                    if (menuSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final franchiseeSettings = {
                      for (var doc in menuSnapshot.data?.docs ?? [])
                        doc.id: FranchiseeMenuItem.fromFirestore(
                            doc.data() as Map<String, dynamic>)
                    };

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: masterProducts.length,
                      itemBuilder: (context, index) {
                        final product = masterProducts[index];
                        final settings = franchiseeSettings[product.productId];
                        final isEnabled = settings?.isVisible ?? false;
                        final isAvailable = settings?.isAvailable ?? true;

                        return Card(
                          color: isEnabled
                              ? (isAvailable
                                  ? Colors.white
                                  : Colors.red.shade50)
                              : const Color(0xFFF0F0F0),
                          child: ListTile(
                            leading: Icon(
                              product.isComposite
                                  ? Icons.widgets_outlined
                                  : Icons.fastfood_outlined,
                              color: isEnabled
                                  ? (isAvailable
                                      ? Colors.deepOrange
                                      : Colors.red)
                                  : Colors.grey,
                              size: 40,
                            ),
                            title: Text(
                              product.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isEnabled
                                    ? Colors.black
                                    : Colors.grey.shade700,
                              ),
                            ),
                            subtitle: Text(
                              isEnabled
                                  ? (isAvailable
                                      ? (product.description ??
                                          'Pas de description')
                                      : "ÉPUISÉ (Aujourd'hui)")
                                  : "Désactivé à la vente",
                              style: TextStyle(
                                  fontStyle: isAvailable
                                      ? FontStyle.normal
                                      : FontStyle.italic),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isEnabled) ...[
                                  Text(
                                      "${settings!.price.toStringAsFixed(2)} €",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _showPriceDialog(context,
                                        franchiseeMenuRef, product, settings,
                                        isComposite: product.isComposite),
                                  ),
                                  Tooltip(
                                    message: isAvailable
                                        ? "Marquer comme Épuisé"
                                        : "Marquer comme Disponible",
                                    child: IconButton(
                                      icon: Icon(
                                          isAvailable
                                              ? Icons.inventory_2_outlined
                                              : Icons
                                                  .do_not_disturb_on_outlined,
                                          color: isAvailable
                                              ? Colors.green
                                              : Colors.red),
                                      onPressed: () {
                                        franchiseeMenuRef
                                            .doc(product.productId)
                                            .set({
                                          'isAvailable': !isAvailable,
                                        }, SetOptions(merge: true));
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 20),
                                Switch(
                                  value: isEnabled,
                                  onChanged: (bool value) {
                                    if (value) {
                                      _showPriceDialog(context,
                                          franchiseeMenuRef, product, settings,
                                          isComposite: product.isComposite);
                                    } else {
                                      franchiseeMenuRef
                                          .doc(product.productId)
                                          .set({
                                        'isVisible': false,
                                        'isAvailable': false
                                      }, SetOptions(merge: true));
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // MODIFIÉ: Ce widget n'utilise plus de StreamBuilder
  Widget _buildFilterBars(FranchiseRepository repository, String franchisorId) {
    return StreamBuilder<List<MasterProduct>>(
      stream: repository.getMasterProductsStream(franchisorId),
      builder: (context, productSnapshot) {
        if (!productSnapshot.hasData) return const SizedBox.shrink();

        final sellableProducts =
            productSnapshot.data!.where((p) => !p.isIngredient).toList();

        final relevantBackOfficeFilterIds =
            sellableProducts.expand((p) => p.filterIds).toSet();

        final relevantKioskFilterIds = (_selectedFilterId == null
                ? sellableProducts
                : sellableProducts
                    .where((p) => p.filterIds.contains(_selectedFilterId)))
            .expand((p) => p.kioskFilterIds)
            .toSet();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBackOfficeFilterSelector(relevantBackOfficeFilterIds),
            _buildKioskFilterSelector(relevantKioskFilterIds),
          ],
        );
      },
    );
  }

  // MODIFIÉ: Utilise la liste en cache `_allBackOfficeFilters`
  Widget _buildBackOfficeFilterSelector(Set<String> relevantFilterIds) {
    final relevantFilters = _allBackOfficeFilters
        .where((f) => relevantFilterIds.contains(f.id))
        .toList();

    if (relevantFilters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text("Tous (rangement)"),
              selected: _selectedFilterId == null,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedFilterId = null;
                    _selectedKioskFilterId = null;
                  });
                }
              },
            ),
            ...relevantFilters.map((filter) => Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: ChoiceChip(
                    label: Text(filter.name),
                    selected: _selectedFilterId == filter.id,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilterId = selected ? filter.id : null;
                        _selectedKioskFilterId = null;
                      });
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // MODIFIÉ: Utilise la liste en cache `_allKioskCategories`
  Widget _buildKioskFilterSelector(Set<String> relevantKioskFilterIds) {
    if (relevantKioskFilterIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final allKioskFilters =
        _allKioskCategories.expand((cat) => cat.filters).toList();
    final relevantFilters = allKioskFilters
        .where((f) => relevantKioskFilterIds.contains(f.id))
        .toList();

    if (relevantFilters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text("Toutes (catégories borne)"),
              selected: _selectedKioskFilterId == null,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedKioskFilterId = null);
                }
              },
            ),
            ...relevantFilters.map((filter) => Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: ChoiceChip(
                    label: Text(filter.name),
                    selected: _selectedKioskFilterId == filter.id,
                    onSelected: (selected) {
                      setState(() =>
                          _selectedKioskFilterId = selected ? filter.id : null);
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _showPriceDialog(BuildContext context, CollectionReference menuRef,
      MasterProduct product, FranchiseeMenuItem? currentSettings,
      {bool isComposite = false}) {
    final priceController = TextEditingController(
        text: currentSettings?.price.toStringAsFixed(2) ?? '0.00');
    final List<double> vatRates = [5.5, 10.0, 20.0];
    double selectedVat = currentSettings?.vatRate ?? 10.0;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isComposite
            ? "Prix de base pour: ${product.name}"
            : "Définir le prix pour: ${product.name}"),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: priceController,
                  decoration: InputDecoration(
                      labelText: isComposite
                          ? "Prix de base (souvent 0€)"
                          : "Prix de vente (€)",
                      prefixIcon: const Icon(Icons.euro_symbol)),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<double>(
                  value: selectedVat,
                  decoration: const InputDecoration(labelText: "Taux de TVA"),
                  items: vatRates
                      .map((rate) =>
                          DropdownMenuItem(value: rate, child: Text("$rate %")))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => selectedVat = value ?? selectedVat),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final double? price =
                  double.tryParse(priceController.text.replaceAll(',', '.'));
              if (price != null && price >= 0) {
                menuRef.doc(product.productId).set({
                  'masterProductId': product.productId,
                  'price': price,
                  'vatRate': selectedVat,
                  'isVisible': true,
                }, SetOptions(merge: true));
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Veuillez entrer un prix valide.")));
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }
}
