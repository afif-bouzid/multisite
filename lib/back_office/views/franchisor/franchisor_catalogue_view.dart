import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/auth_provider.dart';
import '../../../core/constants.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';

enum ProductTypeFilter { all, sellable, ingredients }
enum SellableTypeFilter { all, simple, composite }

class CatalogueView extends StatefulWidget {
  const CatalogueView({super.key});

  @override
  State<CatalogueView> createState() => _CatalogueViewState();
}

class _CatalogueViewState extends State<CatalogueView> {
  final _searchController = TextEditingController();

  List<MasterProduct> _allProducts = [];
  List<MasterProduct> _filteredProducts = [];
  Map<String, String> _sectionNames = {};

  List<ProductFilter> _cachedFilters = [];
  List<KioskCategory> _cachedKioskCategories = [];
  Map<String, String> _kioskFilterNames = {};

  final List<StreamSubscription> _subscriptions = [];

  String _searchQuery = '';
  final Set<String> _selectedFilterIds = {};
  ProductTypeFilter _productTypeFilter = ProductTypeFilter.all;
  SellableTypeFilter _sellableTypeFilter = SellableTypeFilter.all;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final repository = FranchiseRepository();
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    _subscriptions.add(repository.getMasterProductsStream(uid).listen((products) {
      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLoading = false;
          _applyFilters();
        });
      }
    }));

    _subscriptions.add(repository.getSectionsStream(uid).listen((sections) {
      final map = <String, String>{};
      for (var s in sections) {
        map[s.sectionId] = s.title;
      }
      if (mounted) setState(() => _sectionNames = map);
    }));

    _subscriptions.add(repository.getKioskCategoriesStream(uid).listen((categories) {
      final map = <String, String>{};
      for (var cat in categories) {
        for (var filter in cat.filters) {
          map[filter.id] = "${cat.name} > ${filter.name}";
        }
      }
      if (mounted) {
        setState(() {
          _cachedKioskCategories = categories;
          _kioskFilterNames = map;
        });
      }
    }));

    _subscriptions.add(repository.getFiltersStream(uid).listen((filters) {
      if (mounted) setState(() => _cachedFilters = filters);
    }));

    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() {
      _searchQuery = query;
      if (query.isNotEmpty) {
        _selectedFilterIds.clear();
        _productTypeFilter = ProductTypeFilter.all;
        _sellableTypeFilter = SellableTypeFilter.all;
      }
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<MasterProduct> temp = List.from(_allProducts);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      temp = temp.where((p) => p.name.toLowerCase().contains(q)).toList();
    } else {
      if (_productTypeFilter == ProductTypeFilter.sellable) {
        temp = temp.where((p) => !p.isIngredient).toList();
        if (_sellableTypeFilter == SellableTypeFilter.simple) {
          temp = temp.where((p) => !p.isComposite).toList();
        } else if (_sellableTypeFilter == SellableTypeFilter.composite) {
          temp = temp.where((p) => p.isComposite).toList();
        }
      } else if (_productTypeFilter == ProductTypeFilter.ingredients) {
        temp = temp.where((p) => p.isIngredient).toList();
      }

      if (_selectedFilterIds.isNotEmpty) {
        temp = temp.where((p) => p.filterIds.any((id) => _selectedFilterIds.contains(id))).toList();
      }
    }

    temp.sort((a, b) => a.name.compareTo(b.name));
    _filteredProducts = temp;
  }

  Set<String> _getRelevantFilterIds() {
    List<MasterProduct> preFiltered = List.from(_allProducts);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      preFiltered = preFiltered.where((p) => p.name.toLowerCase().contains(q)).toList();
    } else {
      if (_productTypeFilter == ProductTypeFilter.sellable) {
        preFiltered = preFiltered.where((p) => !p.isIngredient).toList();
        if (_sellableTypeFilter == SellableTypeFilter.simple) {
          preFiltered = preFiltered.where((p) => !p.isComposite).toList();
        } else if (_sellableTypeFilter == SellableTypeFilter.composite) {
          preFiltered = preFiltered.where((p) => p.isComposite).toList();
        }
      } else if (_productTypeFilter == ProductTypeFilter.ingredients) {
        preFiltered = preFiltered.where((p) => p.isIngredient).toList();
      }
    }

    final relevantIds = <String>{};
    for (var p in preFiltered) {
      relevantIds.addAll(p.filterIds);
    }
    return relevantIds;
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();

    return Scaffold(
      body: Column(
        children: [
          _buildSearchAndFilterBar(context),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("Aucun produit trouvé.", style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) =>
                  _buildProductCard(context, _filteredProducts[index], repository),
            ),
          ),
        ],
      ),
      floatingActionButton: SizedBox(
        height: 80,
        width: 80,
        child: FloatingActionButton(
            backgroundColor: Theme.of(context).primaryColor,
            child: const Icon(Icons.add, size: 40, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProductFormView()))),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, MasterProduct product, FranchiseRepository repository) {
    final bool isMenu = product.isComposite;
    final bool isIngredient = product.isIngredient;

    List<String> stepNames = [];
    for(var id in product.sectionIds) {
      if(_sectionNames.containsKey(id)) {
        stepNames.add(_sectionNames[id]!);
      }
    }

    String? kioskLabel;
    if (product.kioskFilterIds.isNotEmpty) {
      for (var id in product.kioskFilterIds) {
        if (_kioskFilterNames.containsKey(id)) {
          kioskLabel = _kioskFilterNames[id];
          break;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 160,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductFormView(productToEdit: product))),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                height: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: product.photoUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (_, __) => Container(color: Colors.grey[200]),
                        errorWidget: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                      )
                    else
                      Container(
                        color: product.color != null ? colorFromHex(product.color!) : Colors.grey[200],
                        child: Icon(isIngredient ? Icons.blender : (isMenu ? Icons.fastfood : Icons.restaurant), color: Colors.grey[600], size: 50),
                      ),
                    if (isMenu)
                      Positioned(
                        top: 8, left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                          child: const Text("MENU", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (kioskLabel != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple.shade200)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.touch_app, size: 12, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Flexible(child: Text(kioskLabel, style: TextStyle(fontSize: 11, color: Colors.purple.shade900, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        product.description != null && product.description!.isNotEmpty
                            ? product.description!
                            : (isIngredient ? "Ingrédient interne" : "Produit à la carte"),
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      if (stepNames.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${stepNames.length} étape(s) :", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                              Text(stepNames.join(", "), style: TextStyle(fontSize: 11, color: Colors.blue.shade900), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 70,
                decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade200))),
                child: Column(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(productToEdit: product, isDuplicating: true))),
                        child: Center(child: Icon(Icons.copy_all, size: 30, color: Colors.blueGrey.shade400)),
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade300),
                    Expanded(
                      child: InkWell(
                        onTap: () => _deleteProduct(context, repository, product),
                        child: Center(child: Icon(Icons.delete_outline, size: 30, color: Colors.red.shade400)),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- MODIFICATION ICI : Barre de recherche parallèle aux filtres ---
  Widget _buildSearchAndFilterBar(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // LIGNE 1 : Recherche (Expanded) + Filtres côte à côte
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50, // Hauteur ajustée pour matcher les boutons
                  child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 16),
                      textAlignVertical: TextAlignVertical.center, // Centrage vertical du texte
                      decoration: InputDecoration(
                          hintText: 'Rechercher...',
                          prefixIcon: const Icon(Icons.search, size: 24),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () => _searchController.clear())
                              : null)),
                ),
              ),
              const SizedBox(width: 12),
              // Filtre Vendables
              _buildBigFilterButton("Vendables", Icons.point_of_sale, _productTypeFilter == ProductTypeFilter.sellable, () {
                setState(() {
                  _searchController.clear();
                  if (_productTypeFilter == ProductTypeFilter.sellable) {
                    _productTypeFilter = ProductTypeFilter.all;
                  } else {
                    _productTypeFilter = ProductTypeFilter.sellable;
                  }
                  _sellableTypeFilter = SellableTypeFilter.all;
                  _selectedFilterIds.clear();
                  _applyFilters();
                });
              }),
              const SizedBox(width: 12),
              // Filtre Ingrédients
              _buildBigFilterButton("Ingrédients", Icons.blender_outlined, _productTypeFilter == ProductTypeFilter.ingredients, () {
                setState(() {
                  _searchController.clear();
                  if (_productTypeFilter == ProductTypeFilter.ingredients) {
                    _productTypeFilter = ProductTypeFilter.all;
                  } else {
                    _productTypeFilter = ProductTypeFilter.ingredients;
                  }
                  _selectedFilterIds.clear();
                  _applyFilters();
                });
              }),
            ],
          ),

          if (_productTypeFilter == ProductTypeFilter.sellable) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              // LIGNE 2 (Optionnelle) : Simple / Composés
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildChipChoice("Produits Simples", _sellableTypeFilter == SellableTypeFilter.simple, () {
                    setState(() {
                      _searchController.clear();
                      _selectedFilterIds.clear();
                      if (_sellableTypeFilter == SellableTypeFilter.simple) {
                        _sellableTypeFilter = SellableTypeFilter.all;
                      } else {
                        _sellableTypeFilter = SellableTypeFilter.simple;
                      }
                      _applyFilters();
                    });
                  }),
                  const SizedBox(width: 10),
                  _buildChipChoice("Menus / Composés", _sellableTypeFilter == SellableTypeFilter.composite, () {
                    setState(() {
                      _searchController.clear();
                      _selectedFilterIds.clear();
                      if (_sellableTypeFilter == SellableTypeFilter.composite) {
                        _sellableTypeFilter = SellableTypeFilter.all;
                      } else {
                        _sellableTypeFilter = SellableTypeFilter.composite;
                      }
                      _applyFilters();
                    });
                  }),
                ],
              ),
            ),
          ],

          const Divider(height: 24),
          // Filtres dynamiques (inchangé)
          SizedBox(
            width: double.infinity,
            child: Builder(
              builder: (context) {
                final relevantIds = _getRelevantFilterIds();
                final visibleFilters = _cachedFilters.where((f) => relevantIds.contains(f.id)).toList();

                if (visibleFilters.isEmpty) return const SizedBox.shrink();

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: visibleFilters.map((filter) {
                    final isSelected = _selectedFilterIds.contains(filter.id);
                    return FilterChip(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        label: Text(filter.name, style: TextStyle(fontSize: 16, color: isSelected ? Colors.white : Colors.black87)),
                        selected: isSelected,
                        selectedColor: Theme.of(context).primaryColor,
                        checkmarkColor: Colors.white,
                        onSelected: (selected) {
                          setState(() {
                            _searchController.clear();
                            if (selected) { _selectedFilterIds.add(filter.id); } else { _selectedFilterIds.remove(filter.id); }
                            _applyFilters();
                          });
                        });
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigFilterButton(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16), // Padding légèrement réduit pour gagner de la place
        decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected ? [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : null
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: isSelected ? Colors.white : Colors.black87),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)), // Police légèrement réduite
          ],
        ),
      ),
    );
  }

  Widget _buildChipChoice(String label, bool isSelected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 15, color: isSelected ? Colors.white : Colors.black)),
      selected: isSelected,
      onSelected: (_) => onTap(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      selectedColor: Colors.orange,
    );
  }

  void _deleteProduct(BuildContext context, FranchiseRepository repository, MasterProduct product) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirmer la suppression"),
          content: Text("Supprimer '${product.name}' ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler", style: TextStyle(fontSize: 18))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                child: const Text("Supprimer", style: TextStyle(fontSize: 18, color: Colors.white)))
          ],
        ));

    if (confirm == true) {
      await repository.deleteMasterProduct(product);
    }
  }
}

