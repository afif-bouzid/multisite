import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/auth_provider.dart';
import '../../../../core/repository/repository.dart';
import '../../../models.dart';

class FranchiseeKioskConfigView extends StatefulWidget {
  const FranchiseeKioskConfigView({super.key});

  @override
  State<FranchiseeKioskConfigView> createState() =>
      _FranchiseeKioskConfigViewState();
}

class _FranchiseeKioskConfigViewState extends State<FranchiseeKioskConfigView> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final franchiseUser = authProvider.franchiseUser;
    final firebaseUser = authProvider.firebaseUser;

    if (franchiseUser?.franchisorId == null || firebaseUser?.uid == null) {
      return const Center(
          child: Text("Erreur: Données utilisateur introuvables."));
    }

    final franchisorId = franchiseUser!.franchisorId!;
    final franchiseeId = firebaseUser!.uid;
    final repository = FranchiseRepository();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Configuration Borne"),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 1,
          bottom: const TabBar(
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.amber,
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: "Produits & Visibilité"),
              Tab(icon: Icon(Icons.wallpaper), text: "Écran de Veille"),
            ],
          ),
        ),
        backgroundColor: const Color(0xFFF5F5F7),
        body: TabBarView(
          children: [
            _buildProductsTab(repository, franchiseeId, franchisorId),
            _buildScreensaverTab(franchisorId, franchiseeId, repository),
          ],
        ),
      ),
    );
  }

  Widget _buildScreensaverTab(String franchisorId, String franchiseeId,
      FranchiseRepository repository) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Icon(Icons.photo_library, color: Colors.amber),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Sélectionnez vos images. La numérotation indique l'ordre d'affichage.",
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isUpdating) const LinearProgressIndicator(color: Colors.amber),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(franchiseeId)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final userData =
                  userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

              List<String> rawSelection = [];
              if (userData['screensaverUrls'] != null) {
                rawSelection = List<String>.from(userData['screensaverUrls']);
              } else if (userData['screensaverUrl'] != null &&
                  userData['screensaverUrl'] != "") {
                rawSelection.add(userData['screensaverUrl']);
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('kiosk_medias')
                    .where('franchisorId', isEqualTo: franchisorId)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, mediaSnapshot) {
                  if (!mediaSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = mediaSnapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                        child: Text("Aucune image disponible."));
                  }

                  final Set<String> availableUrls = docs
                      .map((d) =>
                          (d.data() as Map<String, dynamic>)['url'] as String)
                      .toSet();

                  final List<String> cleanSelection = rawSelection
                      .where((url) =>
                          url.isNotEmpty && availableUrls.contains(url))
                      .toList();

                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final url = data['url'];

                      final isSelected = cleanSelection.contains(url);
                      final selectionIndex = cleanSelection.indexOf(url) + 1;

                      return InkWell(
                        onTap: _isUpdating
                            ? null
                            : () async {
                                setState(() => _isUpdating = true);

                                List<String> newSelection =
                                    List.from(cleanSelection);

                                if (isSelected) {
                                  newSelection.remove(url);
                                } else {
                                  newSelection.add(url);
                                }

                                try {
                                  await repository.updateKioskScreensaver(
                                      franchiseeId, newSelection);
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Erreur: $e")));
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isUpdating = false);
                                  }
                                }
                              },
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: isSelected
                                    ? Border.all(color: Colors.amber, width: 4)
                                    : Border.all(color: Colors.grey.shade300),
                                image: DecorationImage(
                                  image: CachedNetworkImageProvider(url),
                                  fit: BoxFit.cover,
                                  colorFilter: isSelected
                                      ? ColorFilter.mode(
                                          Colors.black.withValues(alpha: 0.4),
                                          BlendMode.darken)
                                      : null,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.amber,
                                      boxShadow: [
                                        BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4)
                                      ]),
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    "$selectionIndex",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ),
                              ),
                          ],
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
    );
  }

  Widget _buildProductsTab(FranchiseRepository repository, String franchiseeId,
      String franchisorId) {
    return StreamBuilder<List<MasterProduct>>(
      stream: repository.getFranchiseeVisibleProductsStream(
          franchiseeId, franchisorId),
      builder: (context, productSnapshot) {
        if (productSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!productSnapshot.hasData) {
          return const Center(child: Text("Erreur chargement produits POS."));
        }
        final allPosProducts =
            productSnapshot.data!.where((p) => !p.isIngredient).toList();

        return StreamBuilder<List<KioskCategory>>(
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
                final visibleFiltersWidgets = category.filters
                    .map((filter) {
                      final productsForThisFilter = allPosProducts
                          .where((p) => p.kioskFilterIds.contains(filter.id))
                          .toList();

                      if (productsForThisFilter.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _buildFilterTile(
                          context, franchiseeId, filter, productsForThisFilter);
                    })
                    .where((w) => w is! SizedBox)
                    .toList();

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
                                    backgroundImage: CachedNetworkImageProvider(
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
                                          color:
                                              Theme.of(context).primaryColor)),
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
        int activeCount = productsForThisFilter.length;
        bool isConfigured = false;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final allowedIds = Set<String>.from(data['productIds'] ?? []);
          activeCount = productsForThisFilter
              .where((p) => allowedIds.contains(p.productId))
              .length;
          isConfigured = true;
        }

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
      final data = widget.currentlyAssigned!.data() as Map<String, dynamic>;
      _allowedProductIds = Set<String>.from(data['productIds'] ?? []);
    } else {
      _allowedProductIds =
          widget.productsForThisFilter.map((p) => p.productId).toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            "Décochez les produits que vous ne voulez PAS vendre sur la borne.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: "Rechercher...",
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => setState(() =>
                              _allowedProductIds.addAll(
                                  displayedProducts.map((p) => p.productId))),
                          child: const Text("Tout sélectionner")),
                      TextButton(
                          onPressed: () => setState(() =>
                              _allowedProductIds.removeAll(
                                  displayedProducts.map((p) => p.productId))),
                          child: const Text("Tout désélectionner",
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: displayedProducts.length,
                      itemBuilder: (context, index) {
                        final product = displayedProducts[index];
                        final isAllowed =
                            _allowedProductIds.contains(product.productId);
                        return CheckboxListTile(
                          title: Text(product.name,
                              style: TextStyle(
                                  decoration: isAllowed
                                      ? null
                                      : TextDecoration.lineThrough,
                                  color:
                                      isAllowed ? Colors.black : Colors.grey)),
                          value: isAllowed,
                          activeColor: Colors.green,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _allowedProductIds.add(product.productId);
                              } else {
                                _allowedProductIds.remove(product.productId);
                              }
                            });
                          },
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
          onPressed: () async {
            await widget.configRef.set({
              'productIds': _allowedProductIds.toList(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            if (mounted) Navigator.pop(context);
          },
          child: const Text("Enregistrer"),
        )
      ],
    );
  }
}
