import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/auth_provider.dart';
import '../../../core/constants.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
// Assurez-vous que ce fichier existe bien, sinon commentez l'import
import 'image_input_card.dart';

enum ProductTypeFilter { sellable, ingredients }
enum SellableTypeFilter { all, simple, composite }

class CatalogueView extends StatefulWidget {
  const CatalogueView({super.key});
  @override
  State<CatalogueView> createState() => _CatalogueViewState();
}

class _CatalogueViewState extends State<CatalogueView> {
  final _searchController = TextEditingController();
  List<MasterProduct> _allProducts = [];
  List<ProductSection> _cachedSectionsList = [];
  Map<String, String> _sectionNames = {};
  List<ProductFilter> _cachedFilters = [];
  List<KioskCategory> _cachedKioskCategories = [];
  Map<String, String> _kioskFilterNames = {};
  Map<String, String> _filterToCategoryMap = {};
  String _searchQuery = '';
  ProductTypeFilter _productTypeFilter = ProductTypeFilter.sellable;
  SellableTypeFilter _sellableTypeFilter = SellableTypeFilter.all;
  bool _showContainersOnly = false;
  String? _selectedKioskCategoryId;
  String? _selectedSubFilterId;
  String? _selectedBackOfficeFilterId;
  bool _isLoading = true;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    final repo = FranchiseRepository();
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    // Chargement Produits
    _subscriptions.add(repo.getMasterProductsStream(uid).listen((products) {
      if (mounted) {
        // Tri par position si existant
        products.sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    }));

    // Chargement Sections
    _subscriptions.add(repo.getSectionsStream(uid).listen((sections) {
      final map = <String, String>{};
      for (var s in sections) {
        map[s.sectionId] = s.title;
      }
      if (mounted) {
        setState(() {
          _cachedSectionsList = sections;
          _sectionNames = map;
        });
      }
    }));

    // Chargement Catégories Borne
    _subscriptions.add(repo.getKioskCategoriesStream(uid).listen((cats) {
      final filterMap = <String, String>{};
      final catMap = <String, String>{};
      for (var cat in cats) {
        for (var f in cat.filters) {
          filterMap[f.id] = "${cat.name} > ${f.name}";
          catMap[f.id] = cat.id;
        }
      }
      if (mounted) {
        setState(() {
          _cachedKioskCategories = cats;
          _kioskFilterNames = filterMap;
          _filterToCategoryMap = catMap;
        });
      }
    }));

    // Chargement Filtres BO
    _subscriptions.add(repo.getFiltersStream(uid).listen((filters) {
      if (mounted) setState(() => _cachedFilters = filters);
    }));

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (var sub in _subscriptions) sub.cancel();
    super.dispose();
  }

