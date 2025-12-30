import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/constants.dart';
import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';

class KioskView extends StatefulWidget {
  const KioskView({super.key});

  @override
  State<KioskView> createState() => _KioskViewState();
}

class _KioskViewState extends State<KioskView> {
  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return Scaffold(
      body: StreamBuilder<List<KioskCategory>>(
        stream: repository.getKioskCategoriesStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erreur: ${snapshot.error}"));
          }

          // On crée une copie modifiable de la liste pour le ReorderableListView
          final categories = snapshot.data ?? [];

          if (categories.isEmpty) {
            return const Center(
                child: Text(
                    "Aucune catégorie de borne créée. Commencez par en ajouter une."));
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            onReorder: (oldIndex, newIndex) async {
              // Mise à jour visuelle immédiate (optimistic UI pas strict ici car StreamBuilder va rafraîchir,
              // mais nécessaire pour la fluidité du DnD)
              if (newIndex > oldIndex) newIndex -= 1;
              final item = categories.removeAt(oldIndex);
              categories.insert(newIndex, item);

              // Sauvegarde en base
              await repository.updateKioskCategoriesOrder(categories);
            },
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                key: ValueKey(category.id),
                // Clé unique indispensable pour le DnD
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      image: category.imageUrl != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(
                                  category.imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: category.imageUrl == null
                        ? const Icon(Icons.image_not_supported_outlined,
                            color: Colors.grey)
                        : null,
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Poignée de déplacement explicite (optionnel, mais aide l'UX)
                      const Icon(Icons.drag_handle, color: Colors.grey),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: "Modifier",
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) =>
                              CategoryEditorDialog(category: category),
                        ),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: "Supprimer",
                        onPressed: () => _confirmDeleteCategory(
                            context, repository, category),
                      ),
                    ],
                  ),
                  children: [
                    // Liste des filtres (sous-catégories)
                    if (category.filters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text("Aucun filtre dans cette catégorie.",
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ...category.filters.map((filter) => ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 32, right: 16),
                          leading: filter.imageUrl != null
                              ? CircleAvatar(
                                  backgroundImage: CachedNetworkImageProvider(
                                      filter.imageUrl!),
                                  radius: 16)
                              : Icon(Icons.label_important_outline,
                                  size: 20,
                                  color:
                                      colorFromHex(filter.color ?? '#000000')),
                          title: Text(filter.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: "Modifier le filtre",
                                onPressed: () => _showFilterDialog(
                                  context,
                                  repository,
                                  category.id,
                                  filter: filter,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: "Supprimer le filtre",
                                onPressed: () => repository.deleteKioskFilter(
                                  categoryId: category.id,
                                  filterId: filter.id,
                                ),
                              ),
                            ],
                          ),
                        )),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text("Ajouter un filtre (sous-catégorie)"),
                        onPressed: () => _showFilterDialog(
                          context,
                          repository,
                          category.id,
                          nextPosition: category.filters.length,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDeleteCategory(
      BuildContext context, FranchiseRepository repo, KioskCategory category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la catégorie ?"),
        content: Text(
            "Voulez-vous vraiment supprimer '${category.name}' et tous ses filtres ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              repo.deleteKioskCategory(category.id);
              Navigator.pop(ctx);
            },
            child: const Text("Supprimer"),
          )
        ],
      ),
    );
  }

  void _showFilterDialog(
      BuildContext context, FranchiseRepository repository, String categoryId,
      {KioskFilter? filter, int nextPosition = 0}) {
    final nameController = TextEditingController(text: filter?.name);
    final imageUrlController = TextEditingController();
    String? selectedColorHex = filter?.color;
    XFile? pickedImage;
    String? initialImageUrl = filter?.imageUrl;

    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(
                  filter == null ? "Créer un Filtre" : "Modifier le Filtre"),
              content: _KioskFilterDialogContent(
                nameController: nameController,
                imageUrlController: imageUrlController,
                initialColor: selectedColorHex,
                initialImageUrl: initialImageUrl,
                onColorSelected: (color) => selectedColorHex = color,
                onImagePicked: (image) => pickedImage = image,
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text("Annuler")),
                ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isNotEmpty) {
                        bool imageRemoved = pickedImage == null &&
                            imageUrlController.text.isEmpty &&
                            initialImageUrl != null;
                        String? urlToKeep =
                            imageRemoved ? null : initialImageUrl;

                        await repository.saveKioskFilter(
                          categoryId: categoryId,
                          filterId: filter?.id,
                          name: nameController.text,
                          position: filter?.position ?? nextPosition,
                          color: selectedColorHex,
                          imageFile: pickedImage,
                          existingImageUrl: urlToKeep,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text("Sauvegarder")),
              ],
            ));
  }
}

