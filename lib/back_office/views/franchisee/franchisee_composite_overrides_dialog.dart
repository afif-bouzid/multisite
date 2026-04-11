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
  bool _isLoading = false;
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
    final baseSections = await repository.getSectionsForProduct(
        widget.franchisorId, widget.product.sectionIds);
    final priceOverridesSnapshot =
    await _menuProductRef.collection('supplement_overrides').get();
    final priceOverrides = {
      for (var doc in priceOverridesSnapshot.docs)
        doc.id: (doc.data()['price'] as num?)?.toDouble() ?? 0.0
    };
    List<SectionOverrideData> finalData = [];
    for (var section in baseSections) {
      List<SectionItem> items = List.from(section.items);
      if (widget.product.ingredientProductIds.isNotEmpty) {
        items.sort((a, b) {
          int indexA = widget.product.ingredientProductIds.indexOf(a.product.productId);
          int indexB = widget.product.ingredientProductIds.indexOf(b.product.productId);
          if (indexA == -1) indexA = 999;
          if (indexB == -1) indexB = 999;
          return indexA.compareTo(indexB);
        });
      }
      for (var item in items) {
        final overridePrice = priceOverrides[item.product.productId];
        _priceControllers[item.product.productId] = TextEditingController(
          text: overridePrice != null ? overridePrice.toStringAsFixed(2) : "",
        );
      }
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
    _priceControllers.forEach((productId, controller) {
      final priceRef =
      _menuProductRef.collection('supplement_overrides').doc(productId);
      final textVal = controller.text.replaceAll(',', '.').trim();
      if (textVal.isNotEmpty) {
        final priceValue = double.tryParse(textVal);
        if (priceValue != null && priceValue >= 0) {
          batch.set(priceRef, {'price': priceValue}, SetOptions(merge: true));
        }
      } else {
        batch.delete(priceRef);
      }
    });
    try {
      await batch.commit();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Prix mis à jour ! Visible immédiatement en caisse."),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }
  @override
  void dispose() {
    for (var controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
  Widget _getSectionIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('increment') || t.contains('quantity') || t.contains('compteur')) {
      return const Icon(Icons.add_circle_outline, color: Colors.blue);
    } else if (t.contains('unique') || t.contains('radio')) {
      return const Icon(Icons.radio_button_checked, color: Colors.orange);
    } else {
      return const Icon(Icons.check_box, color: Colors.green);
    }
  }
  String _getSectionTypeText(String type) {
    final t = type.toLowerCase();
    if (t.contains('increment')) return "INCRÉMENTATION";
    if (t.contains('unique') || t.contains('radio')) return "CHOIX UNIQUE (RADIO)";
    return "CHOIX MULTIPLE (CHECKBOX)";
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_suggest, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text("Options de '${widget.product.name}'")),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        height: MediaQuery.of(context).size.height * 0.8,
        child: FutureBuilder<List<SectionOverrideData>>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return Center(child: Text("Erreur: ${snapshot.error}"));
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucune section trouvée."));
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final data = snapshot.data![index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          children: [
                            _getSectionIcon(data.section.type),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data.section.title.toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  Text(_getSectionTypeText(data.section.type),
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.grey.shade300)
                              ),
                              child: Text(
                                "MIN: ${data.section.selectionMin} / MAX: ${data.section.selectionMax == 0 ? '∞' : data.section.selectionMax}",
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.items.length,
                        separatorBuilder: (context, i) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = data.items[idx];
                          final controller = _priceControllers[item.product.productId];
                          return ListTile(
                            title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text("Prix base: ${item.supplementPrice.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 12)),
                            trailing: SizedBox(
                              width: 140,
                              child: TextField(
                                controller: controller,
                                textAlign: TextAlign.right,
                                decoration: const InputDecoration(
                                    labelText: "Prix perso (€)",
                                    hintText: "Défaut",
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    suffixText: "€"
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*([.,]?\d{0,2})'))],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _isLoading ? null : _saveChanges,
          icon: const Icon(Icons.save),
          label: const Text("Sauvegarder les prix"),
        ),
      ],
    );
  }
}
