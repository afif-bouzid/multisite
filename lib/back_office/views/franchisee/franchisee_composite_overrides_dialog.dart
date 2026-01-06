import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/repository/repository.dart';
import '../../../models.dart';

class SectionOverrideData {
  final ProductSection section;
  List<SectionItem> items;
  final Map<String, double> priceOverrides;

  SectionOverrideData({
    required this.section,
    required this.items,
    required this.priceOverrides,
  });
}

class FranchiseeCompositeOverridesDialog extends StatefulWidget {
  final String franchiseeId;
  final String franchisorId;
  final MasterProduct product;

  const FranchiseeCompositeOverridesDialog({
    super.key,
    required this.franchiseeId,
    required this.franchisorId,
    required this.product,
  });

  @override
  State<FranchiseeCompositeOverridesDialog> createState() =>
      _FranchiseeCompositeOverridesDialogState();
}

class _FranchiseeCompositeOverridesDialogState
    extends State<FranchiseeCompositeOverridesDialog> {
  late Future<List<SectionOverrideData>> _dataFuture;
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, List<SectionItem>> _orderedItems = {};
  bool _isLoading = false;

  // Référence à la sous-collection du menu franchisé pour ce produit
  late final DocumentReference _menuProductRef;

  @override
  void initState() {
    super.initState();
    _menuProductRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.franchiseeId)
        .collection('menu')
        .doc(widget.product.productId);

    _dataFuture = _loadData();
  }

  Future<List<SectionOverrideData>> _loadData() async {
    final repository = FranchiseRepository();

    // 1. Récupérer les sections de base (ordre et items du franchiseur)
    final baseSections = await repository.getSectionsForProduct(
        widget.franchisorId, widget.product.sectionIds);

    // 2. Récupérer les overrides de prix
    final priceOverridesSnapshot =
        await _menuProductRef.collection('supplement_overrides').get();
    final priceOverrides = {
      for (var doc in priceOverridesSnapshot.docs)
        doc.id: (doc.data()['price'] as num?)?.toDouble() ?? 0.0
    };

    // 3. Récupérer les overrides d'ordre
    final orderOverridesSnapshot =
        await _menuProductRef.collection('section_overrides').get();
    final orderOverrides = {
      for (var doc in orderOverridesSnapshot.docs)
        doc.id: List<String>.from(doc.data()['itemOrder'] ?? [])
    };

    List<SectionOverrideData> finalData = [];
    for (var section in baseSections) {
      List<SectionItem> items = List.from(section.items);
      final order = orderOverrides[section.sectionId];

      if (order != null && order.isNotEmpty) {
        // Appliquer l'ordre personnalisé
        items.sort((a, b) {
          int indexA = order.indexOf(a.product.productId);
          int indexB = order.indexOf(b.product.productId);
          if (indexA == -1) indexA = 999;
          if (indexB == -1) indexB = 999;
          return indexA.compareTo(indexB);
        });
      }

      // Initialiser les contrôleurs de prix
      for (var item in items) {
        final overridePrice = priceOverrides[item.product.productId];
        _priceControllers[item.product.productId] = TextEditingController(
          text: overridePrice?.toStringAsFixed(2),
        );
      }

      // Stocker l'ordre initial (pour le drag-and-drop)
      _orderedItems[section.sectionId] = items;

      finalData.add(SectionOverrideData(
        section: section,
        items: items,
        priceOverrides: priceOverrides,
      ));
    }

    finalData.sort((a, b) {
      int indexA = widget.product.sectionIds.indexOf(a.section.sectionId);
      int indexB = widget.product.sectionIds.indexOf(b.section.sectionId);
      return indexA.compareTo(indexB);
    });

    return finalData;
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    final batch = FirebaseFirestore.instance.batch();

    // 1. Sauvegarder les PRIX
    _priceControllers.forEach((productId, controller) {
      final priceRef =
          _menuProductRef.collection('supplement_overrides').doc(productId);
      final priceValue = double.tryParse(controller.text.replaceAll(',', '.'));

      if (priceValue != null && priceValue >= 0) {
        // Sauvegarde le nouveau prix
        batch.set(priceRef, {'price': priceValue});
      } else {
        // Si le champ est vide ou invalide, on supprime l'override
        batch.delete(priceRef);
      }
    });

    // 2. Sauvegarder l'ORDRE
    _orderedItems.forEach((sectionId, items) {
      final orderRef =
          _menuProductRef.collection('section_overrides').doc(sectionId);
      final itemOrder = items.map((item) => item.product.productId).toList();
      batch.set(orderRef, {'itemOrder': itemOrder});
    });

    try {
      await batch.commit();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Options et prix des suppléments mis à jour."),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur de sauvegarde: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Gérer les options de '${widget.product.name}'"),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.6, // 60% de la largeur
        height: MediaQuery.of(context).size.height * 0.7, // 70% de la hauteur
        child: FutureBuilder<List<SectionOverrideData>>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                _isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text("Erreur: ${snapshot.error}"));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("Aucune section trouvée."));
            }

            final sectionDataList = snapshot.data!;

            return ListView.builder(
              itemCount: sectionDataList.length,
              itemBuilder: (context, index) {
                final sectionData = sectionDataList[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: Text(sectionData.section.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${sectionData.items.length} options"),
                    initiallyExpanded: index == 0,
                    children: [
                      _buildReorderableList(sectionData.section.sectionId)
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annuler"),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          child: const Text("Sauvegarder"),
        ),
      ],
    );
  }

  Widget _buildReorderableList(String sectionId) {
    final items = _orderedItems[sectionId] ?? [];

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final controller = _priceControllers[item.product.productId];

        return Container(
          key: ValueKey(item.product.id),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
          ),
          child: ListTile(
            leading: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
            title: Text(item.product.name),
            subtitle: Text(
                "Prix de base: ${item.supplementPrice.toStringAsFixed(2)} €"),
            trailing: SizedBox(
              width: 150,
              child: TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "Prix personnalisé (€)",
                  hintText: "Aucun (base)",
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*([.,]?\d{0,2})')),
                ],
              ),
            ),
          ),
        );
      },
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _orderedItems[sectionId]!.removeAt(oldIndex);
          _orderedItems[sectionId]!.insert(newIndex, item);
        });
      },
    );
  }
}
