import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';

class FranchiseeKioskConfigView extends StatefulWidget {
  const FranchiseeKioskConfigView({super.key});

  @override
  State<FranchiseeKioskConfigView> createState() =>
      _FranchiseeKioskConfigViewState();
}

class _FranchiseeKioskConfigViewState extends State<FranchiseeKioskConfigView> {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuration Contenu Borne"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      backgroundColor: const Color(0xFFF5F5F7),
      body: StreamBuilder<List<MasterProduct>>(
        // 1. On récupère d'abord TOUS les produits visibles sur le POS pour ce franchisé
        stream: repository.getFranchiseeVisibleProductsStream(
            franchiseeId, franchisorId),
        builder: (context, productSnapshot) {
          if (productSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!productSnapshot.hasData) {
            return const Center(child: Text("Erreur chargement produits POS."));
          }

          // On ne garde que les produits vendables (pas les ingrédients)
          // C'est la "Vérité POS"
          final allPosProducts =
              productSnapshot.data!.where((p) => !p.isIngredient).toList();

          return StreamBuilder<List<KioskCategory>>(
            // 2. On récupère la structure de la borne
            stream: repository.getKioskCategoriesStream(franchisorId),
            builder: (context, categorySnapshot) {
              if (categorySnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!categorySnapshot.hasData || categorySnapshot.data!.isEmpty) {
                return const Center(
                    child: Text("Aucune catégorie borne définie."));
              }

              final categories = categorySnapshot.data!;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];

                  // On prépare les filtres à afficher pour cette catégorie
                  // On ne garde que les filtres qui contiennent au moins un produit disponible dans le POS
                  final visibleFiltersWidgets = category.filters
                      .map((filter) {
                        // On trouve les produits du POS qui appartiennent à ce filtre
                        final productsForThisFilter = allPosProducts
                            .where((p) => p.kioskFilterIds.contains(filter.id))
                            .toList();

                        // "PAS DE FILTRE FANTÔME" : Si aucun produit POS ne correspond, on ne retourne rien
                        if (productsForThisFilter.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return _buildFilterTile(context, franchiseeId, filter,
                            productsForThisFilter);
                      })
                      .where((w) => w is! SizedBox)
                      .toList();

                  // Si la catégorie entière est vide (tous les filtres sont vides), on ne l'affiche pas
                  if (visibleFiltersWidgets.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                if (category.imageUrl != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12.0),
                                    child: CircleAvatar(
                                      backgroundImage:
                                          CachedNetworkImageProvider(
                                              category.imageUrl!),
                                      radius: 20,
                                    ),
                                  ),
                                Text(category.name.toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 20,
                                            color: Theme.of(context)
                                                .primaryColor)),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ...visibleFiltersWidgets,
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
    );
  }

  Widget _buildFilterTile(BuildContext context, String franchiseeId,
      KioskFilter filter, List<MasterProduct> productsForThisFilter) {
    final configRef = FirebaseFirestore.instance
        .collection('users')
        .doc(franchiseeId)
        .collection('kiosk_config')
        .doc(filter.id);

    return StreamBuilder<DocumentSnapshot>(
      stream: configRef.snapshots(),
      builder: (context, snapshot) {
        // Par défaut (si pas de config), tout est activé
        int activeCount = productsForThisFilter.length;
        bool isConfigured = false;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final allowedIds = Set<String>.from(data['productIds'] ?? []);

          // On compte combien de produits POS actuels sont autorisés dans la config
          activeCount = productsForThisFilter
              .where((p) => allowedIds.contains(p.productId))
              .length;
          isConfigured = true;
        }

        // Tri alphabétique pour l'affichage
        productsForThisFilter.sort((a, b) => a.name.compareTo(b.name));

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: filter.imageUrl != null
              ? CircleAvatar(
                  backgroundImage: CachedNetworkImageProvider(filter.imageUrl!),
                  backgroundColor: Colors.grey.shade200)
              : const Icon(Icons.label_outline, color: Colors.grey),
          title: Text(filter.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Row(
            children: [
              Icon(
                  activeCount == productsForThisFilter.length
                      ? Icons.check_circle
                      : Icons.remove_circle,
                  size: 14,
                  color: activeCount == productsForThisFilter.length
                      ? Colors.green
                      : Colors.orange),
              const SizedBox(width: 4),
              Text(
                '$activeCount / ${productsForThisFilter.length} affichés',
                style: TextStyle(
                    color: activeCount == productsForThisFilter.length
                        ? Colors.green
                        : Colors.orange.shade800,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          trailing: ElevatedButton.icon(
            icon: const Icon(Icons.tune, size: 16),
            label: const Text("Exclure / Gérer"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              _showProductAssignmentDialog(
                context,
                filter: filter,
                configRef: configRef,
                productsForThisFilter: productsForThisFilter,
                currentlyAssigned: isConfigured ? snapshot.data : null,
              );
            },
          ),
        );
      },
    );
  }

  void _showProductAssignmentDialog(BuildContext context,
      {required KioskFilter filter,
      required DocumentReference configRef,
      required List<MasterProduct> productsForThisFilter,
      DocumentSnapshot? currentlyAssigned}) {
    showDialog(
      context: context,
      builder: (context) => ProductAssignmentDialog(
        filter: filter,
        configRef: configRef,
        productsForThisFilter: productsForThisFilter,
        currentlyAssigned: currentlyAssigned,
      ),
    );
  }
}

class ProductAssignmentDialog extends StatefulWidget {
  final KioskFilter filter;
  final DocumentReference configRef;
  final List<MasterProduct> productsForThisFilter;
  final DocumentSnapshot? currentlyAssigned;

  const ProductAssignmentDialog(
      {super.key,
      required this.filter,
      required this.configRef,
      required this.productsForThisFilter,
      this.currentlyAssigned});

  @override
  State<ProductAssignmentDialog> createState() =>
      _ProductAssignmentDialogState();
}

class _ProductAssignmentDialogState extends State<ProductAssignmentDialog> {
  late Set<String> _allowedProductIds;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    if (widget.currentlyAssigned != null && widget.currentlyAssigned!.exists) {
      // Cas 1 : Une config existe déjà, on la respecte
      final data = widget.currentlyAssigned!.data() as Map<String, dynamic>;
      _allowedProductIds = Set<String>.from(data['productIds'] ?? []);
    } else {
      // Cas 2 : Pas de config (nouveau filtre ou jamais touché)
      // => PAR DÉFAUT : TOUT EST COCHÉ (Logique "Blacklist" demandée)
      _allowedProductIds =
          widget.productsForThisFilter.map((p) => p.productId).toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filtrage local pour la recherche dans le dialogue
    final displayedProducts = widget.productsForThisFilter.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility, color: Colors.blueGrey),
              const SizedBox(width: 10),
              Expanded(child: Text("Visibilité : ${widget.filter.name}")),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Décochez les produits que vous ne voulez PAS vendre sur la borne (ex: Alcool).",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: "Filtrer la liste...",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          )
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: displayedProducts.isEmpty
            ? const Center(child: Text("Aucun produit correspondant."))
            : Column(
                children: [
                  // Actions rapides
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => setState(() {
                                  // Tout cocher
                                  _allowedProductIds.addAll(displayedProducts
                                      .map((p) => p.productId));
                                }),
                            child: const Text("Tout activer")),
                        TextButton(
                            onPressed: () => setState(() {
                                  // Tout décocher
                                  _allowedProductIds.removeAll(displayedProducts
                                      .map((p) => p.productId));
                                }),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text("Tout masquer")),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: displayedProducts.length,
                      itemBuilder: (context, index) {
                        final product = displayedProducts[index];
                        final isAllowed =
                            _allowedProductIds.contains(product.productId);

                        return SwitchListTile(
                          title: Text(product.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isAllowed ? Colors.black : Colors.grey,
                                  decoration: isAllowed
                                      ? null
                                      : TextDecoration.lineThrough)),
                          subtitle: product.isComposite
                              ? const Text("Menu",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.purple))
                              : null,
                          value: isAllowed,
                          activeColor: Colors.green,
                          inactiveTrackColor: Colors.red.shade100,
                          onChanged: (val) {
                            setState(() {
                              if (val) {
                                _allowedProductIds.add(product.productId);
                              } else {
                                _allowedProductIds.remove(product.productId);
                              }
                            });
                          },
                          secondary: Icon(
                              isAllowed
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: isAllowed ? Colors.green : Colors.red),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          onPressed: () {
            // Sauvegarde la liste des IDs AUTORISÉS (Whitelist)
            widget.configRef.set({'productIds': _allowedProductIds.toList()});
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Configuration mise à jour avec succès."),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ));
          },
          child: const Text("Enregistrer les modifications"),
        ),
      ],
    );
  }
}
