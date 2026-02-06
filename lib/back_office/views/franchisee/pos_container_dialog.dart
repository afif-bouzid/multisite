import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '/models.dart';

class PosContainerDialog extends StatelessWidget {
  final MasterProduct container;
  final List<MasterProduct> allProducts;
  final Function(MasterProduct) onProductSelected;

  const PosContainerDialog({
    super.key,
    required this.container,
    required this.allProducts,
    required this.onProductSelected,
  });

  @override
  Widget build(BuildContext context) {
    final List<MasterProduct> children = _getContainerChildren();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 600, // Largeur adaptée pour la caisse
        height: 500,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    container.name.toUpperCase(),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const Divider(),

            // Grille des produits contenus
            Expanded(
              child: children.isEmpty
                  ? const Center(
                child: Text(
                  "Aucun produit trouvé dans ce dossier.",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              )
                  : GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // 3 produits par ligne
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: children.length,
                itemBuilder: (context, index) {
                  final product = children[index];
                  return _buildProductCard(context, product);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, MasterProduct product) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onProductSelected(product);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image du produit
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                  imageUrl: product.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey[200]),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                )
                    : Container(
                  color: Colors.grey[100],
                  child: Icon(Icons.fastfood, size: 40, color: Colors.grey[400]),
                ),
              ),
            ),
            // Nom du produit
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                product.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<MasterProduct> _getContainerChildren() {
    if (container.containerProductIds.isEmpty) return [];

    return container.containerProductIds.map((childId) {
      try {
        return allProducts.firstWhere((p) => p.id == childId);
      } catch (e) {
        return null;
      }
    }).whereType<MasterProduct>().toList();
  }
}