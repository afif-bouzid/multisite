// FILE: lib/backoffice/franchisor/product_creation_view.dart
import 'package:flutter/material.dart';

import '../../../models.dart';

class FranchisorProductCreationView extends StatefulWidget {
  // Supposons que vous passez la liste de tous les produits existants pour les mettre dans le conteneur
  final List<Product> availableProducts;
  final Function(Product) onSave;

  const FranchisorProductCreationView({Key? key, required this.availableProducts, required this.onSave}) : super(key: key);

  @override
  State<FranchisorProductCreationView> createState() => _FranchisorProductCreationViewState();
}

class _FranchisorProductCreationViewState extends State<FranchisorProductCreationView> {
  final _nameController = TextEditingController();
  bool _isContainer = false;
  final List<String> _selectedChildrenIds = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nouveau Produit Master")),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Nom du produit (ex: Frites)"),
            ),
            const SizedBox(height: 20),

            // TOGGLE : EST-CE UN DOSSIER ?
            SwitchListTile(
              title: const Text("Est-ce un conteneur (Dossier) ?"),
              subtitle: const Text("Cochez si ce produit sert à regrouper d'autres produits (ex: Frites -> Petite, Grande)"),
              value: _isContainer,
              onChanged: (val) => setState(() => _isContainer = val),
            ),

            // SÉLECTION DES ENFANTS (Seulement si c'est un conteneur)
            if (_isContainer) ...[
              const Divider(),
              const Text("Sélectionnez les produits inclus :", style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                height: 300,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                child: ListView.builder(
                  itemCount: widget.availableProducts.length,
                  itemBuilder: (context, index) {
                    final prod = widget.availableProducts[index];
                    // On évite de mettre un conteneur dans un conteneur pour simplifier
                    if (prod.isContainer) return const SizedBox.shrink();

                    final isChecked = _selectedChildrenIds.contains(prod.id);
                    return CheckboxListTile(
                      title: Text(prod.name),
                      value: isChecked,
                      onChanged: (bool? val) {
                        setState(() {
                          if (val == true) {
                            _selectedChildrenIds.add(prod.id);
                          } else {
                            _selectedChildrenIds.remove(prod.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Création du produit
                final newProduct = Product(
                  id: DateTime.now().millisecondsSinceEpoch.toString(), // ID temporaire
                  name: _nameController.text,
                  price: 0.0, // Le prix du conteneur n'est pas important
                  isContainer: _isContainer,
                  containerProductIds: _isContainer ? _selectedChildrenIds : [],
                );
                widget.onSave(newProduct);
                Navigator.pop(context);
              },
              child: const Text("Sauvegarder le Master"),
            )
          ],
        ),
      ),
    );
  }
}