class ProductFormView extends StatefulWidget {
  final MasterProduct? productToEdit;
  final bool isDuplicating;

  const ProductFormView({super.key, this.productToEdit, this.isDuplicating = false});

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class ProductPickerDialog extends StatefulWidget {
  final List<MasterProduct> initialSelection;
  final bool ingredientsOnly;
  const ProductPickerDialog({super.key, this.initialSelection = const [], this.ingredientsOnly = false});
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
  void dispose() { _searchController.dispose(); super.dispose(); }
  Future<Map<String, dynamic>> _loadAndGroupProducts() async {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.firebaseUser!.uid;
    final results = await Future.wait([repository.getFiltersStream(uid).first, repository.getMasterProductsStream(uid).first]);
    final allFilters = results[0] as List<ProductFilter>;
    final allProducts = results[1] as List<MasterProduct>;
    List<MasterProduct> usableProducts;
    if (widget.ingredientsOnly) { usableProducts = allProducts.where((p) => p.isIngredient).toList(); }
    else { usableProducts = allProducts.where((p) => !p.isComposite).toList(); }
    final Map<String, List<MasterProduct>> grouped = {};
    final List<MasterProduct> ungrouped = [];
    for (final product in usableProducts) {
      if (product.filterIds.isEmpty) { ungrouped.add(product); }
      else { for (final filterId in product.filterIds) { grouped.putIfAbsent(filterId, () => []).add(product); } }
    }
    allFilters.sort((a, b) => a.name.compareTo(b.name));
    return { 'filters': allFilters, 'groupedProducts': grouped, 'ungroupedProducts': ungrouped };
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Sélectionner des produits"),
      content: SizedBox( width: 600, height: 500,
        child: Column( children: [
          TextField(controller: _searchController, decoration: InputDecoration(labelText: 'Rechercher...', prefixIcon: const Icon(Icons.search), suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null)),
          const SizedBox(height: 16),
          Expanded(child: FutureBuilder<Map<String, dynamic>>(
            future: _groupedProductsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final data = snapshot.data!;
              final filters = data['filters'] as List<ProductFilter>;
              final groupedProducts = data['groupedProducts'] as Map<String, List<MasterProduct>>;
              final ungroupedProducts = data['ungroupedProducts'] as List<MasterProduct>;
              return ListView(children: [
                ...filters.map((filter) {
                  List<MasterProduct> products = groupedProducts[filter.id] ?? [];
                  if (_searchQuery.isNotEmpty) products = products.where((p) => p.name.toLowerCase().contains(_searchQuery)).toList();
                  if (products.isEmpty) return const SizedBox.shrink();
                  return ExpansionTile(title: Text(filter.name), initiallyExpanded: true, children: products.map((p) => CheckboxListTile(title: Text(p.name), value: _selectedProducts.any((sp) => sp.id == p.id), onChanged: (val) { setState(() { if(val!) {
                    _selectedProducts.add(p);
                  } else {
                    _selectedProducts.removeWhere((x)=>x.id==p.id);
                  } }); })).toList());
                }),
                if(ungroupedProducts.isNotEmpty) ExpansionTile(title: const Text("Non classés"), initiallyExpanded: true, children: ungroupedProducts.where((p)=>p.name.toLowerCase().contains(_searchQuery)).map((p) => CheckboxListTile(title: Text(p.name), value: _selectedProducts.any((sp) => sp.id == p.id), onChanged: (val) { setState(() { if(val!) {
                  _selectedProducts.add(p);
                } else {
                  _selectedProducts.removeWhere((x)=>x.id==p.id);
                } }); })).toList())
              ]);
            },
          ),
          ),
        ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(fontSize: 18))),
        ElevatedButton(onPressed: () => Navigator.pop(context, _selectedProducts), style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)), child: const Text("Valider", style: TextStyle(fontSize: 18))),
      ],
    );
  }
}