  List<MasterProduct> _getFilteredProducts() {
    return _allProducts.where((product) {
      // Filtre Recherche
      if (_searchQuery.isNotEmpty) {
        if (!product.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      // Filtre Type (Ingrédient vs Vendable)
      if (!_matchesProductType(product)) return false;

      // Filtre Sous-type Vendable (Simple vs Composé)
      if (_productTypeFilter == ProductTypeFilter.sellable) {
        if (!_matchesSellableType(product)) return false;
      }

      // Filtre Conteneur uniquement
      if (_showContainersOnly && !product.isContainer) return false;

      // Filtre Étiquette BackOffice
      if (_selectedBackOfficeFilterId != null) {
        if (!product.filterIds.contains(_selectedBackOfficeFilterId)) return false;
      }

      // Filtre Catégorie Borne
      if (_selectedKioskCategoryId != null) {
        if (!_matchesKioskCategory(product)) return false;
      }
      return true;
    }).toList();
  }

  bool _matchesProductType(MasterProduct product) {
    switch (_productTypeFilter) {
      case ProductTypeFilter.sellable:
        return !product.isIngredient;
      case ProductTypeFilter.ingredients:
        return product.isIngredient;
    }
  }

  bool _matchesSellableType(MasterProduct product) {
    switch (_sellableTypeFilter) {
      case SellableTypeFilter.all:
        return true;
      case SellableTypeFilter.simple:
        return !product.isComposite; // isComposite est souvent true pour les menus
      case SellableTypeFilter.composite:
        return product.isComposite;
    }
  }

  bool _matchesKioskCategory(MasterProduct product) {
    bool belongsToCategory = product.kioskFilterIds.any((fId) =>
    _filterToCategoryMap[fId] == _selectedKioskCategoryId
    );
    if (!belongsToCategory) return false;
    if (_selectedSubFilterId != null) {
      return product.kioskFilterIds.contains(_selectedSubFilterId);
    }
    return true;
  }

  void _onReorder(int oldIndex, int newIndex, List<MasterProduct> currentList) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = currentList.removeAt(oldIndex);
      currentList.insert(newIndex, item);
    });
    // Sauvegarde de l'ordre via repository
    await FranchiseRepository().updateMasterProductsOrder(currentList);
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _getFilteredProducts();
    final repository = FranchiseRepository();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      body: Column(
        children: [
          _buildTopHeader(),
          _buildCategoryTabs(),
          if (_selectedKioskCategoryId != null) _buildSubCategoryBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                ? _buildEmptyState()
                : _buildProductList(filteredList, repository),
          ),
        ],
      ),
      floatingActionButton: SizedBox(
        height: 70, width: 70,
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF2D3436),
          elevation: 6,
          child: const Icon(Icons.add, size: 32, color: Colors.white),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProductFormView(
                preselectedFilterId: _selectedSubFilterId,
                preloadedSections: _cachedSectionsList,
                allProducts: _allProducts,
              ))
          ),
        ),
      ),
    );
  }

  // --- WIDGETS D'INTERFACE PRINCIPALE ---

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), offset: const Offset(0, 4), blurRadius: 10)]
      ),
      child: Column(
        children: [
          // Barre de recherche et filtre Étiquette
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: TextField(
                    controller: _searchController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Rechercher...',
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                      suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchController.clear()) : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: Container(
                  height: 45,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text("Étiquette", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.black87)),
                      value: _selectedBackOfficeFilterId,
                      icon: const Icon(Icons.label_outline, size: 20, color: Colors.grey),
                      items: [
                        const DropdownMenuItem(value: null, child: Text("Toutes", style: TextStyle(fontWeight: FontWeight.bold))),
                        ..._cachedFilters.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: (val) => setState(() => _selectedBackOfficeFilterId = val),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Boutons Vendables / Ingrédients
          Row(
            children: [
              Expanded(child: _buildBigFilterBtn("Vendables", Icons.storefront, ProductTypeFilter.sellable)),
              const SizedBox(width: 12),
              Expanded(child: _buildBigFilterBtn("Ingrédients", Icons.kitchen, ProductTypeFilter.ingredients)),
            ],
          ),

          // Sous-filtres Vendables
          if (_productTypeFilter == ProductTypeFilter.sellable) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildToggleChip("Produits Simples", SellableTypeFilter.simple),
                  const SizedBox(width: 10),
                  // _buildToggleChip("Menus & Composés", SellableTypeFilter.composite),
                  // const SizedBox(width: 10),
                  Container(height: 20, width: 1, color: Colors.grey[300]),
                  const SizedBox(width: 10),
                  FilterChip(
                    label: const Text("Conteneurs (Frites...)"),
                    selected: _showContainersOnly,
                    onSelected: (val) {
                      setState(() {
                        _showContainersOnly = val;
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: Colors.orange.shade100,
                    checkmarkColor: Colors.orange.shade800,
                    labelStyle: TextStyle(
                        color: _showContainersOnly ? Colors.orange.shade900 : Colors.grey[700],
                        fontWeight: _showContainersOnly ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13
                    ),
                    shape: StadiumBorder(side: BorderSide(color: _showContainersOnly ? Colors.orange.shade200 : Colors.grey.shade300)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBigFilterBtn(String label, IconData icon, ProductTypeFilter type) {
    final isSelected = _productTypeFilter == type;
    return InkWell(
      onTap: () {
        setState(() {
          _searchController.clear();
          _productTypeFilter = type;
          _selectedKioskCategoryId = null;
          _selectedSubFilterId = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 45,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D3436) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.shade300),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3))] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey[700], size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleChip(String label, SellableTypeFilter type) {
    final isSelected = _sellableTypeFilter == type;
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _sellableTypeFilter = SellableTypeFilter.all;
          } else {
            _sellableTypeFilter = type;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.blue[800] : Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    if (_productTypeFilter != ProductTypeFilter.sellable) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      height: 50,
      margin: const EdgeInsets.only(top: 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildTabItem("Vue d'ensemble", null),
          ..._cachedKioskCategories.map((cat) => _buildTabItem(cat.name, cat.id)),
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, String? catId) {
    final isSelected = _selectedKioskCategoryId == catId;
    return InkWell(
      onTap: () => setState(() {
        _selectedKioskCategoryId = catId;
        _selectedSubFilterId = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: isSelected ? const Border(bottom: BorderSide(color: Color(0xFF2D3436), width: 3)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF2D3436) : Colors.grey[500],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSubCategoryBar() {
    final category = _cachedKioskCategories.firstWhere((c) => c.id == _selectedKioskCategoryId, orElse: () => KioskCategory(id: '', name: '', filters: [], position: 0));
    if (category.filters.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.grey[50],
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSubFilterChip("Tout", null),
          ...category.filters.map((f) => _buildSubFilterChip(f.name, f.id)),
        ],
      ),
    );
  }

  Widget _buildSubFilterChip(String label, String? filterId) {
    final isSelected = _selectedSubFilterId == filterId;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedSubFilterId = filterId),
        backgroundColor: Colors.white,
        selectedColor: Colors.black87,
        checkmarkColor: Colors.white,
        shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildProductList(List<MasterProduct> list, FranchiseRepository repo) {
    if (_selectedKioskCategoryId == null) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
        itemCount: list.length,
        itemBuilder: (ctx, i) => _buildProductCard(list[i], repo, enableDrag: false),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
      buildDefaultDragHandles: false,
      itemCount: list.length,
      onReorder: (oldIdx, newIdx) => _onReorder(oldIdx, newIdx, list),
      itemBuilder: (ctx, i) {
        final product = list[i];
        return Column(
          key: ValueKey(product.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedSubFilterId == null)
              _buildSubCategoryHeaderIfNeeded(product, i, list),
            _buildProductCard(product, repo, enableDrag: true, key: ValueKey(product.id)),
          ],
        );
      },
    );
  }

  Widget _buildSubCategoryHeaderIfNeeded(MasterProduct current, int index, List<MasterProduct> list) {
    if (_selectedKioskCategoryId == null) return const SizedBox.shrink();
    String currentSubCatName = "Autres / Non classés";
    String currentSubCatId = "others";

    for (var id in current.kioskFilterIds) {
      if (_filterToCategoryMap[id] == _selectedKioskCategoryId) {
        currentSubCatName = _kioskFilterNames[id]?.split('>').last.trim() ?? "Autres";
        currentSubCatId = id;
        break;
      }
    }

    String? prevSubCatId;
    if (index > 0) {
      final prev = list[index - 1];
      for (var id in prev.kioskFilterIds) {
        if (_filterToCategoryMap[id] == _selectedKioskCategoryId) {
          prevSubCatId = id;
          break;
        }
      }
      prevSubCatId ??= "others";
    }

    if (currentSubCatId != prevSubCatId) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.blueGrey[50], borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.blueGrey[400]),
            ),
            const SizedBox(width: 12),
            Text(
                currentSubCatName.toUpperCase(),
                style: TextStyle(color: Colors.blueGrey[800], fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: Colors.blueGrey[100], thickness: 1)),
            if (currentSubCatId != "others")
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(preselectedFilterId: currentSubCatId, preloadedSections: _cachedSectionsList, allProducts: _allProducts))),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle, size: 16, color: Colors.green[600]),
                      const SizedBox(width: 4),
                      Text("Ajouter", style: TextStyle(fontSize: 12, color: Colors.green[800], fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildProductCard(MasterProduct product, FranchiseRepository repo, {required bool enableDrag, Key? key}) {
    final bool isIngredient = product.isIngredient;
    final bool isContainer = product.isContainer;
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
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 5))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(productToEdit: product, preloadedSections: _cachedSectionsList, allProducts: _allProducts))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: "product_${product.id}",
                  child: Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      image: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                          ? DecorationImage(image: CachedNetworkImageProvider(product.photoUrl!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: Stack(
                      children: [
                        if (product.photoUrl == null || product.photoUrl!.isEmpty)
                          Center(child: Icon(isIngredient ? Icons.blender : (isContainer ? Icons.folder_copy_rounded : Icons.restaurant), color: Colors.grey[300], size: 36)),
                        if (isContainer)
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(15))
                              ),
                              child: const Text("CONTENEUR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                            ),
                          )
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              color: Color(0xFF2D3436)
                          )
                      ),
                      const SizedBox(height: 8),
                      if (kioskLabel != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              kioskLabel,
                              style: TextStyle(fontSize: 12, color: Colors.purple.shade800, fontWeight: FontWeight.bold)
                          ),
                        ),

                      if (product.isContainer)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.list_alt_rounded, size: 16, color: Colors.black54),
                                  const SizedBox(width: 8),
                                  Text(
                                      "${product.containerProductIds.length} produit(s) lié(s)",
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87
                                      )
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else if (product.sectionIds.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.layers_rounded, size: 16, color: Colors.blueGrey),
                                  SizedBox(width: 8),
                                  Text(
                                    "Configuration du produit :",
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.blueGrey
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Divider(height: 1, color: Colors.white),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: product.sectionIds.map((sId) => _buildSectionBadge(sId)).toList(),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                            product.description ?? "Aucune description disponible.",
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.grey),
                      iconSize: 26,
                      tooltip: "Dupliquer",
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(productToEdit: product, isDuplicating: true, preloadedSections: _cachedSectionsList, allProducts: _allProducts))),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                      iconSize: 26,
                      tooltip: "Supprimer",
                      onPressed: () => _deleteProduct(context, repo, product),
                    ),
                  ],
                ),
                if (enableDrag)
                  ReorderableDragStartListener(
                    index: _allProducts.indexOf(product),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                      child: Icon(Icons.drag_indicator_rounded, color: Colors.grey.shade400, size: 30),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBadge(String sectionId) {
    ProductSection section;
    try {
      section = _cachedSectionsList.firstWhere((s) => s.sectionId == sectionId);
    } catch (e) {
      section = ProductSection(id: '0', sectionId: sectionId, title: 'Section introuvable ($sectionId)', selectionMin: 0, selectionMax: 0, type: 'checkbox', items: [], filterIds: []);
    }
    IconData icon;
    Color color;
    String typeLabel;
    final typeLower = section.type.toString().toLowerCase().trim();
    if (typeLower.contains('radio') || typeLower.contains('unique')) {
      icon = Icons.radio_button_checked_rounded;
      color = Colors.deepOrange;
      typeLabel = 'Choix Unique';
    } else if (typeLower.contains('increment') || typeLower.contains('quantity')) {
      icon = Icons.exposure_plus_1_rounded;
      color = Colors.green;
      typeLabel = 'Incrémental';
    } else {
      icon = Icons.check_box_rounded;
      color = Colors.blue.shade700;
      typeLabel = 'Choix Multiple';
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "$typeLabel • Min: ${section.selectionMin} / Max: ${section.selectionMax}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
            child: Icon(Icons.search_off_rounded, size: 40, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text("Aucun produit trouvé", style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _deleteProduct(BuildContext context, FranchiseRepository repo, MasterProduct product) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Supprimer ?"),
          content: Text("Voulez-vous supprimer définitivement '${product.name}' ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("Supprimer", style: TextStyle(color: Colors.white)))
          ],
        ));
    if (confirm == true) {
      await repo.deleteMasterProduct(product);
    }
  }
}

// ---------------------------------------------------------------------------
// FORMULAIRE PRODUIT (AJOUT / MODIFICATION)
// ---------------------------------------------------------------------------

class ProductFormView extends StatefulWidget {
  final MasterProduct? productToEdit;
  final bool isDuplicating;
  final String? preselectedFilterId;
  final List<ProductSection> preloadedSections;
  final List<MasterProduct> allProducts;

  const ProductFormView({
    super.key,
    this.productToEdit,
    this.isDuplicating = false,
    this.preselectedFilterId,
    this.preloadedSections = const [],
    this.allProducts = const [],
  });

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<ProductFormView> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  XFile? _imageFile;
  String? _displayUrl;
  final ImagePicker _picker = ImagePicker();
  bool _isComposite = false;
  bool _isIngredient = false;
  bool _isContainer = false;
  List<String> _linkedProductIds = [];
  List<ProductSection> _associatedSections = [];
  List<String> _selectedFilterIds = [];
  List<String> _selectedKioskFilterIds = [];
  bool _isLoading = false;
  List<ProductSection> _allAvailableSections = [];
  late TabController _tabController;
  List<ProductFilter> _loadedFilters = [];
  List<KioskCategory> _loadedKioskCategories = [];
  final List<StreamSubscription> _subscriptions = [];

  // ID des ingrédients sélectionnés
  List<String> _ingredientProductIds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _allAvailableSections = List.from(widget.preloadedSections);

    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    final repository = FranchiseRepository();

    _subscriptions.add(repository.getFiltersStream(uid).listen((data) {
      if(mounted) setState(() => _loadedFilters = data);
    }));
    _subscriptions.add(repository.getKioskCategoriesStream(uid).listen((data) {
      if(mounted) setState(() => _loadedKioskCategories = data);
    }));
    _subscriptions.add(repository.getSectionsStream(uid).listen((sections) {
      if(mounted) setState(() => _allAvailableSections = sections);
    }));

    if (widget.productToEdit != null) {
      final p = widget.productToEdit!;
      _nameController.text = p.name;
      _descriptionController.text = p.description ?? '';
      _priceController.text = p.price.toString();
      _isComposite = p.isComposite;
      _isIngredient = p.isIngredient;
      _isContainer = p.isContainer;
      _linkedProductIds = List.from(p.containerProductIds);
      if (!widget.isDuplicating) _displayUrl = p.photoUrl;
      _selectedFilterIds = List.from(p.filterIds);
      _selectedKioskFilterIds = List.from(p.kioskFilterIds);

      // Recharger les sections complètes à partir de leurs IDs
      if (p.sectionIds.isNotEmpty) {
        _associatedSections = [];
        for (var sid in p.sectionIds) {
          final match = _allAvailableSections.where((s) => s.sectionId == sid).firstOrNull;
          if(match != null) _associatedSections.add(match);
        }
      }

      // Initialisation des ingrédients
      _ingredientProductIds = List.from(p.ingredientProductIds);

    } else {
      if (widget.preselectedFilterId != null) {
        _selectedKioskFilterIds.add(widget.preselectedFilterId!);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _tabController.dispose();
    for(var s in _subscriptions) s.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) setState(() { _imageFile = image; _displayUrl = null; });
  }

  // --- ACTIONS MODALES ---

  // Nouvelle méthode pour ajouter une étape (Section ou Groupe)
  void _showStepPicker() async {
    final user = Provider.of<AuthProvider>(context, listen: false).firebaseUser!;

    // Récupération des groupes en direct
    List<SectionGroup> groups = [];
    try {
      final repo = FranchiseRepository();
      // On utilise first pour avoir les données une fois
      groups = await repo.getSectionGroupsStream(user.uid).first;
    } catch (_) {}

    if (!mounted) return;

    // Affiche la modale "Ajouter une étape" (Section ou Groupe)
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _StepSelectionDialog(
        availableSections: _allAvailableSections,
        availableGroups: groups,
      ),
    );

    if (result != null) {
      setState(() {
        if (result['type'] == 'section') {
          final s = result['data'] as ProductSection;
          // Vérifier doublon
          if (!_associatedSections.any((x) => x.sectionId == s.sectionId)) {
            _associatedSections.add(s);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Section '${s.title}' déjà présente.")));
          }
        } else if (result['type'] == 'group') {
          final g = result['data'] as SectionGroup;
          int added = 0;
          for (var sid in g.sectionIds) {
            if (!_associatedSections.any((x) => x.sectionId == sid)) {
              // On cherche la section correspondante dans la liste globale
              final match = _allAvailableSections.where((x) => x.sectionId == sid).firstOrNull;
              if (match != null) {
                _associatedSections.add(match);
                added++;
              }
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$added sections ajoutées du groupe '${g.name}'.")));
        }
      });
    }
  }

  void _showProductLinkPicker() async {
    final candidates = widget.allProducts.where((p) => p.id != widget.productToEdit?.id && !_linkedProductIds.contains(p.id) && !p.isContainer).toList();

    final MasterProduct? picked = await showDialog<MasterProduct>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            children: [
              Text("Ajouter un produit au conteneur", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if(candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucun autre produit disponible."),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final p = candidates[index];
                    return ListTile(
                      leading: CircleAvatar(backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty) ? CachedNetworkImageProvider(p.photoUrl!) : null, child: (p.photoUrl == null || p.photoUrl!.isEmpty) ? const Icon(Icons.fastfood) : null),
                      title: Text(p.name),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler"))
            ],
          ),
        ),
      ),
    );

    if (picked != null) {
      setState(() {
        _linkedProductIds.add(picked.id);
      });
    }
  }

  // Modale pour ajouter un ingrédient avec recherche
  void _showIngredientPicker() async {
    final availableIngredients = widget.allProducts
        .where((p) => p.isIngredient && !_ingredientProductIds.contains(p.productId))
        .toList();

    if (availableIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Aucun autre ingrédient disponible.")));
      return;
    }

    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) => _IngredientSearchDialog(ingredients: availableIngredients),
    );

    if (result != null) {
      setState(() {
        _ingredientProductIds.add(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.productToEdit == null ? "Nouveau Produit" : (widget.isDuplicating ? "Dupliquer" : "Modifier")),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0, top: 8, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveProduct,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: const Text(
                "Enregistrer",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.black,
          tabs: const [
            Tab(text: "Détails"),
            Tab(text: "Contenu & Étapes"),
            Tab(text: "Borne"),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildDetailsTab(),
            _buildContentTab(),
            _buildKioskTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[200], borderRadius: BorderRadius.circular(16),
                    image: _imageFile != null
                        ? DecorationImage(
                        image: kIsWeb
                            ? NetworkImage(_imageFile!.path)                   // ✅ Version WEB
                            : FileImage(File(_imageFile!.path)) as ImageProvider, // ✅ Version MOBILE
                        fit: BoxFit.cover)
                        : (_displayUrl != null
                        ? DecorationImage(image: CachedNetworkImageProvider(_displayUrl!), fit: BoxFit.cover)
                        : null),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                child: (_imageFile == null && _displayUrl == null) ? const Icon(Icons.add_a_photo, color: Colors.grey, size: 40) : null,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: "Nom du produit", border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Requis" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Prix (€)", border: OutlineInputBorder(), suffixText: "€"),
                  ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text("Est un Conteneur ?"),
          subtitle: const Text("Permet de regrouper plusieurs produits (ex: Frites -> Petite, Grande)."),
          value: _isContainer,
          activeColor: Colors.orange,
          onChanged: _isIngredient
              ? null
              : (val) {
            setState(() {
              _isContainer = val;
              if(val) _isComposite = false;
            });
          },
          contentPadding: EdgeInsets.zero,
        ),

        SwitchListTile(
          title: const Text("Est un ingrédient ?"),
          subtitle: const Text("Pour les fiches techniques uniquement"),
          value: _isIngredient,
          onChanged: (val) {
            setState(() {
              _isIngredient = val;
              if (val) {
                _isComposite = false;
                _isContainer = false;
              }
            });
          },
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 24),
        TextFormField(controller: _descriptionController, maxLines: 3, decoration: const InputDecoration(labelText: "Description", border: OutlineInputBorder())),

        const SizedBox(height: 24),
        const Text(
          "Ingrédients (pour la fiche technique)",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._ingredientProductIds.map((id) {
                    final ingName = widget.allProducts
                        .firstWhere((p) => p.productId == id,
                        orElse: () => MasterProduct.empty())
                        .name;
                    return Chip(
                      label: Text(ingName),
                      onDeleted: () {
                        setState(() {
                          _ingredientProductIds.remove(id);
                        });
                      },
                      backgroundColor: Colors.orange.shade50,
                      deleteIconColor: Colors.red,
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text("Ajouter"),
                    onPressed: _showIngredientPicker,
                  ),
                ],
              ),
              if (_ingredientProductIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    "Aucun ingrédient sélectionné.",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text("Filtres Back-Office", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _loadedFilters.map((filter) {
            final isSelected = _selectedFilterIds.contains(filter.id);
            return FilterChip(
              label: Text(filter.name),
              selected: isSelected,
              onSelected: (selected) {
                setState(() { selected ? _selectedFilterIds.add(filter.id) : _selectedFilterIds.remove(filter.id); });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildContentTab() {
    if (_isContainer) {
      return _buildContainerManager();
    }
    return _buildSectionsManager();
  }

  Widget _buildContainerManager() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        children: [
          _buildSectionHeader(
            title: "Produits liés au conteneur",
            subtitle: "Ajoutez ici les produits qui apparaîtront dans ce dossier (ex: Petite Frite, Grande Frite).",
            icon: Icons.folder_copy_rounded,
            color: Colors.orange.shade800,
            action: ElevatedButton.icon(
              onPressed: _showProductLinkPicker,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text("Lier un produit existant"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_linkedProductIds.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _linkedProductIds.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _linkedProductIds.removeAt(oldIndex);
                  _linkedProductIds.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final prodId = _linkedProductIds[index];
                final product = widget.allProducts.firstWhere((p) => p.id == prodId, orElse: () => MasterProduct(id: prodId, productId: prodId, name: "Produit Introuvable", createdBy: ''));

                return Padding(
                  key: ValueKey("link_$prodId"),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                          image: (product.photoUrl != null && product.photoUrl!.isNotEmpty) ? DecorationImage(image: CachedNetworkImageProvider(product.photoUrl!), fit: BoxFit.cover) : null,
                        ),
                        child: (product.photoUrl == null || product.photoUrl!.isEmpty) ? const Icon(Icons.fastfood, color: Colors.grey) : null,
                      ),
                      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      trailing: IconButton(
                        icon: const Icon(Icons.link_off_rounded, color: Colors.red),
                        onPressed: () => setState(() => _linkedProductIds.removeAt(index)),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            _buildEmptyState("Aucun produit lié pour le moment."),
        ],
      ),
    );
  }

  Widget _buildSectionsManager() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        children: [
          _buildSectionHeader(
            title: "Étapes / Sections",
            subtitle: "Ajoutez des étapes de personnalisation (Cuisson, Sauce, etc.).",
            icon: Icons.layers_rounded,
            color: Colors.blue.shade800,
            action: ElevatedButton.icon(
              onPressed: _showStepPicker, // MODIFICATION : Nouvelle modale Section/Groupe
              icon: const Icon(Icons.add_rounded),
              label: const Text("Ajouter une étape"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_associatedSections.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _associatedSections.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _associatedSections.removeAt(oldIndex);
                  _associatedSections.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final section = _associatedSections[index];
                return Padding(
                  key: ValueKey("g_sec_${section.sectionId}"),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.drag_handle_rounded, color: Colors.blue.shade700),
                      ),
                      title: Text(
                        section.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Text(
                        "${section.selectionMin} à ${section.selectionMax} choix",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          padding: const EdgeInsets.all(12),
                        ),
                        onPressed: () => setState(() => _associatedSections.removeAt(index)),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            _buildEmptyState("Aucune section configurée."),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: action),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildKioskTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text("Catégories Borne", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Text("Sélectionnez où ce produit doit apparaître sur la borne.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 16),
        ..._loadedKioskCategories.map((cat) {
          return ExpansionTile(
            title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            children: cat.filters.map((filter) {
              final isSelected = _selectedKioskFilterIds.contains(filter.id);
              return CheckboxListTile(
                title: Text(filter.name),
                value: isSelected,
                activeColor: Colors.black,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedKioskFilterIds.add(filter.id);
                    } else {
                      _selectedKioskFilterIds.remove(filter.id);
                    }
                  });
                },
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final repo = FranchiseRepository();

    // Déterminer les ID des ingrédients en fonction du type
    List<String> finalIngredientsIds = [];
    if (!_isContainer && !_isIngredient) {
      finalIngredientsIds = _ingredientProductIds;
    }

    // Déterminer les IDs des sections
    List<String> finalSectionIds = [];
    if (!_isContainer && !_isIngredient) {
      finalSectionIds = _associatedSections.map((s) => s.sectionId).toList();
    }

    try {
      await repo.saveProduct(
        product: widget.isDuplicating ? null : widget.productToEdit,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0,
        isComposite: _isComposite,
        isIngredient: _isIngredient,
        isContainer: _isContainer,
        containerProductIds: _linkedProductIds,
        filterIds: _selectedFilterIds,
        sectionIds: finalSectionIds,
        kioskFilterIds: _selectedKioskFilterIds,
        imageFile: _imageFile,
        existingPhotoUrl: _displayUrl,
        photoUrl: _displayUrl ?? "",
        ingredientProductIds: finalIngredientsIds,
        options: widget.productToEdit?.options ?? [],
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// MODALES CUSTOM (Ingrédients & Étapes)
// ---------------------------------------------------------------------------

class _IngredientSearchDialog extends StatefulWidget {
  final List<MasterProduct> ingredients;
  const _IngredientSearchDialog({required this.ingredients});

  @override
  State<_IngredientSearchDialog> createState() => _IngredientSearchDialogState();
}

class _IngredientSearchDialogState extends State<_IngredientSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final filtered = widget.ingredients.where((i) => i.name.toLowerCase().contains(_query.toLowerCase())).toList();

    return AlertDialog(
      title: const Text("Ajouter un ingrédient"),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState((){_searchController.clear(); _query="";})) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text("Aucun résultat"))
                  : ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (c,i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final ing = filtered[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade100,
                      backgroundImage: (ing.photoUrl?.isNotEmpty ?? false) ? CachedNetworkImageProvider(ing.photoUrl!) : null,
                      child: (ing.photoUrl?.isEmpty ?? true) ? const Icon(Icons.kitchen, size: 16) : null,
                    ),
                    title: Text(ing.name),
                    onTap: () => Navigator.pop(context, ing.productId),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler"))
      ],
    );
  }
}

class _StepSelectionDialog extends StatefulWidget {
  final List<ProductSection> availableSections;
  final List<SectionGroup> availableGroups;

  const _StepSelectionDialog({required this.availableSections, required this.availableGroups});

  @override
  State<_StepSelectionDialog> createState() => _StepSelectionDialogState();
}

class _StepSelectionDialogState extends State<_StepSelectionDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    // Filtrage dynamique
    final filteredSections = widget.availableSections.where((s) => s.title.toLowerCase().contains(_query.toLowerCase())).toList();
    final filteredGroups = widget.availableGroups.where((g) => g.name.toLowerCase().contains(_query.toLowerCase())).toList();

    return AlertDialog(
      title: const Text("Ajouter une Étape"),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState((){_searchController.clear(); _query="";})) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                tabs: const [Tab(text: "Section Unique"), Tab(text: "Groupe de Sections")],
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // LISTE SECTIONS
                  filteredSections.isEmpty
                      ? const Center(child: Text("Aucune section"))
                      : ListView.separated(
                    itemCount: filteredSections.length,
                    separatorBuilder: (c,i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final s = filteredSections[index];
                      return ListTile(
                        leading: const Icon(Icons.list, color: Colors.blue),
                        title: Text(s.title),
                        subtitle: Text("${s.items.length} choix"),
                        onTap: () => Navigator.pop(context, {'type': 'section', 'data': s}),
                      );
                    },
                  ),
                  // LISTE GROUPES
                  filteredGroups.isEmpty
                      ? const Center(child: Text("Aucun groupe"))
                      : ListView.separated(
                    itemCount: filteredGroups.length,
                    separatorBuilder: (c,i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final g = filteredGroups[index];
                      return ListTile(
                        leading: const Icon(Icons.folder_copy, color: Colors.orange),
                        title: Text(g.name),
                        subtitle: Text("${g.sectionIds.length} sections"),
                        onTap: () => Navigator.pop(context, {'type': 'group', 'data': g}),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler"))
      ],
    );
  }
}