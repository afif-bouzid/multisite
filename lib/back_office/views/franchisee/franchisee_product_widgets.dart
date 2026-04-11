import 'package:flutter/material.dart';
import '../../../models.dart';
class ContainerSelectionDialog extends StatelessWidget {
  final Product containerProduct;
  final List<Product> allProducts; 
  final Function(Product) onProductSelected; 
  const ContainerSelectionDialog({
    Key? key,
    required this.containerProduct,
    required this.allProducts,
    required this.onProductSelected,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final List<Product> childrenProducts = allProducts
        .where((p) => containerProduct.containerProductIds.contains(p.id))
        .toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Row(
        children: [
          const Icon(Icons.folder_open_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Text(
            containerProduct.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 600, 
        height: 400,
        child: childrenProducts.isEmpty
            ? const Center(child: Text("Ce dossier est vide."))
            : GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, 
            childAspectRatio: 0.8,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: childrenProducts.length,
          itemBuilder: (context, index) {
            final product = childrenProducts[index];
            return InkWell(
              onTap: () {
                onProductSelected(product);
              },
              child: Card(
                elevation: 2,
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                          ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                          : Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Text(
                            product.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "${product.price.toStringAsFixed(2)} €",
                            style: const TextStyle(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
          child: const Text('FERMER LE DOSSIER'),
        ),
      ],
    );
  }
}
class FranchiseeProductCard extends StatelessWidget {
  final Product product;
  final List<Product> allProducts; 
  final Function(Product) onAddToCart; 
  const FranchiseeProductCard({
    Key? key,
    required this.product,
    required this.allProducts,
    required this.onAddToCart,
  }) : super(key: key);
  void _handleTap(BuildContext context) {
    if (product.isContainer) {
      showDialog(
        context: context,
        builder: (context) => ContainerSelectionDialog(
          containerProduct: product,
          allProducts: allProducts,
          onProductSelected: (selectedChild) {
            onAddToCart(selectedChild);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("${selectedChild.name} ajouté !"),
                duration: const Duration(milliseconds: 500),
              ),
            );
          },
        ),
      );
    } else {
      onAddToCart(product);
    }
  }
  @override
  Widget build(BuildContext context) {
    final isFolder = product.isContainer;
    final cardColor = isFolder ? Colors.orange.shade50 : Colors.white;
    final borderColor = isFolder ? Colors.orange.shade200 : Colors.grey.shade200;
    return InkWell(
      onTap: () => _handleTap(context),
      child: Card(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                        ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                        : Icon(
                      isFolder ? Icons.folder_copy_rounded : Icons.fastfood_rounded,
                      size: 40,
                      color: isFolder ? Colors.orange : Colors.grey,
                    ),
                  ),
                  if (isFolder)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "DOSSIER",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      isFolder
                          ? "Ouvrir..."
                          : "${product.price.toStringAsFixed(2)} €",
                      style: TextStyle(
                        color: isFolder ? Colors.orange[800] : Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