class _ProductFormViewState extends State<ProductFormView> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _photoUrlController = TextEditingController();
  final _colorController = TextEditingController();

  String? _selectedColorHex;
  XFile? _pickedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isComposite = false;
  bool _isIngredient = false;
  List<ProductSection> _associatedSections = [];
  List<MasterProduct> _associatedIngredients = [];
  List<String> _selectedFilterIds = [];
  List<String> _selectedKioskFilterIds = [];
  List<ProductOption> _productOptions = [];
  bool _isLoading = false;

  bool _isLoadingSectionGroup = false;
  bool _isLoadingSingleSection = false;

  List<ProductSection>? _cachedAllSections;

  final Map<String, XFile?> _pendingOptionImages = {};
  late TabController _tabController;

  List<ProductFilter> _loadedFilters = [];
  List<KioskCategory> _loadedKioskCategories = [];
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    final repository = FranchiseRepository();

    _subscriptions.add(repository.getFiltersStream(uid).listen((data) {
      if(mounted) setState(() => _loadedFilters = data);
    }));

    _subscriptions.add(repository.getKioskCategoriesStream(uid).listen((data) {
      if(mounted) setState(() => _loadedKioskCategories = data);
    }));

    if (widget.productToEdit != null) {
      _nameController.text = widget.productToEdit!.name + (widget.isDuplicating ? ' (Copie)' : '');
      _descriptionController.text = widget.productToEdit!.description ?? '';
      _selectedColorHex = widget.productToEdit!.color;
      _photoUrlController.text = widget.productToEdit!.photoUrl ?? '';
      _isComposite = widget.productToEdit!.isComposite;
      _isIngredient = widget.productToEdit!.isIngredient;
      _selectedFilterIds = List.from(widget.productToEdit!.filterIds);
      _selectedKioskFilterIds = List.from(widget.productToEdit!.kioskFilterIds);
      _productOptions = List.from(widget.productToEdit!.options);

      if (_isComposite) _loadSectionsForProduct();
      if (widget.productToEdit!.ingredientProductIds.isNotEmpty) {
        _loadIngredientsForProduct();
      }
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _nameController.dispose();
    _descriptionController.dispose();
    _photoUrlController.dispose();
    _colorController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSectionsForProduct() async {
    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final repository = FranchiseRepository();
    final sections = await repository.getSectionsForProduct(authProvider.firebaseUser!.uid, widget.productToEdit!.sectionIds);
    if (!mounted) return;
    setState(() { _associatedSections = sections; _isLoading = false; });
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _performChunkedQuery(Query collectionQuery, String field, List<dynamic> ids) async {
    if (ids.isEmpty) return [];
    final List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
    for (var i = 0; i < ids.length; i += 30) {
      final sublist = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      futures.add(collectionQuery.where(field, whereIn: sublist).get() as Future<QuerySnapshot<Map<String, dynamic>>>);
    }
    final snapshots = await Future.wait(futures);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
    for (final snapshot in snapshots) {
      docs.addAll(snapshot.docs);
    }
    return docs;
  }

  Future<void> _loadIngredientsForProduct() async {
    setState(() => _isLoading = true);
    final baseQuery = FirebaseFirestore.instance.collection('master_products');
    final productDocs = await _performChunkedQuery(baseQuery, 'productId', widget.productToEdit!.ingredientProductIds);
    final productMap = { for (var doc in productDocs) doc.data()['productId']: MasterProduct.fromFirestore(doc.data(), doc.id) };
    if (!mounted) return;
    setState(() {
      _associatedIngredients = widget.productToEdit!.ingredientProductIds.map((id) => productMap[id]).whereType<MasterProduct>().toList();
      _isLoading = false;
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final int sizeInBytes = await image.length();
      if (sizeInBytes > 500 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("L'image est trop lourde (Max 500 Ko)."), backgroundColor: Colors.red));
        return;
      }
      setState(() { _pickedImage = image; _photoUrlController.text = image.name; });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final repository = FranchiseRepository();
      List<ProductOption> finalOptions = [];
      for (var opt in _productOptions) {
        String? imageUrl = opt.imageUrl;
        if (_pendingOptionImages.containsKey(opt.id) && _pendingOptionImages[opt.id] != null) {
          final path = 'product_options/${widget.productToEdit?.productId ?? const Uuid().v4()}/${opt.id}/${_pendingOptionImages[opt.id]!.name}';
          imageUrl = await repository.uploadImage(_pendingOptionImages[opt.id]!, path);
        }
        finalOptions.add(ProductOption(id: opt.id, name: opt.name, sectionIds: opt.sectionIds, imageUrl: imageUrl));
      }
      MasterProduct? productToUpdate;
      String? existingPhotoUrl;
      if (widget.productToEdit != null) {
        existingPhotoUrl = widget.productToEdit!.photoUrl;
        if (!widget.isDuplicating) productToUpdate = widget.productToEdit;
      }
      bool imageRemoved = _pickedImage == null && _photoUrlController.text.isEmpty && existingPhotoUrl != null;
      String? urlToKeep = imageRemoved ? null : existingPhotoUrl;

      await repository.saveProduct(
        product: productToUpdate,
        name: _nameController.text,
        description: _descriptionController.text,
        imageFile: _pickedImage,
        existingPhotoUrl: urlToKeep,
        color: _selectedColorHex,
        isComposite: _isComposite,
        isIngredient: _isIngredient,
        filterIds: _selectedFilterIds,
        sectionIds: _associatedSections.map((s) => s.sectionId).toList(),
        options: finalOptions,
        ingredientProductIds: _associatedIngredients.map((p) => p.productId).toList(),
        kioskFilterIds: _isIngredient ? [] : _selectedKioskFilterIds,
        photoUrl: '',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addSectionsFromGroup() async {
    setState(() => _isLoadingSectionGroup = true);
    try {
      final repository = FranchiseRepository();
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final groups = await repository.getSectionGroupsStream(authProvider.firebaseUser!.uid).first;

      if (!mounted) return;
      setState(() => _isLoadingSectionGroup = false);

      final selectedGroup = await showDialog<SectionGroup>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Choisir un groupe"),
            content: SizedBox(width: 400, height: 400,
                child: ListView.builder(itemCount: groups.length, itemBuilder: (context, index) => ListTile(contentPadding: const EdgeInsets.all(12), title: Text(groups[index].name, style: const TextStyle(fontSize: 18)), onTap: () => Navigator.pop(context, groups[index])))),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(fontSize: 18)))],
          ));

      if (selectedGroup != null) {
        setState(() => _isLoadingSectionGroup = true);
        final sectionsFromGroup = await repository.getSectionsForProduct(authProvider.firebaseUser!.uid, selectedGroup.sectionIds);
        if (!mounted) return;
        setState(() {
          for (var section in sectionsFromGroup) {
            if (!_associatedSections.any((s) => s.sectionId == section.sectionId)) {
              _associatedSections.add(section);
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingSectionGroup = false);
    }
  }

  Future<void> _addSingleSection() async {
    if (_cachedAllSections != null) {
      _showSingleSectionDialog(_cachedAllSections!);
      return;
    }

    setState(() => _isLoadingSingleSection = true);
    try {
      final repository = FranchiseRepository();
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _cachedAllSections = await repository.getSectionsStream(authProvider.firebaseUser!.uid).first;

      if (!mounted) return;
      setState(() => _isLoadingSingleSection = false);

      if (_cachedAllSections != null) {
        _showSingleSectionDialog(_cachedAllSections!);
      }
    } finally {
      if (mounted) setState(() => _isLoadingSingleSection = false);
    }
  }

  void _showSingleSectionDialog(List<ProductSection> allSections) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ajouter une Section"),
        content: SizedBox(
          width: 400, height: 500,
          child: ListView.builder(
            itemCount: allSections.length,
            itemBuilder: (context, i) {
              final s = allSections[i];
              final isAlreadyAdded = _associatedSections.any((as) => as.sectionId == s.sectionId);
              return ListTile(
                title: Text(s.title, style: TextStyle(fontWeight: FontWeight.bold, color: isAlreadyAdded ? Colors.grey : Colors.black)),
                subtitle: Text("${s.items.length} choix possibles"),
                trailing: isAlreadyAdded ? const Icon(Icons.check, color: Colors.green) : const Icon(Icons.add_circle_outline),
                enabled: !isAlreadyAdded,
                onTap: () {
                  setState(() {
                    _associatedSections.add(s);
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer", style: TextStyle(fontSize: 18)))
        ],
      ),
    );
  }

  void _manageOptions() {
    showDialog(
      context: context,
      builder: (context) => _ProductOptionsDialog(
        initialOptions: _productOptions,
        onConfirm: (newOptions, newImages) {
          setState(() {
            _productOptions = newOptions;
            _pendingOptionImages.addAll(newImages);
          });
        },
      ),
    );
  }

  void _showAddFilterDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouveau Filtre Back-Office"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Nom du filtre (ex: À tester)", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final name = controller.text.trim();
                final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

                final tempFilter = ProductFilter(id: const Uuid().v4(), name: name);
                setState(() {
                  _loadedFilters.add(tempFilter);
                  _selectedFilterIds.add(tempFilter.id);
                });

                Navigator.pop(ctx);
                await FranchiseRepository().addProductFilter(uid, name);
              }
            },
            child: const Text("Ajouter"),
          )
        ],
      ),
    );
  }

  void _showAddCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouvelle Catégorie Borne"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Nom (ex: Nos Burgers)", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final name = controller.text.trim();
                final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

                final tempCategory = KioskCategory(id: const Uuid().v4(), name: name, filters: [], position: 999);
                setState(() => _loadedKioskCategories.add(tempCategory));

                Navigator.pop(ctx);
                await FranchiseRepository().addKioskCategory(uid, name);
              }
            },
            child: const Text("Ajouter"),
          )
        ],
      ),
    );
  }

  void _showAddKioskFilterDialog(KioskCategory category) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Ajouter dans : ${category.name}"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Nom de la sous-catégorie (ex: Spicy)", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final name = controller.text.trim();
                final newFilter = KioskFilter(id: const Uuid().v4(), name: name, position: 99);

                setState(() {
                  final index = _loadedKioskCategories.indexWhere((c) => c.id == category.id);
                  if (index != -1) {
                    _loadedKioskCategories[index].filters.add(newFilter);
                    _selectedKioskFilterIds.add(newFilter.id);
                  }
                });

                Navigator.pop(ctx);
                await FranchiseRepository().saveKioskFilter(categoryId: category.id, name: name, position: 99);
              }
            },
            child: const Text("Ajouter"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          toolbarHeight: 80,
          title: Text(widget.productToEdit == null ? "Nouveau Produit" : "Modifier le produit", style: const TextStyle(fontSize: 24)),
          bottom: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(vertical: 12),
            labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(icon: Icon(Icons.info_outline, size: 30), text: "Général"),
              Tab(icon: Icon(Icons.layers, size: 30), text: "Composition"),
              Tab(icon: Icon(Icons.category, size: 30), text: "Classement"),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 24)),
                  icon: const Icon(Icons.save, size: 28),
                  label: const Text("ENREGISTRER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: _isLoading ? null : _saveProduct),
            )
          ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildGeneralTab(),
            _buildCompositionTab(),
            _buildClassificationTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Column(
              children: [
                _buildImagePreview(),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                        labelText: "Nom du produit",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        isDense: true
                    ),
                    validator: (v) => v!.isEmpty ? "Requis" : null),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                        labelText: "Description",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(16)
                    )),
                const SizedBox(height: 20),
                const Text("Couleur de fond", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: kColorPalette.map((hexColor) {
                    final color = colorFromHex(hexColor);
                    final isSelected = _selectedColorHex == hexColor;
                    return InkWell(
                      onTap: () => setState(() => _selectedColorHex = isSelected ? null : hexColor),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: isSelected ? Colors.black : Colors.grey.shade300,
                                width: isSelected ? 3 : 1
                            )
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                      color: _isIngredient ? Colors.orange.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _isIngredient ? Colors.orange.shade200 : Colors.grey.shade300)
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    dense: true,
                    title: const Text("Ingrédient non vendable ?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: const Text("Cocher si ce produit ne peut pas être vendu seul.", style: TextStyle(fontSize: 13)),
                    value: _isIngredient,
                    activeThumbColor: Colors.orange,
                    onChanged: (val) => setState(() => _isIngredient = val),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCompositionTab() {
    if (_isIngredient) {
      return const Center(child: Text("Un ingrédient n'a pas de composition complexe.", style: TextStyle(fontSize: 22)));
    }

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        SwitchListTile(
            contentPadding: const EdgeInsets.all(16),
            title: const Text("Produit Menu / Composite ?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            subtitle: const Text("Activez si ce produit contient des étapes de choix (ex: Menu Burger).", style: TextStyle(fontSize: 16)),
            value: _isComposite,
            onChanged: (val) => setState(() => _isComposite = val)),

        const Divider(height: 40),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Ingrédients de base", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 24),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
              label: const Text("Ajouter Ingrédient", style: TextStyle(fontSize: 16)),
              onPressed: () async {
                final selectedProducts = await showDialog<List<MasterProduct>>(
                    context: context,
                    builder: (context) => ProductPickerDialog(ingredientsOnly: true, initialSelection: _associatedIngredients));
                if (selectedProducts != null) setState(() => _associatedIngredients = selectedProducts);
              },
            )
          ],
        ),
        if (_associatedIngredients.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text("Aucun ingrédient associé.", style: TextStyle(color: Colors.grey, fontSize: 18)))
        else
          ..._associatedIngredients.map((ingredient) => Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const Icon(Icons.blender_outlined, size: 30),
              title: Text(ingredient.name, style: const TextStyle(fontSize: 18)),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 30), onPressed: () => setState(() => _associatedIngredients.remove(ingredient))),
            ),
          )),

        const Divider(height: 40),

        if (!_isComposite)
          const Padding(padding: EdgeInsets.all(16.0), child: Text("Activez 'Produit Menu / Composite' pour ajouter des étapes.", style: TextStyle(color: Colors.grey, fontSize: 18, fontStyle: FontStyle.italic)))
        else ...[
          ListTile(
            tileColor: Colors.blue[50],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            contentPadding: const EdgeInsets.all(20),
            title: const Text("Déclinaisons & Options", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 20)),
            subtitle: Text("${_productOptions.length} option(s) configurée(s)", style: const TextStyle(fontSize: 16)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 24),
            onTap: _manageOptions,
          ),

          const SizedBox(height: 30),

          if (_productOptions.isEmpty) ...[
            Row(
              children: [
                const Text("Sections Globales", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Spacer(),

                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: _isLoadingSingleSection
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.add),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), backgroundColor: Colors.orange),
                    onPressed: _isLoadingSingleSection ? null : _addSingleSection,
                    label: Text(_isLoadingSingleSection ? " Chargement..." : "Une Section", style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: _isLoadingSectionGroup
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.playlist_add),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                    onPressed: _isLoadingSectionGroup ? null : _addSectionsFromGroup,
                    label: Text(_isLoadingSectionGroup ? " Chargement..." : "Un Groupe", style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_associatedSections.isEmpty)
              const Text("Aucune section.", style: TextStyle(color: Colors.grey, fontSize: 18))
            else
              ..._associatedSections.asMap().entries.map((entry) => Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(entry.value.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  subtitle: Text("Choix Min: ${entry.value.selectionMin}, Max: ${entry.value.selectionMax}", style: const TextStyle(fontSize: 16)),
                  trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 30), onPressed: () => setState(() => _associatedSections.removeAt(entry.key))),
                ),
              )),
          ]
        ]
      ],
    );
  }

  Widget _buildClassificationTab() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            const Text("Filtres Back-Office", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            IconButton(
              onPressed: _showAddFilterDialog,
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
              tooltip: "Ajouter un nouveau filtre",
            )
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12, runSpacing: 12,
          children: _loadedFilters.map((filter) => FilterChip(
              padding: const EdgeInsets.all(12),
              label: Text(filter.name, style: const TextStyle(fontSize: 16)),
              selected: _selectedFilterIds.contains(filter.id),
              onSelected: (selected) => setState(() { selected ? _selectedFilterIds.add(filter.id) : _selectedFilterIds.remove(filter.id); })
          )).toList(),
        ),
        if (!_isIngredient) ...[
          const Divider(height: 48),
          Row(
            children: [
              const Text("Affichage sur la Borne", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _showAddCategoryDialog,
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                tooltip: "Ajouter une nouvelle catégorie",
              )
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _loadedKioskCategories.map((category) => Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(category.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                        onPressed: () => _showAddKioskFilterDialog(category),
                        tooltip: "Ajouter une sous-catégorie dans ${category.name}",
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12, runSpacing: 12,
                    children: category.filters.map((filter) => FilterChip(
                        padding: const EdgeInsets.all(12),
                        label: Text(filter.name, style: const TextStyle(fontSize: 16)),
                        selected: _selectedKioskFilterIds.contains(filter.id),
                        onSelected: (selected) => setState(() { selected ? _selectedKioskFilterIds.add(filter.id) : _selectedKioskFilterIds.remove(filter.id); })
                    )).toList(),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildImagePreview() {
    Widget? imageWidget;
    if (_pickedImage != null) {
      imageWidget = kIsWeb ? Image.network(_pickedImage!.path, fit: BoxFit.cover) : Image.file(File(_pickedImage!.path), fit: BoxFit.cover);
    } else if (_photoUrlController.text.isNotEmpty) {
      imageWidget = CachedNetworkImage(imageUrl: _photoUrlController.text, fit: BoxFit.cover, errorWidget: (_,__,___) => const Icon(Icons.broken_image, size: 50));
    }

    return GestureDetector(
      onTap: _pickImage,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[300]!)),
          child: imageWidget != null
              ? ClipRRect(borderRadius: BorderRadius.circular(20), child: imageWidget)
              : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 60, color: Colors.grey), SizedBox(height: 16), Text("Ajouter une image", style: TextStyle(color: Colors.grey, fontSize: 18))]),
        ),
      ),
    );
  }
}

