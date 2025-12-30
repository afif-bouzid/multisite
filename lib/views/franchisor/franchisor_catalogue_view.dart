import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';

enum ProductTypeFilter { all, sellable, ingredients }

enum SellableTypeFilter { all, simple, composite }

class CatalogueView extends StatefulWidget {
  const CatalogueView({super.key});

  @override
  State<CatalogueView> createState() => _CatalogueViewState();
}

class _CatalogueViewState extends State<CatalogueView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedFilterIds = {};
  ProductTypeFilter _productTypeFilter = ProductTypeFilter.all;
  SellableTypeFilter _sellableTypeFilter = SellableTypeFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
        () => setState(() => _searchQuery = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return Scaffold(
      body: Column(
        children: [
          _buildSearchAndFilterBar(context, repository, uid),
          Expanded(
            child: StreamBuilder<List<MasterProduct>>(
              stream: repository.getMasterProductsStream(uid,
                  filterIds: _selectedFilterIds.toList()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return Center(child: Text("Erreur: ${snapshot.error}"));
                if (!snapshot.hasData || snapshot.data!.isEmpty)
                  return const Center(child: Text("Aucun produit créé."));

                List<MasterProduct> products = snapshot.data!;
                if (_productTypeFilter == ProductTypeFilter.sellable) {
                  products = products.where((p) => !p.isIngredient).toList();
                  if (_sellableTypeFilter == SellableTypeFilter.simple) {
                    products = products.where((p) => !p.isComposite).toList();
                  } else if (_sellableTypeFilter ==
                      SellableTypeFilter.composite) {
                    products = products.where((p) => p.isComposite).toList();
                  }
                } else if (_productTypeFilter ==
                    ProductTypeFilter.ingredients) {
                  products = products.where((p) => p.isIngredient).toList();
                }

                if (_searchQuery.isNotEmpty) {
                  products = products
                      .where((p) => p.name
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                if (products.isEmpty)
                  return const Center(
                      child: Text(
                          "Aucun résultat pour les filtres sélectionnés."));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: products.length,
                  itemBuilder: (context, index) =>
                      _buildProductCard(context, products[index], repository),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text("Nouveau Produit"),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const ProductFormView()))),
    );
  }

  Widget _buildProductCard(BuildContext context, MasterProduct product,
      FranchiseRepository repository) {
    String subtitleText;
    IconData iconData;
    Color color;
    String typeLabel;

    if (product.isIngredient) {
      subtitleText = "Ingrédient / Non vendable";
      iconData = Icons.blender_outlined;
      color = Colors.grey.shade600;
      typeLabel = "Ingrédient";
    } else if (product.isComposite) {
      subtitleText = "Menu - ${product.sectionIds.length} section(s)";
      iconData = Icons.widgets_outlined;
      color = Theme.of(context).primaryColor;
      typeLabel = "Composite";
    } else {
      subtitleText = product.description ?? "Produit simple";
      iconData = Icons.fastfood_outlined;
      color = const Color(0xFF3F51B5); // Indigo
      typeLabel = "Simple";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    child: Icon(iconData, color: color),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                          child: Text(product.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(typeLabel),
                        labelStyle: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        backgroundColor: color.withOpacity(0.1),
                        padding: EdgeInsets.zero,
                        side: BorderSide.none,
                      )
                    ],
                  ),
                  subtitle: Text(subtitleText,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 20),
                          tooltip: "Dupliquer",
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ProductFormView(
                                      productToEdit: product,
                                      isDuplicating: true)))),
                      IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: "Modifier",
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ProductFormView(
                                      productToEdit: product)))),
                      IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          tooltip: "Supprimer",
                          onPressed: () =>
                              _deleteProduct(context, repository, product)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilterBar(
      BuildContext context, FranchiseRepository repository, String uid) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
              controller: _searchController,
              decoration: InputDecoration(
                  labelText: 'Rechercher un produit...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear())
                      : null)),
          const SizedBox(height: 16),
          SegmentedButton<ProductTypeFilter>(
            segments: const <ButtonSegment<ProductTypeFilter>>[
              ButtonSegment<ProductTypeFilter>(
                  value: ProductTypeFilter.all,
                  label: Text('Tous'),
                  icon: Icon(Icons.list)),
              ButtonSegment<ProductTypeFilter>(
                  value: ProductTypeFilter.sellable,
                  label: Text('Vendables'),
                  icon: Icon(Icons.point_of_sale)),
              ButtonSegment<ProductTypeFilter>(
                  value: ProductTypeFilter.ingredients,
                  label: Text('Ingrédients'),
                  icon: Icon(Icons.blender_outlined)),
            ],
            selected: <ProductTypeFilter>{_productTypeFilter},
            onSelectionChanged: (Set<ProductTypeFilter> newSelection) {
              setState(() {
                _productTypeFilter = newSelection.first;
                _sellableTypeFilter = SellableTypeFilter.all;
              });
            },
          ),
          if (_productTypeFilter == ProductTypeFilter.sellable)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.only(top: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Affiner les produits vendables :",
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                          label: const Text("Tous"),
                          selected:
                              _sellableTypeFilter == SellableTypeFilter.all,
                          onSelected: (selected) => setState(() =>
                              _sellableTypeFilter = SellableTypeFilter.all)),
                      ChoiceChip(
                          label: const Text("Simples"),
                          selected:
                              _sellableTypeFilter == SellableTypeFilter.simple,
                          onSelected: (selected) => setState(() =>
                              _sellableTypeFilter = SellableTypeFilter.simple)),
                      ChoiceChip(
                          label: const Text("Menus Composés"),
                          selected: _sellableTypeFilter ==
                              SellableTypeFilter.composite,
                          onSelected: (selected) => setState(() =>
                              _sellableTypeFilter =
                                  SellableTypeFilter.composite)),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
          StreamBuilder<List<ProductFilter>>(
            stream: repository.getFiltersStream(uid),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Wrap(
                spacing: 8,
                children: snapshot.data!
                    .map((filter) => FilterChip(
                        label: Text(filter.name),
                        selected: _selectedFilterIds.contains(filter.id),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedFilterIds.add(filter.id);
                            } else {
                              _selectedFilterIds.remove(filter.id);
                            }

                            // --- CORRECTION APPLIQUÉE ICI ---
                            // Réinitialise le filtre de type pour s'assurer que tous les produits
                            // sont potentiellement visibles lors du changement de filtre de rangement.
                            _productTypeFilter = ProductTypeFilter.all;
                          });
                        }))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _deleteProduct(BuildContext context, FranchiseRepository repository,
      MasterProduct product) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Confirmer la suppression"),
              content: Text(
                  "Supprimer '${product.name}' ? Cette action est irréversible et supprimera le produit pour tous les franchisés."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Annuler")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Supprimer"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white))
              ],
            ));
    if (confirm == true) {
      if (!mounted) return;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => const Dialog(
              child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Suppression...")
                  ]))));
      await repository.deleteMasterProduct(product);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

