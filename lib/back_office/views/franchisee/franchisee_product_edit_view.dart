// FILE: lib/backoffice/franchisee/franchisee_product_edit_view.dart
import 'package:flutter/material.dart';

import '../../../models.dart';

/// Vue permettant au franchisé de configurer un produit (ou un conteneur)
class FranchiseeProductEditView extends StatelessWidget {
  final Product product; // Le produit (qui peut être un conteneur)
  final List<Product> allFranchiseeProducts; // Tous les produits DU FRANCHISÉ (pour trouver les enfants)
  final Function(Product, double) onUpdatePrice; // Fonction pour sauvegarder le prix en base

  const FranchiseeProductEditView({
    super.key,
    required this.product,
    required this.allFranchiseeProducts,
    required this.onUpdatePrice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Config: ${product.name}")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Si c'est un produit normal, on édite son prix
            if (!product.isContainer)
              _buildPriceEditor(context, product),

            // Si c'est un conteneur, on affiche la liste des enfants pour modifier LEURS prix
            if (product.isContainer) ...[
              const Text(
                "Ce produit est un dossier. Voici ce qu'il contient :",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: _getContainerChildren().map((child) {
                    return Card(
                      child: ListTile(
                        title: Text(child.name),
                        subtitle: Text("Prix actuel: ${child.price.toStringAsFixed(2)} €"),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showPriceDialog(context, child),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  "NB: Le dossier lui-même n'a pas de prix. Seuls les produits à l'intérieur sont vendus.",
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  // Récupère les vrais objets produits enfants grâce aux IDs
  List<Product> _getContainerChildren() {
    return allFranchiseeProducts
        .where((p) => product.containerProductIds?.contains(p.id) ?? false)
        .toList();
  }

  Widget _buildPriceEditor(BuildContext context, Product p) {
    return ListTile(
      title: const Text("Prix de vente"),
      trailing: Text("${p.price.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      onTap: () => _showPriceDialog(context, p),
    );
  }

  void _showPriceDialog(BuildContext context, Product p) {
    final controller = TextEditingController(text: p.price.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Prix pour ${p.name}"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: "€"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final newPrice = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0.0;
              onUpdatePrice(p, newPrice); // Sauvegarde
              Navigator.pop(ctx);
            },
            child: const Text("Valider"),
          )
        ],
      ),
    );
  }
}