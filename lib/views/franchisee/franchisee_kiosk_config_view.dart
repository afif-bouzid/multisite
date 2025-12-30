import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';

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

    return Scaffold(
      body: StreamBuilder<List<KioskCategory>>(
        stream: FranchiseRepository().getKioskCategoriesStream(franchisorId),
        builder: (context, categorySnapshot) {
          if (categorySnapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (!categorySnapshot.hasData || categorySnapshot.data!.isEmpty)
            return const Center(
                child: Text(
                    "La structure de la borne n'a pas encore été définie par le franchiseur."));

          final categories = categorySnapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(category.name,
                            style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      ...category.filters.map((filter) {
                        return _buildFilterTile(
                            context, franchiseeId, franchisorId, filter);
                      }).toList(),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterTile(BuildContext context, String franchiseeId,
      String franchisorId, KioskFilter filter) {
    final configRef = FirebaseFirestore.instance
        .collection('users')
        .doc(franchiseeId)
        .collection('kiosk_config')
        .doc(filter.id);

    return StreamBuilder<DocumentSnapshot>(
      stream: configRef.snapshots(),
      builder: (context, snapshot) {
        int assignedProductCount = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          assignedProductCount = (data['productIds'] as List?)?.length ?? 0;
        }

        return ListTile(
          title: Text(filter.name),
          subtitle: Text('$assignedProductCount produit(s) associé(s)'),
          trailing: ElevatedButton(
            child: const Text("Gérer les produits"),
            onPressed: () async {
              final availableProducts = await FranchiseRepository()
                  .getFranchiseeVisibleProductsStream(
                      franchiseeId, franchisorId)
                  .first;

              if (context.mounted) {
                _showProductAssignmentDialog(
                  context,
                  filter: filter,
                  configRef: configRef,
                  availableProducts: availableProducts,
                  currentlyAssigned: snapshot.data,
                );
              }
            },
          ),
        );
      },
    );
  }

  void _showProductAssignmentDialog(BuildContext context,
      {required KioskFilter filter,
      required DocumentReference configRef,
      required List<MasterProduct> availableProducts,
      DocumentSnapshot? currentlyAssigned}) {
    showDialog(
      context: context,
      builder: (context) => ProductAssignmentDialog(
        filter: filter,
        configRef: configRef,
        availableProducts: availableProducts,
        currentlyAssigned: currentlyAssigned,
      ),
    );
  }
}

class ProductAssignmentDialog extends StatefulWidget {
  final KioskFilter filter;
  final DocumentReference configRef;
  final List<MasterProduct> availableProducts;
  final DocumentSnapshot? currentlyAssigned;

  const ProductAssignmentDialog(
      {super.key,
      required this.filter,
      required this.configRef,
      required this.availableProducts,
      this.currentlyAssigned});

  @override
  State<ProductAssignmentDialog> createState() =>
      _ProductAssignmentDialogState();
}

class _ProductAssignmentDialogState extends State<ProductAssignmentDialog> {
  late Set<String> _selectedProductIds;

  @override
  void initState() {
    super.initState();
    if (widget.currentlyAssigned != null && widget.currentlyAssigned!.exists) {
      final data = widget.currentlyAssigned!.data() as Map<String, dynamic>;
      _selectedProductIds = Set<String>.from(data['productIds'] ?? []);
    } else {
      _selectedProductIds = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Assigner des produits à '${widget.filter.name}'"),
      content: SizedBox(
        width: 500,
        child: widget.availableProducts.isEmpty
            ? const Center(
                child: Text("Aucun produit activé dans votre catalogue."))
            : ListView.builder(
                itemCount: widget.availableProducts.length,
                itemBuilder: (context, index) {
                  final product = widget.availableProducts[index];
                  final isSelected =
                      _selectedProductIds.contains(product.productId);
                  return CheckboxListTile(
                    title: Text(product.name),
                    value: isSelected,
                    onChanged: (selected) {
                      setState(() {
                        if (selected!) {
                          _selectedProductIds.add(product.productId);
                        } else {
                          _selectedProductIds.remove(product.productId);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: () {
            widget.configRef.set({'productIds': _selectedProductIds.toList()});
            Navigator.pop(context);
          },
          child: const Text("Sauvegarder"),
        ),
      ],
    );
  }
}