class _ProductOptionsDialog extends StatefulWidget {
  final List<ProductOption> initialOptions;
  final Function(List<ProductOption>, Map<String, XFile?>) onConfirm;
  const _ProductOptionsDialog({required this.initialOptions, required this.onConfirm});
  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}
class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  late List<ProductOption> _options;
  final Map<String, XFile?> _newImages = {};
  final ImagePicker _picker = ImagePicker();
  @override
  void initState() { super.initState(); _options = List.from(widget.initialOptions); }

  void _addOption() {
    final nameController = TextEditingController();
    XFile? tempImage;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("Nouvelle Option"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      final int sizeInBytes = await image.length();
                      if (sizeInBytes > 500 * 1024) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image option trop lourde (Max 500Ko)"), backgroundColor: Colors.red));
                        return;
                      }
                      setStateDialog(() => tempImage = image);
                    }
                  },
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[400]!),
                        image: tempImage != null ? DecorationImage(image: kIsWeb ? NetworkImage(tempImage!.path) : FileImage(File(tempImage!.path)) as ImageProvider, fit: BoxFit.cover) : null),
                    child: tempImage == null ? const Icon(Icons.add_a_photo, color: Colors.grey, size: 40) : null,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nom (ex: Menu XL)", border: OutlineInputBorder())),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler", style: TextStyle(fontSize: 18))),
              ElevatedButton(onPressed: () {
                if (nameController.text.isNotEmpty) {
                  setState(() {
                    final newId = const Uuid().v4();
                    _options.add(ProductOption(id: newId, name: nameController.text, sectionIds: []));
                    if (tempImage != null) _newImages[newId] = tempImage;
                  });
                  Navigator.pop(ctx);
                }
              }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)), child: const Text("Créer", style: TextStyle(fontSize: 18)))
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickImageForOption(String optionId) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final int sizeInBytes = await image.length();
      if (sizeInBytes > 500 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image trop lourde (Max 500Ko)"), backgroundColor: Colors.red));
        return;
      }
      setState(() => _newImages[optionId] = image);
    }
  }

  void _configureSectionsForOption(int index) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final repository = FranchiseRepository();
    final allSections = await repository.getSectionsStream(authProvider.firebaseUser!.uid).first;
    final option = _options[index];
    final currentSectionIds = Set<String>.from(option.sectionIds);

    await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text("Sections pour : ${option.name}"),
            content: SizedBox(width: 500, height: 600,
              child: ListView.builder(
                itemCount: allSections.length,
                itemBuilder: (context, i) {
                  final s = allSections[i];
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    title: Text(s.title, style: const TextStyle(fontSize: 18)),
                    subtitle: Text("${s.items.length} produits"),
                    value: currentSectionIds.contains(s.sectionId),
                    onChanged: (val) => setStateDialog(() => val == true ? currentSectionIds.add(s.sectionId) : currentSectionIds.remove(s.sectionId)),
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer", style: TextStyle(fontSize: 18)))],
          );
        }));
    setState(() {
      _options[index] = ProductOption(id: option.id, name: option.name, sectionIds: currentSectionIds.toList(), imageUrl: option.imageUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Gérer les déclinaisons"),
      content: SizedBox(width: 700, height: 600,
        child: Column(children: [
          Expanded(child: ListView.builder(
            itemCount: _options.length,
            itemBuilder: (context, index) {
              final opt = _options[index];
              final hasNewImage = _newImages.containsKey(opt.id);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: GestureDetector(
                    onTap: () => _pickImageForOption(opt.id),
                    child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                      child: hasNewImage ? (kIsWeb ? Image.network(_newImages[opt.id]!.path, fit: BoxFit.cover) : Image.file(File(_newImages[opt.id]!.path), fit: BoxFit.cover))
                          : (opt.imageUrl != null ? Image.network(opt.imageUrl!, fit: BoxFit.cover) : const Icon(Icons.image, size: 30, color: Colors.grey)),
                    ),
                  ),
                  title: Text(opt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text("${opt.sectionIds.length} section(s) associée(s)", style: const TextStyle(fontSize: 16)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.settings_input_component, color: Colors.blue, size: 30), onPressed: () => _configureSectionsForOption(index)),
                    const SizedBox(width: 16),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 30), onPressed: () => setState(() => _options.removeAt(index))),
                  ],
                  ),
                ),
              );
            },
          ),
          ),
          ElevatedButton.icon(icon: const Icon(Icons.add, size: 28), label: const Text("Ajouter une option", style: TextStyle(fontSize: 18)), style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)), onPressed: _addOption)
        ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(fontSize: 18))),
        ElevatedButton(onPressed: () { widget.onConfirm(_options, _newImages); Navigator.pop(context); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)), child: const Text("Valider", style: TextStyle(fontSize: 18))),
      ],
    );
  }
}