class ProductFormView extends StatefulWidget {
  final MasterProduct? productToEdit;
  final bool isDuplicating;

  const ProductFormView(
      {super.key, this.productToEdit, this.isDuplicating = false});

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<ProductFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isComposite = false;
  bool _isIngredient = false;
  List<ProductSection> _associatedSections = [];
  List<String> _selectedFilterIds = [];
  List<String> _selectedKioskFilterIds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.productToEdit != null) {
      _nameController.text =
          widget.productToEdit!.name + (widget.isDuplicating ? ' (Copie)' : '');
      _descriptionController.text = widget.productToEdit!.description ?? '';
      _isComposite = widget.productToEdit!.isComposite;
      _isIngredient = widget.productToEdit!.isIngredient;
      _selectedFilterIds = List.from(widget.productToEdit!.filterIds);
      _selectedKioskFilterIds = List.from(widget.productToEdit!.kioskFilterIds);
      if (_isComposite) _loadSectionsForProduct();
    }
  }

  Future<void> _loadSectionsForProduct() async {
    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final repository = FranchiseRepository();
    final sections = await repository.getSectionsForProduct(
        authProvider.firebaseUser!.uid, widget.productToEdit!.sectionIds);
    if (!mounted) return;
    setState(() {
      _associatedSections = sections;
      _isLoading = false;
    });
  }

  void _removeSection(int index) =>
      setState(() => _associatedSections.removeAt(index));

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final repository = FranchiseRepository();
      MasterProduct? productToUpdate;
      if (widget.productToEdit != null && !widget.isDuplicating)
        productToUpdate = widget.productToEdit;
      await repository.saveProduct(
        product: productToUpdate,
        name: _nameController.text,
        description: _descriptionController.text,
        isComposite: _isComposite,
        isIngredient: _isIngredient,
        filterIds: _selectedFilterIds,
        sectionIds: _associatedSections.map((s) => s.sectionId).toList(),
        kioskFilterIds: _isIngredient ? [] : _selectedKioskFilterIds,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addSectionsFromGroup() async {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final groups = await repository
        .getSectionGroupsStream(authProvider.firebaseUser!.uid)
        .first;

    if (!mounted) return;
    final selectedGroup = await showDialog<SectionGroup>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Choisir un groupe"),
              content: SizedBox(
                  width: 300,
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: groups.length,
                      itemBuilder: (context, index) => ListTile(
                          title: Text(groups[index].name),
                          onTap: () => Navigator.pop(context, groups[index])))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Annuler"))
              ],
            ));
    if (selectedGroup != null) {
      final sectionsFromGroup = await repository.getSectionsForProduct(
          authProvider.firebaseUser!.uid, selectedGroup.sectionIds);
      if (!mounted) return;
      setState(() {
        for (var section in sectionsFromGroup) {
          if (!_associatedSections.any((s) => s.sectionId == section.sectionId))
            _associatedSections.add(section);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.productToEdit != null && !widget.isDuplicating;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
          title: Text(isEditing ? "Modifier un Produit" : "Créer un Produit"),
          actions: [
            IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isLoading ? null : _saveProduct)
          ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text("Informations Principales",
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _nameController,
                      decoration:
                          const InputDecoration(labelText: "Nom du produit"),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _descriptionController,
                      decoration:
                          const InputDecoration(labelText: "Description")),
                  const SizedBox(height: 16),
                  SwitchListTile(
                      title: const Text("Produit composite ?"),
                      subtitle: const Text(
                          "Cochez si ce produit est un menu personnalisable."),
                      value: _isComposite,
                      onChanged: (val) => setState(() => _isComposite = val)),
                  SwitchListTile(
                    title: const Text("Produit interne / Ingrédient ?"),
                    subtitle: const Text(
                        "Cochez si ce produit ne doit pas être vendu seul (ex: une sauce, un steak...)."),
                    value: _isIngredient,
                    onChanged: (val) => setState(() => _isIngredient = val),
                  ),
                  const Divider(height: 40),
                  _buildBackOfficeFilterSelector(context, authProvider),
                  if (!_isIngredient) ...[
                    const Divider(height: 40),
                    _buildKioskFilterSelector(context, authProvider),
                  ],
                  if (_isComposite) ...[
                    const Divider(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Sections de Personnalisation",
                            style: Theme.of(context).textTheme.headlineSmall),
                        ElevatedButton.icon(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: _addSectionsFromGroup,
                            label: const Text("Ajouter un groupe"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white))
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_associatedSections.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(16.0),
                          child:
                              Center(child: Text("Aucune section associée.")))
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _associatedSections.length,
                        itemBuilder: (context, index) {
                          final section = _associatedSections[index];
                          return Card(
                            key: ValueKey(section.id),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(section.title),
                              subtitle: Text(
                                  "Type: ${section.type}, Min: ${section.selectionMin}, Max: ${section.selectionMax}"),
                              trailing: IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  tooltip: "Dissocier",
                                  onPressed: () => _removeSection(index)),
                            ),
                          );
                        },
                      ),
                  ]
                ],
              ),
            ),
    );
  }

  Widget _buildBackOfficeFilterSelector(
      BuildContext context, AuthProvider authProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Filtres de Rangement (Back-Office)",
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        StreamBuilder<List<ProductFilter>>(
          stream: FranchiseRepository()
              .getFiltersStream(authProvider.firebaseUser!.uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();

            return Wrap(
              spacing: 8,
              children: snapshot.data!.map((filter) {
                final isSelected = _selectedFilterIds.contains(filter.id);
                return FilterChip(
                    label: Text(filter.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected)
                          _selectedFilterIds.add(filter.id);
                        else
                          _selectedFilterIds.remove(filter.id);
                      });
                    });
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildKioskFilterSelector(
      BuildContext context, AuthProvider authProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Catégorisation Borne",
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        StreamBuilder<List<KioskCategory>>(
          stream: FranchiseRepository()
              .getKioskCategoriesStream(authProvider.firebaseUser!.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());

            if (!snapshot.hasData || snapshot.data!.isEmpty)
              return const Text(
                  "Veuillez d'abord créer la structure dans l'onglet 'Structure Borne'.");

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: snapshot.data!
                  .map((category) => Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category.name,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: category.filters.map((filter) {
                                final isSelected =
                                    _selectedKioskFilterIds.contains(filter.id);
                                return FilterChip(
                                  label: Text(filter.name),
                                  selected: isSelected,
                                  onSelected: (selected) => setState(() {
                                    if (selected)
                                      _selectedKioskFilterIds.add(filter.id);
                                    else
                                      _selectedKioskFilterIds.remove(filter.id);
                                  }),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class ProductPickerDialog extends StatefulWidget {
  final List<MasterProduct> initialSelection;

  const ProductPickerDialog({super.key, this.initialSelection = const []});

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  late List<MasterProduct> _selectedProducts;
  late Future<Map<String, dynamic>> _groupedProductsFuture;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedProducts = List.from(widget.initialSelection);
    _groupedProductsFuture = _loadAndGroupProducts();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadAndGroupProducts() async {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.firebaseUser!.uid;

    final results = await Future.wait([
      repository.getFiltersStream(uid).first,
      repository.getMasterProductsStream(uid).first,
    ]);
    final allFilters = results[0] as List<ProductFilter>;
    final allProducts = results[1] as List<MasterProduct>;

    final usableProducts = allProducts.where((p) => !p.isComposite).toList();
    final Map<String, List<MasterProduct>> grouped = {};
    final List<MasterProduct> ungrouped = [];
    for (final product in usableProducts) {
      if (product.filterIds.isEmpty) {
        ungrouped.add(product);
      } else {
        for (final filterId in product.filterIds) {
          grouped.putIfAbsent(filterId, () => []).add(product);
        }
      }
    }

    allFilters.sort((a, b) => a.name.compareTo(b.name));
    return {
      'filters': allFilters,
      'groupedProducts': grouped,
      'ungroupedProducts': ungrouped,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Sélectionner des produits"),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher un produit...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear())
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _groupedProductsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Center(
                        child: Text("Erreur de chargement des produits."));
                  }

                  final data = snapshot.data!;
                  final filters = data['filters'] as List<ProductFilter>;
                  final groupedProducts = data['groupedProducts']
                      as Map<String, List<MasterProduct>>;
                  final ungroupedProducts =
                      data['ungroupedProducts'] as List<MasterProduct>;
                  return ListView(
                    children: [
                      ...filters.map((filter) {
                        List<MasterProduct> products =
                            groupedProducts[filter.id] ?? [];
                        if (_searchQuery.isNotEmpty) {
                          products = products
                              .where((p) =>
                                  p.name.toLowerCase().contains(_searchQuery))
                              .toList();
                        }
                        if (products.isEmpty) return const SizedBox.shrink();

                        return _buildProductGroup(filter.name, products);
                      }).toList(),
                      _buildProductGroup(
                          "Produits non classés",
                          ungroupedProducts
                              .where((p) =>
                                  p.name.toLowerCase().contains(_searchQuery))
                              .toList()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _selectedProducts),
            child: const Text("Valider la Sélection")),
      ],
    );
  }

  Widget _buildProductGroup(String title, List<MasterProduct> products) {
    if (products.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text("$title (${products.length})",
          style: const TextStyle(fontWeight: FontWeight.bold)),
      initiallyExpanded: true,
      children: products.map((product) {
        final isSelected = _selectedProducts.any((p) => p.id == product.id);
        return CheckboxListTile(
          title: Text(product.name),
          value: isSelected,
          onChanged: (selected) {
            setState(() {
              if (selected!) {
                _selectedProducts.add(product);
              } else {
                _selectedProducts.removeWhere((p) => p.id == product.id);
              }
            });
          },
        );
      }).toList(),
    );
  }
}
