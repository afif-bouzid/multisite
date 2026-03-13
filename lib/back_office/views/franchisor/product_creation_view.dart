import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models.dart';

class FranchisorProductCreationView extends StatefulWidget {
  final List<Product> availableProducts;
  final Function(Product, File?) onSave; // Modifié pour renvoyer aussi le fichier image si nécessaire

  const FranchisorProductCreationView({
    Key? key,
    required this.availableProducts,
    required this.onSave
  }) : super(key: key);

  @override
  State<FranchisorProductCreationView> createState() => _FranchisorProductCreationViewState();
}

class _FranchisorProductCreationViewState extends State<FranchisorProductCreationView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _ingredientsTextController = TextEditingController(); // Pour la fiche technique

  bool _isContainer = false;
  bool _isIngredient = false;

  XFile? _selectedImageFile;
  final List<String> _selectedChildrenIds = [];

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _selectedImageFile = image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nouveau Produit Master")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- 1. GESTION PHOTO (Avec bouton supprimer) ---
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                      image: _selectedImageFile != null
                          ? DecorationImage(image: FileImage(File(_selectedImageFile!.path)), fit: BoxFit.cover)
                          : null,
                    ),
                    child: _selectedImageFile == null
                        ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey)
                        : null,
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _pickImage,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Bouton Poubelle pour supprimer la photo
                  if (_selectedImageFile != null)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black26)]
                          ),
                          child: const Icon(Icons.delete, color: Colors.red, size: 18),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedImageFile = null;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- NOM ---
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Nom du produit (ex: Frites)",
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? "Nom requis" : null,
            ),
            const SizedBox(height: 16),

            // --- PRIX ---
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: "Prix TTC (€)",
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.euro),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return null; // Peut être 0
                if (double.tryParse(v.replaceAll(',', '.')) == null) return "Prix invalide";
                return null;
              },
            ),
            const SizedBox(height: 20),

            // --- TOGGLE : EST-CE UN INGRÉDIENT ? ---
            SwitchListTile(
              title: const Text("C'est un ingrédient ?"),
              subtitle: const Text("Sert aux fiches techniques, non vendu seul."),
              value: _isIngredient,
              onChanged: (val) {
                setState(() {
                  _isIngredient = val;
                  // Si c'est un ingrédient, ça ne peut généralement pas être un conteneur de menu
                  if (val) _isContainer = false;
                });
              },
            ),

            // --- CHAMPS CONDITIONNELS (Masqués si Ingrédient) ---
            if (!_isIngredient) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: "Description (Carte)",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ingredientsTextController,
                decoration: const InputDecoration(
                  labelText: "Ingrédients (Texte technique)",
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],

            const SizedBox(height: 20),

            // --- TOGGLE : EST-CE UN DOSSIER (CONTENEUR) ? ---
            if (!_isIngredient) // On masque souvent l'option conteneur pour un ingrédient simple
              SwitchListTile(
                title: const Text("Est-ce un conteneur (Dossier) ?"),
                subtitle: const Text("Regroupe d'autres produits (ex: Nos Burgers)"),
                value: _isContainer,
                onChanged: (val) => setState(() => _isContainer = val),
              ),

            // --- LISTE DES ENFANTS (Si Conteneur) ---
            if (_isContainer && !_isIngredient) ...[
              const SizedBox(height: 10),
              const Text("Sélectionnez les produits contenus :", style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                height: 200,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                child: ListView.builder(
                  itemCount: widget.availableProducts.length,
                  itemBuilder: (context, index) {
                    final prod = widget.availableProducts[index];
                    // On évite de s'ajouter soi-même ou d'ajouter d'autres conteneurs pour éviter les boucles
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

            const SizedBox(height: 30),

            // --- BOUTON SAUVEGARDER ---
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final double price = _priceController.text.isNotEmpty
                      ? double.parse(_priceController.text.replaceAll(',', '.'))
                      : 0.0;

                  // Création de l'objet Product
                  final newProduct = Product(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: _nameController.text,
                    price: price,
                    description: !_isIngredient ? _descriptionController.text : null,
                    // Note: imageUrl sera géré par le parent via le fichier renvoyé
                    isContainer: _isContainer,
                    // Le champ isIngredient n'existe peut-être pas dans votre modèle Product original
                    // (basé sur le snippet fourni), mais s'il existe, ajoutez: isIngredient: _isIngredient,
                    containerProductIds: _isContainer ? _selectedChildrenIds : [],
                  );

                  // On renvoie le produit ET le fichier image
                  widget.onSave(newProduct, _selectedImageFile != null ? File(_selectedImageFile!.path) : null);
                  Navigator.pop(context);
                }
              },
              child: const Text("Sauvegarder le Produit", style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}