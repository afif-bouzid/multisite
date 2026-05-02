import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '/models.dart';

class FranchiseeContainerConfigDialog extends StatefulWidget {
  final MasterProduct containerProduct;
  final List<MasterProduct> allProducts;
  final Map<String, FranchiseeMenuItem> franchiseeSettings;
  final Function(MasterProduct, double) onUpdateChildPrice;
  const FranchiseeContainerConfigDialog({
    super.key,
    required this.containerProduct,
    required this.allProducts,
    required this.franchiseeSettings,
    required this.onUpdateChildPrice,
  });
  @override
  State<FranchiseeContainerConfigDialog> createState() =>
      _FranchiseeContainerConfigDialogState();
}

class _FranchiseeContainerConfigDialogState
    extends State<FranchiseeContainerConfigDialog> {
  final Map<String, TextEditingController> _controllers = {};
  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final children = _getContainerChildren();
    for (var child in children) {
      String initialPrice = '';
      if (widget.franchiseeSettings.containsKey(child.productId)) {
        final settings = widget.franchiseeSettings[child.productId]!;
        initialPrice = settings.price?.toStringAsFixed(2) ?? '';
      }
      _controllers[child.id] = TextEditingController(text: initialPrice);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<MasterProduct> _getContainerChildren() {
    if (widget.containerProduct.containerProductIds.isEmpty) return [];
    return widget.containerProduct.containerProductIds
        .map((childId) {
          try {
            return widget.allProducts.firstWhere(
              (p) => p.id == childId,
            );
          } catch (e) {
            print("Produit enfant introuvable pour l'ID: $childId");
            return null;
          }
        })
        .whereType<MasterProduct>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final children = _getContainerChildren();
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Configuration du Menu"),
          Text(
            widget.containerProduct.name,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: children.isEmpty
            ? const Center(
                child: Text(
                    "Ce conteneur semble vide ou les produits liés sont introuvables."),
              )
            : ListView.separated(
                itemCount: children.length,
                separatorBuilder: (c, i) => const Divider(),
                itemBuilder: (context, index) {
                  final child = children[index];
                  final controller = _controllers[child.id];
                  return ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        image: (child.photoUrl != null &&
                                child.photoUrl!.isNotEmpty)
                            ? DecorationImage(
                                image:
                                    CachedNetworkImageProvider(child.photoUrl!),
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: (child.photoUrl == null || child.photoUrl!.isEmpty)
                          ? const Icon(Icons.fastfood,
                              size: 20, color: Colors.grey)
                          : null,
                    ),
                    title: Text(child.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(child.isIngredient
                        ? "Ingrédient / Produit Interne"
                        : "Produit standard"),
                    trailing: SizedBox(
                      width: 100,
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: "Prix €",
                          hintText: child.price?.toStringAsFixed(2) ?? "0.00",
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0),
                        ),
                        onChanged: (val) {},
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Fermer"),
        ),
        ElevatedButton(
          onPressed: () {
            for (var child in children) {
              final ctrl = _controllers[child.id];
              if (ctrl != null) {
                final double? newPrice =
                    double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (newPrice != null && newPrice >= 0) {
                  widget.onUpdateChildPrice(child, newPrice);
                }
              }
            }
            Navigator.pop(context);
          },
          child: const Text("Enregistrer tout"),
        )
      ],
    );
  }
}
