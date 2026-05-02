import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '../../../core/constants.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
// Import du widget ImageInputCard (ajustez le chemin si nécessaire)
import 'image_input_card.dart';

const List<String> _kLocalPalette = [
  '#F44336',
  '#E91E63',
  '#9C27B0',
  '#673AB7',
  '#2196F3',
  '#03A9F4',
  '#00BCD4',
  '#009688',
  '#4CAF50',
  '#8BC34A',
  '#CDDC39',
  '#FFC107',
  '#FF9800',
  '#FF5722',
  '#795548',
  '#9E9E9E',
  '#607D8B',
  '#000000'
];

class KioskView extends StatefulWidget {
  const KioskView({super.key});

  @override
  State<KioskView> createState() => _KioskViewState();
}

class _KioskViewState extends State<KioskView> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Stream<List<KioskCategory>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    _categoriesStream = FranchiseRepository().getKioskCategoriesStream(uid);
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<KioskCategory>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text("Erreur", style: TextStyle(color: Colors.red)));
          }

          final categories = List<KioskCategory>.from(snapshot.data ?? []);

          if (categories.isEmpty) {
            return _buildEmptyState(context, uid);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderInfo(context),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: categories.length,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) => Material(
                    elevation: 10,
                    color: Colors.white,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    child: child,
                  ),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = categories.removeAt(oldIndex);
                      categories.insert(newIndex, item);
                    });
                    repository.updateKioskCategoriesOrder(categories);
                  },
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return CategoryCard(
                      key: ValueKey(category.id),
                      category: category,
                      index: index,
                      repository: repository,
                      franchisorId: uid,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text("Nouvelle Catégorie",
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => CategoryEditorDialog(franchisorId: uid),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String uid) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 24),
          Text(
            "Votre borne est vide",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          const Text(
            "Créez des catégories pour organiser votre menu.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CategoryEditorDialog(franchisorId: uid),
            ),
            icon: const Icon(Icons.add),
            label: const Text("Créer une catégorie"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHeaderInfo(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 4),
            blurRadius: 10)
      ]),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Menu Borne Client",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(
            "Glissez les éléments avec la poignée grise pour organiser l'ordre.",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class CategoryCard extends StatefulWidget {
  final KioskCategory category;
  final int index;
  final FranchiseRepository repository;
  final String franchisorId;

  const CategoryCard({
    super.key,
    required this.category,
    required this.index,
    required this.repository,
    required this.franchisorId,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  late Stream<List<KioskFilter>> _filtersStream;

  @override
  void initState() {
    super.initState();
    _filtersStream = FirebaseFirestore.instance
        .collection('kiosk_categories')
        .doc(widget.category.id)
        .collection('filters')
        .orderBy('position')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => KioskFilter.fromFirestore(doc))
            .toList());
  }

  void _confirmDeleteCategory(BuildContext context) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Supprimer la catégorie ?"),
              content: Text(
                  "Supprimer '${widget.category.name}' ?\nL'image sera également effacée."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Annuler")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    child: const Text("Supprimer"))
              ],
            ));
    if (confirm == true) {
      await widget.repository.deleteKioskCategory(widget.category.id);
    }
  }

  void _showFilterDialog(BuildContext context, {KioskFilter? filter}) {
    showDialog(
      context: context,
      builder: (_) => FilterEditorDialog(
        categoryId: widget.category.id,
        filter: filter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KioskFilter>>(
      stream: _filtersStream,
      builder: (context, snapshot) {
        final filters = snapshot.data ?? [];
        final bool canDelete = filters.isEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  offset: const Offset(0, 4),
                  blurRadius: 12)
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              childrenPadding: const EdgeInsets.only(bottom: 16),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                  image: (widget.category.imageUrl != null &&
                          widget.category.imageUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(
                              widget.category.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (widget.category.imageUrl == null ||
                        widget.category.imageUrl!.isEmpty)
                    ? Icon(Icons.folder_zip_outlined,
                        color: Colors.blueGrey.shade200, size: 28)
                    : null,
              ),
              title: Text(
                widget.category.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87),
              ),
              subtitle: Text(
                canDelete
                    ? "Dossier vide"
                    : "${filters.length} sous-catégorie(s)",
                style: TextStyle(
                    color: canDelete
                        ? Colors.orange.shade300
                        : Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.edit_outlined, color: Colors.black54),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => CategoryEditorDialog(
                          category: widget.category,
                          franchisorId: widget.franchisorId),
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.red.shade400),
                      onPressed: () => _confirmDeleteCategory(context),
                    )
                  else
                    Tooltip(
                      message: "Videz le dossier pour le supprimer",
                      triggerMode: TooltipTriggerMode.tap,
                      child: IconButton(
                        icon: Icon(Icons.delete_forever,
                            color: Colors.grey.shade200),
                        onPressed: null,
                      ),
                    ),
                  const SizedBox(width: 8),
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300)),
                      child: const Icon(Icons.drag_handle_rounded,
                          color: Colors.black87, size: 24),
                    ),
                  ),
                ],
              ),
              children: [
                const Divider(height: 1),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Sous-catégories",
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.blue),
                        onPressed: () => _showFilterDialog(context),
                        tooltip: "Ajouter une sous-catégorie",
                      )
                    ],
                  ),
                ),
                if (filters.isEmpty)
                  _buildEmptyFilterState()
                else
                  _buildFilterList(filters),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyFilterState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          Text("Ce dossier est vide.",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFilterList(List<KioskFilter> filters) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filters.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        shadowColor: Colors.black26,
        child: child,
      ),
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final item = filters.removeAt(oldIndex);
        filters.insert(newIndex, item);
        widget.repository.updateKioskFiltersOrder(widget.category.id, filters);
      },
      itemBuilder: (context, index) {
        final filter = filters[index];
        return _buildFilterRow(filter, index);
      },
    );
  }

  Widget _buildFilterRow(KioskFilter filter, int index) {
    Color seedColor;
    if (filter.color != null && filter.color!.isNotEmpty) {
      try {
        seedColor = colorFromHex(filter.color!);
      } catch (_) {
        seedColor = Colors.blue;
      }
    } else {
      seedColor = Colors.blue;
    }

    return Container(
      key: ValueKey(filter.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: seedColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: seedColor.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: seedColor.withValues(alpha: 0.3)),
            image: (filter.imageUrl != null && filter.imageUrl!.isNotEmpty)
                ? DecorationImage(
                    image: CachedNetworkImageProvider(filter.imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: (filter.imageUrl == null || filter.imageUrl!.isEmpty)
              ? Icon(Icons.label, color: seedColor, size: 20)
              : null,
        ),
        title: Text(filter.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20, color: Colors.black54),
              onPressed: () => _showFilterDialog(context, filter: filter),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                          title: const Text("Supprimer ?"),
                          content: Text(
                              "Supprimer la sous-catégorie '${filter.name}' ?\nL'image sera supprimée."),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Annuler")),
                            ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white),
                                child: const Text("Supprimer"))
                          ],
                        ));
                if (confirm == true) {
                  await widget.repository.deleteKioskFilter(
                      categoryId: widget.category.id, filterId: filter.id);
                }
              },
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(Icons.drag_indicator, size: 20, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- BOÎTE DE DIALOGUE CATÉGORIE ---

class CategoryEditorDialog extends StatefulWidget {
  final KioskCategory? category;
  final String franchisorId;

  const CategoryEditorDialog(
      {super.key, this.category, required this.franchisorId});

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  // Image Management
  XFile? _imageFile;
  String? _displayUrl;
  String? _originalUrl;

  @override
  void initState() {
    super.initState();
    if (widget.category != null) {
      _nameController.text = widget.category!.name;
      _displayUrl = widget.category!.imageUrl;
      _originalUrl = widget.category!.imageUrl;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = FranchiseRepository();

      // LOGIQUE POUR L'URL FINALE
      String finalUrlParam = "";
      if (_imageFile == null &&
          (_displayUrl != null && _displayUrl!.isNotEmpty)) {
        finalUrlParam = _displayUrl!;
      }

      await repo.saveKioskCategory(
        id: widget.category?.id,
        name: _nameController.text.trim(),
        position: widget.category?.position ?? 999,
        // Paramètres Image
        imageFile: _imageFile,
        existingImageUrl: _originalUrl,
        imageUrl: finalUrlParam,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null
          ? "Nouvelle Catégorie"
          : "Modifier Catégorie"),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ImageInputCard(
              label: "Image",
              imageFile: _imageFile,
              imageUrl: _displayUrl,
              size: 120,
              onPick: () async {
                final img =
                    await ImagePicker().pickImage(source: ImageSource.gallery);
                if (img != null) {
                  setState(() {
                    _imageFile = img;
                    _displayUrl = "";
                  });
                }
              },
              onRemove: () {
                setState(() {
                  _imageFile = null;
                  _displayUrl = "";
                });
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: "Nom de la catégorie",
                  border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? "Requis" : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Enregistrer"),
        )
      ],
    );
  }
}

// --- BOÎTE DE DIALOGUE FILTRE (SOUS-CATÉGORIE) ---

class FilterEditorDialog extends StatefulWidget {
  final String categoryId;
  final KioskFilter? filter;

  const FilterEditorDialog({super.key, required this.categoryId, this.filter});

  @override
  State<FilterEditorDialog> createState() => _FilterEditorDialogState();
}

class _FilterEditorDialogState extends State<FilterEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedColor;
  bool _isLoading = false;

  // Image Management
  XFile? _imageFile;
  String? _displayUrl;
  String? _originalUrl;

  @override
  void initState() {
    super.initState();
    if (widget.filter != null) {
      _nameController.text = widget.filter!.name;
      _selectedColor = widget.filter!.color;
      _displayUrl = widget.filter!.imageUrl;
      _originalUrl = widget.filter!.imageUrl;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = FranchiseRepository();

      // LOGIQUE POUR L'URL FINALE
      String finalUrlParam = "";
      if (_imageFile == null &&
          (_displayUrl != null && _displayUrl!.isNotEmpty)) {
        finalUrlParam = _displayUrl!;
      }

      await repo.saveKioskFilter(
        categoryId: widget.categoryId,
        filterId: widget.filter?.id,
        name: _nameController.text.trim(),
        position: widget.filter?.position ?? 999,
        color: _selectedColor,
        // Paramètres Image
        imageFile: _imageFile,
        existingImageUrl: _originalUrl,
        imageUrl: finalUrlParam,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.filter == null
          ? "Nouvelle Sous-Catégorie"
          : "Modifier Sous-Catégorie"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ImageInputCard(
                  label: "Icône",
                  imageFile: _imageFile,
                  imageUrl: _displayUrl,
                  size: 100,
                  onPick: () async {
                    final img = await ImagePicker()
                        .pickImage(source: ImageSource.gallery);
                    if (img != null) {
                      setState(() {
                        _imageFile = img;
                        _displayUrl = "";
                      });
                    }
                  },
                  onRemove: () {
                    setState(() {
                      _imageFile = null;
                      _displayUrl = "";
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: "Nom", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "Requis" : null,
              ),
              const SizedBox(height: 20),
              const Text("Couleur d'accentuation",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kLocalPalette.map((hex) {
                  final color = colorFromHex(hex);
                  final isSelected = _selectedColor == hex;
                  return InkWell(
                    onTap: () => setState(
                        () => _selectedColor = isSelected ? null : hex),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                isSelected ? Colors.black : Colors.transparent,
                            width: 2),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              )
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Enregistrer"),
        )
      ],
    );
  }
}