// --- DIALOGUE D'EDITION DE CATEGORIE (Avec Gestion Photo) ---

class CategoryEditorDialog extends StatefulWidget {
  final KioskCategory? category;
  final int? nextPosition;

  const CategoryEditorDialog({super.key, this.category, this.nextPosition});

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  XFile? _pickedImage;
  String? _existingImageUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _existingImageUrl = widget.category?.imageUrl;
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _pickedImage = image;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isUploading = true);
    try {
      int positionToSave;
      if (widget.category != null) {
        positionToSave = widget.category!.position;
      } else {
        positionToSave = widget.nextPosition ?? 999;
      }

      await FranchiseRepository().saveKioskCategory(
        id: widget.category?.id,
        name: _nameController.text.trim(),
        position: positionToSave,
        imageFile: _pickedImage,
        existingImageUrl: _existingImageUrl,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null
          ? "Nouvelle Catégorie"
          : "Modifier Catégorie"),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[400]!),
                      image: _pickedImage != null
                          ? DecorationImage(
                              image: kIsWeb
                                  ? NetworkImage(_pickedImage!.path)
                                  : FileImage(File(_pickedImage!.path))
                                      as ImageProvider,
                              fit: BoxFit.cover)
                          : (_existingImageUrl != null
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(
                                      _existingImageUrl!),
                                  fit: BoxFit.cover)
                              : null),
                    ),
                    child: (_pickedImage == null && _existingImageUrl == null)
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo,
                                  size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text("Ajouter photo",
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              if (_pickedImage != null || _existingImageUrl != null)
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.red),
                    label: const Text("Supprimer l'image",
                        style: TextStyle(color: Colors.red, fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        _pickedImage = null;
                        _existingImageUrl = null;
                      });
                    },
                  ),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: "Nom de la catégorie",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category)),
                validator: (v) => v == null || v.isEmpty ? "Requis" : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: _isUploading ? null : _save,
          child: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text("Enregistrer"),
        ),
      ],
    );
  }
}

// --- WIDGET INTERNE POUR LE DIALOGUE DE FILTRE ---

class _KioskFilterDialogContent extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController imageUrlController;
  final Function(String?) onColorSelected;
  final Function(XFile?) onImagePicked;
  final String? initialColor;
  final String? initialImageUrl;

  const _KioskFilterDialogContent({
    required this.nameController,
    required this.imageUrlController,
    required this.onColorSelected,
    required this.onImagePicked,
    this.initialColor,
    this.initialImageUrl,
  });

  @override
  State<_KioskFilterDialogContent> createState() =>
      _KioskFilterDialogContentState();
}

class _KioskFilterDialogContentState extends State<_KioskFilterDialogContent> {
  String? _selectedColor;
  XFile? _pickedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    widget.imageUrlController.text = widget.initialImageUrl ?? '';
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedImage = image;
        widget.imageUrlController.text = image.name;
      });
      widget.onImagePicked(_pickedImage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
              controller: widget.nameController,
              decoration: const InputDecoration(labelText: "Nom du filtre")),
          const SizedBox(height: 24),
          Text("Couleur", style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kColorPalette.map((hexColor) {
              final color = colorFromHex(hexColor);
              final isSelected = _selectedColor == hexColor;
              return InkWell(
                onTap: () {
                  setState(() => _selectedColor = isSelected ? null : hexColor);
                  widget.onColorSelected(_selectedColor);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isSelected ? Colors.blueAccent : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text("Image (Optionnel)",
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.imageUrlController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: "Image sélectionnée",
                    hintText: "Aucune",
                    suffixIcon: _pickedImage != null ||
                            (widget.initialImageUrl?.isNotEmpty ?? false)
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _pickedImage = null;
                                widget.imageUrlController.clear();
                                widget.onImagePicked(null);
                              });
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.upload_file),
                onPressed: _pickImage,
                tooltip: "Choisir une image",
              ),
            ],
          ),
          if (_pickedImage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: kIsWeb
                  ? Image.network(_pickedImage!.path,
                      height: 60, fit: BoxFit.cover)
                  : Image.file(File(_pickedImage!.path),
                      height: 60, fit: BoxFit.cover),
            )
          else if (widget.initialImageUrl != null &&
              widget.initialImageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: CachedNetworkImage(
                  imageUrl: widget.initialImageUrl!,
                  height: 60,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox()),
            )
        ],
      ),
    );
  }
}
