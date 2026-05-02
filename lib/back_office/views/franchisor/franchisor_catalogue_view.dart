import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';

enum ProductTypeFilter { simple, container, ingredients }

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
  ProductTypeFilter _productTypeFilter = ProductTypeFilter.simple;
  String? _selectedKioskCategoryId;
  String? _selectedSubFilterId;
  String? _selectedBackOfficeFilterId;
  bool _isLoading = true;
  bool _areSectionsLoaded = false;
  final List<StreamSubscription> _subscriptions = [];
  @override
  void initState() {
    super.initState();
    final repo = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    _subscriptions.add(repo.getMasterProductsStream(uid).listen((products) {
      if (mounted) {
        products
            .sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    }));
    _subscriptions.add(repo.getSectionsStream(uid).listen((sections) {
      final map = <String, String>{};
      for (var s in sections) {
        map[s.sectionId] = s.title;
      }
      if (mounted) {
        setState(() {
          _cachedSectionsList = sections;
          _sectionNames = map;
          _areSectionsLoaded = true;
        });
      }
    }));
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
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Color _getColorFromHex(String hexColor) {
    try {
      hexColor = hexColor.toUpperCase().replaceAll("#", "");
      if (hexColor.length == 6) {
        hexColor = "FF$hexColor";
      }
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }

  List<MasterProduct> _getFilteredProducts() {
    return _allProducts.where((product) {
      if (_searchQuery.isNotEmpty) {
        if (!product.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (!_matchesProductType(product)) return false;
      if (_selectedBackOfficeFilterId != null) {
        if (!product.filterIds.contains(_selectedBackOfficeFilterId)) {
          return false;
        }
      }
      if (_selectedKioskCategoryId != null) {
        if (!_matchesKioskCategory(product)) return false;
      }
      return true;
    }).toList();
  }

  bool _matchesProductType(MasterProduct product) {
    switch (_productTypeFilter) {
      case ProductTypeFilter.simple:
        return !product.isIngredient && !product.isContainer;
      case ProductTypeFilter.container:
        return product.isContainer;
      case ProductTypeFilter.ingredients:
        return product.isIngredient;
    }
  }

  bool _matchesKioskCategory(MasterProduct product) {
    bool belongsToCategory = product.kioskFilterIds
        .any((fId) => _filterToCategoryMap[fId] == _selectedKioskCategoryId);
    if (!belongsToCategory) return false;
    if (_selectedSubFilterId != null) {
      return product.kioskFilterIds.contains(_selectedSubFilterId);
    }
    return true;
  }

  void _onReorder(
      int oldIndex, int newIndex, List<MasterProduct> currentList) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = currentList.removeAt(oldIndex);
      currentList.insert(newIndex, item);
    });
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
          if (_productTypeFilter != ProductTypeFilter.ingredients)
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
        height: 70,
        width: 70,
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF2D3436),
          elevation: 6,
          child: const Icon(Icons.add, size: 32, color: Colors.white),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ProductFormView(
                        preselectedFilterId: _selectedSubFilterId,
                        preloadedSections: _cachedSectionsList,
                        allProducts: _allProducts,
                      ))),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 4),
            blurRadius: 10)
      ]),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: TextField(
                    controller: _searchController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Rechercher...',
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchController.clear())
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
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
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text("Étiquette",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 13, color: Colors.black87)),
                      value: _selectedBackOfficeFilterId,
                      icon: const Icon(Icons.label_outline,
                          size: 20, color: Colors.grey),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text("Toutes",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        ..._cachedFilters.map((f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(f.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedBackOfficeFilterId = val),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildBigFilterBtn(
                      "Produits", Icons.storefront, ProductTypeFilter.simple)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildBigFilterBtn("Dossiers",
                      Icons.folder_copy_rounded, ProductTypeFilter.container)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildBigFilterBtn("Ingrédients", Icons.kitchen,
                      ProductTypeFilter.ingredients)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBigFilterBtn(
      String label, IconData icon, ProductTypeFilter type) {
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
          border: Border.all(
              color: isSelected ? Colors.transparent : Colors.grey.shade300),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isSelected ? Colors.white : Colors.grey[700], size: 18),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      color: Colors.white,
      height: 50,
      margin: const EdgeInsets.only(top: 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildTabItem("Vue d'ensemble", null),
          ..._cachedKioskCategories
              .map((cat) => _buildTabItem(cat.name, cat.id)),
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
          border: isSelected
              ? const Border(
                  bottom: BorderSide(color: Color(0xFF2D3436), width: 3))
              : null,
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
    final category = _cachedKioskCategories.firstWhere(
        (c) => c.id == _selectedKioskCategoryId,
        orElse: () =>
            KioskCategory(id: '', name: '', filters: [], position: 0));
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
        label: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13)),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedSubFilterId = filterId),
        backgroundColor: Colors.white,
        selectedColor: Colors.black87,
        checkmarkColor: Colors.white,
        shape: StadiumBorder(
            side: BorderSide(
                color: isSelected ? Colors.transparent : Colors.grey.shade300)),
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
        itemBuilder: (ctx, i) =>
            _buildProductCard(list[i], repo, enableDrag: false, index: i),
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
            _buildProductCard(product, repo,
                enableDrag: true,
                key: ValueKey("card_${product.id}"),
                index: i),
          ],
        );
      },
    );
  }

  Widget _buildSubCategoryHeaderIfNeeded(
      MasterProduct current, int index, List<MasterProduct> list) {
    if (_selectedKioskCategoryId == null) return const SizedBox.shrink();
    String currentSubCatName = "Autres / Non classés";
    String currentSubCatId = "others";
    for (var id in current.kioskFilterIds) {
      if (_filterToCategoryMap[id] == _selectedKioskCategoryId) {
        currentSubCatName =
            _kioskFilterNames[id]?.split('>').last.trim() ?? "Autres";
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
              decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.subdirectory_arrow_right,
                  size: 16, color: Colors.blueGrey[400]),
            ),
            const SizedBox(width: 12),
            Text(currentSubCatName.toUpperCase(),
                style: TextStyle(
                    color: Colors.blueGrey[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5)),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: Colors.blueGrey[100], thickness: 1)),
            if (currentSubCatId != "others")
              InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProductFormView(
                            preselectedFilterId: currentSubCatId,
                            preloadedSections: _cachedSectionsList,
                            allProducts: _allProducts))),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle,
                          size: 16, color: Colors.green[600]),
                      const SizedBox(width: 4),
                      Text("Ajouter",
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[800],
                              fontWeight: FontWeight.w600)),
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

  Widget _buildProductCard(MasterProduct product, FranchiseRepository repo,
      {required bool enableDrag, Key? key, required int index}) {
    final bool isIngredient = product.isIngredient;
    final bool isContainer = product.isContainer;
    String? kioskLabel;
    final productFilters =
        _cachedFilters.where((f) => product.filterIds.contains(f.id)).toList();
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
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 15,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ProductFormView(
                      productToEdit: product,
                      preloadedSections: _cachedSectionsList,
                      allProducts: _allProducts))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: "product_${product.id}",
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      image: (product.photoUrl != null &&
                              product.photoUrl!.isNotEmpty)
                          ? DecorationImage(
                              image: kIsWeb
                                  ? NetworkImage(product.photoUrl!)
                                      as ImageProvider
                                  : CachedNetworkImageProvider(
                                      product.photoUrl!),
                              fit: BoxFit.contain)
                          : null,
                    ),
                    child: Stack(
                      children: [
                        if (product.photoUrl == null ||
                            product.photoUrl!.isEmpty)
                          Center(
                              child: Icon(
                                  isIngredient
                                      ? Icons.blender
                                      : (isContainer
                                          ? Icons.folder_copy_rounded
                                          : Icons.restaurant),
                                  color: Colors.grey[300],
                                  size: 36)),
                        if (isContainer)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(10),
                                      bottomRight: Radius.circular(15))),
                              child: const Text("CONTENEUR",
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
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
                      Text(product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              color: Color(0xFF2D3436),
                              letterSpacing: -0.5)),
                      if (productFilters.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0, bottom: 6.0),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: productFilters.map((filter) {
                              final color =
                                  _getColorFromHex(filter.color ?? '#9E9E9E');
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: color.withValues(alpha: 0.4), width: 1),
                                ),
                                child: Text(
                                  filter.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: color.withValues(alpha: 1.0),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (kioskLabel != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(kioskLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.purple.shade800,
                                  fontWeight: FontWeight.bold)),
                        ),
                      if (!product.isContainer &&
                          product.description != null &&
                          product.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(product.description!,
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                  height: 1.4),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
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
                                  Icon(Icons.folder_open_rounded,
                                      size: 16, color: Colors.orange.shade800),
                                  const SizedBox(width: 8),
                                  Text("Contenu du dossier :",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade900)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (product.containerProductIds.isEmpty)
                                const Text("Vide",
                                    style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 12,
                                        color: Colors.grey))
                              else
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children:
                                      product.containerProductIds.map((id) {
                                    final childProduct = _allProducts
                                        .firstWhere((p) => p.id == id,
                                            orElse: () => MasterProduct(
                                                id: '',
                                                name: 'Inconnu',
                                                productId: '',
                                                createdBy: ''));
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        childProduct.name,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87),
                                      ),
                                    );
                                  }).toList(),
                                )
                            ],
                          ),
                        )
                      else if (product.sectionIds.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.hub_rounded,
                                      size: 14, color: Colors.grey.shade500),
                                  const SizedBox(width: 6),
                                  Text("PERSONNALISATION :",
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade500,
                                          letterSpacing: 1)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (!_areSectionsLoaded)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              else
                                Wrap(
                                  spacing: -12,
                                  runSpacing: 8,
                                  children: List.generate(
                                      product.sectionIds.length, (idx) {
                                    return _buildStepArrow(
                                        product.sectionIds[idx],
                                        idx,
                                        product.sectionIds.length);
                                  }),
                                ),
                            ],
                          ),
                        ),
                      if (!isIngredient && (product.price ?? 0) > 0)
                        Text("${product.price!.toStringAsFixed(2)} €",
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Color(0xFF00B894))),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.grey),
                      iconSize: 26,
                      tooltip: "Dupliquer",
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProductFormView(
                                  productToEdit: product,
                                  isDuplicating: true,
                                  preloadedSections: _cachedSectionsList,
                                  allProducts: _allProducts))),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Colors.red.shade400),
                      iconSize: 26,
                      tooltip: "Supprimer",
                      onPressed: () => _deleteProduct(context, repo, product),
                    ),
                  ],
                ),
                if (enableDrag)
                  ReorderableDragStartListener(
                    index: index,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 8),
                      child: Icon(Icons.drag_indicator_rounded,
                          color: Colors.grey.shade400, size: 30),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepArrow(String sectionId, int index, int total) {
    ProductSection section;
    try {
      section = _cachedSectionsList.firstWhere((s) => s.sectionId == sectionId);
    } catch (e) {
      section = ProductSection(
          id: '0',
          sectionId: sectionId,
          title: '?',
          selectionMin: 0,
          selectionMax: 0,
          type: 'checkbox',
          items: [],
          filterIds: []);
    }
    final bool isFirst = index == 0;
    final bool isLast = index == total - 1;
    Color sectionColor = _getSectionTypeColor(section.type);
    Color textColor = Colors.white;
    return ClipPath(
      clipper: ArrowClipper(isFirst: isFirst, isLast: isLast),
      child: Container(
        padding: EdgeInsets.only(
            left: isFirst ? 14 : 26,
            right: isLast ? 14 : 26,
            top: 7,
            bottom: 7),
        decoration: BoxDecoration(
            color: sectionColor,
            gradient: LinearGradient(
                colors: [sectionColor, sectionColor.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 2,
                  offset: const Offset(0, 1))
            ]),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getSectionIcon(section.type),
              color: textColor.withValues(alpha: 0.95),
              size: 14,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  section.title.toUpperCase(),
                  style: TextStyle(
                      color: textColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      height: 1.0),
                ),
                const SizedBox(height: 2),
                Text(
                  "${_getTypeLabel(section.type)} • ${section.selectionMin}-${section.selectionMax}",
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1.0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSectionIcon(String? type) {
    final t = type?.toLowerCase() ?? '';
    if (t.contains('radio') || t.contains('unique')) {
      return Icons.radio_button_checked;
    }
    if (t.contains('increment') || t.contains('quantity')) {
      return Icons.exposure_plus_1;
    }
    return Icons.check_box;
  }

  String _getTypeLabel(String? type) {
    final t = type?.toLowerCase() ?? '';
    if (t.contains('radio') || t.contains('unique')) return "Unique";
    if (t.contains('quantity')) return "Qté";
    return "Checkbox";
  }

  Color _getSectionTypeColor(String? type) {
    final t = type?.toLowerCase() ?? '';
    if (t.contains('radio') || t.contains('unique')) {
      return const Color(0xFFE67E22);
    }
    if (t.contains('quantity')) return const Color(0xFF27AE60);
    return const Color(0xFF2980B9);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration:
                BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
            child: Icon(Icons.search_off_rounded,
                size: 40, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text("Aucun produit trouvé",
              style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _deleteProduct(BuildContext context, FranchiseRepository repo,
      MasterProduct product) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Supprimer ?"),
              content: Text(
                  "Voulez-vous supprimer définitivement '${product.name}' ?"),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Annuler")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("Supprimer",
                        style: TextStyle(color: Colors.white)))
              ],
            ));
    if (confirm == true) {
      await repo.deleteMasterProduct(product);
    }
  }
}

class ArrowClipper extends CustomClipper<Path> {
  final bool isFirst;
  final bool isLast;
  final double arrowWidth = 14.0;
  ArrowClipper({required this.isFirst, required this.isLast});
  @override
  Path getClip(Size size) {
    Path path = Path();
    final w = size.width;
    final h = size.height;
    if (isFirst) {
      path.moveTo(0, 0);
    } else {
      path.moveTo(0, 0);
      path.lineTo(arrowWidth, h / 2);
      path.lineTo(0, h);
    }
    path.lineTo(0, h);
    if (isLast) {
      path.lineTo(w, h);
      path.lineTo(w, 0);
    } else {
      path.lineTo(w - arrowWidth, h);
      path.lineTo(w, h / 2);
      path.lineTo(w - arrowWidth, 0);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

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

class _ProductFormViewState extends State<ProductFormView>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  XFile? _imageFile;
  Uint8List? _imageBytes;
  String? _displayUrl;
  bool _isComposite = false;
  bool _isIngredient = false;
  bool _isContainer = false;
  List<String> _linkedProductIds = [];
  List<ProductSection> _associatedSections = [];
  List<String> _selectedFilterIds = [];
  List<String> _selectedKioskFilterIds = [];
  bool _isLoading = false;
  List<ProductSection> _allAvailableSections = [];
  List<ProductFilter> _loadedFilters = [];
  List<KioskCategory> _loadedKioskCategories = [];
  final List<StreamSubscription> _subscriptions = [];
  List<String> _ingredientProductIds = [];
  @override
  void initState() {
    super.initState();
    _allAvailableSections = List.from(widget.preloadedSections);
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    final repository = FranchiseRepository();
    _subscriptions.add(repository.getFiltersStream(uid).listen((data) {
      if (mounted) setState(() => _loadedFilters = data);
    }));
    _subscriptions.add(repository.getKioskCategoriesStream(uid).listen((data) {
      if (mounted) setState(() => _loadedKioskCategories = data);
    }));
    _subscriptions.add(repository.getSectionsStream(uid).listen((sections) {
      if (mounted) setState(() => _allAvailableSections = sections);
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
      if (p.sectionIds.isNotEmpty) {
        _associatedSections = [];
        for (var sid in p.sectionIds) {
          final match = _allAvailableSections
              .where((s) => s.sectionId == sid)
              .firstOrNull;
          if (match != null) _associatedSections.add(match);
        }
      }
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
    for (var s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();

    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();

      setState(() {
        _imageBytes = bytes;
        _imageFile =
            pickedFile; // pickedFile est déjà de type XFile, donc plus besoin de XFile.fromData()
        _displayUrl = null;
      });
    }
  }

  void _showStepPicker() async {
    final user =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!;
    List<SectionGroup> groups = [];
    try {
      final repo = FranchiseRepository();
      groups = await repo.getSectionGroupsStream(user.uid).first;
    } catch (_) {}
    if (!mounted) return;
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
          if (!_associatedSections.any((x) => x.sectionId == s.sectionId)) {
            _associatedSections.add(s);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Section '${s.title}' déjà présente.")));
          }
        } else if (result['type'] == 'group') {
          final g = result['data'] as SectionGroup;
          int added = 0;
          for (var sid in g.sectionIds) {
            if (!_associatedSections.any((x) => x.sectionId == sid)) {
              final match = _allAvailableSections
                  .where((x) => x.sectionId == sid)
                  .firstOrNull;
              if (match != null) {
                _associatedSections.add(match);
                added++;
              }
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text("$added sections ajoutées du groupe '${g.name}'.")));
        }
      });
    }
  }

  void _showProductLinkPicker() async {
    final List<String>? resultIds = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => ContainerSelectionDialog(
        allProducts: widget.allProducts,
        alreadyLinkedIds: _linkedProductIds,
        currentProductId: widget.productToEdit?.id,
        availableFilters: _loadedFilters,
      ),
    );
    if (resultIds != null && resultIds.isNotEmpty) {
      setState(() {
        for (var id in resultIds) {
          if (!_linkedProductIds.contains(id)) {
            _linkedProductIds.add(id);
          }
        }
      });
    }
  }

  void _showIngredientPicker() async {
    final availableIngredients = widget.allProducts
        .where((p) =>
            p.isIngredient && !_ingredientProductIds.contains(p.productId))
        .toList();
    if (availableIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Aucun autre ingrédient disponible.")));
      return;
    }
    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _IngredientSearchDialog(ingredients: availableIngredients),
    );
    if (result != null) {
      setState(() {
        _ingredientProductIds.add(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [const Tab(text: "Détails")];
    List<Widget> views = [_buildDetailsTab()];
    if (!_isIngredient) {
      tabs.add(const Tab(text: "Contenu & Étapes"));
      views.add(_buildContentTab());
      tabs.add(const Tab(text: "Borne"));
      views.add(_buildKioskTab());
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text(widget.productToEdit == null
              ? "Nouveau Produit"
              : (widget.isDuplicating ? "Dupliquer" : "Modifier")),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0, top: 8, bottom: 8),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveProduct,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 18),
                label: const Text("Enregistrer",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
              ),
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.black,
            tabs: tabs,
          ),
        ),
        body: Form(
          key: _formKey,
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: views,
          ),
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
            Stack(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      image: _imageBytes != null
                          ? DecorationImage(
                              image: MemoryImage(_imageBytes!),
                              fit: BoxFit.contain)
                          : (_displayUrl != null && _displayUrl!.isNotEmpty
                              ? DecorationImage(
                                  image: kIsWeb
                                      ? NetworkImage(_displayUrl!)
                                          as ImageProvider
                                      : CachedNetworkImageProvider(
                                          _displayUrl!),
                                  fit: BoxFit.contain)
                              : null),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: (_imageBytes == null &&
                            (_displayUrl == null || _displayUrl!.isEmpty))
                        ? const Icon(Icons.add_a_photo,
                            color: Colors.grey, size: 40)
                        : null,
                  ),
                ),
                if (_imageBytes != null ||
                    (_displayUrl != null && _displayUrl!.isNotEmpty))
                  Positioned(
                    right: -5,
                    top: -5,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _imageFile = null;
                          _imageBytes = null;
                          _displayUrl = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 4)
                            ]),
                        child: const Icon(Icons.cancel,
                            color: Colors.red, size: 20),
                      ),
                    ),
                  )
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                        labelText: "Nom du produit",
                        border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Requis" : null,
                  ),
                  const SizedBox(height: 16),
                  if (!_isContainer)
                    TextFormField(
                      controller: _priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: "Prix (€)",
                          border: OutlineInputBorder(),
                          suffixText: "€"),
                    ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text("Est un Conteneur ?"),
          subtitle: const Text(
              "Permet de regrouper plusieurs produits (ex: Frites -> Petite, Grande)."),
          value: _isContainer,
          activeThumbColor: Colors.orange,
          onChanged: _isIngredient
              ? null
              : (val) {
                  setState(() {
                    _isContainer = val;
                    if (val) {
                      _isComposite = false;
                      _priceController.clear();
                    }
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
        TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: "Description", border: OutlineInputBorder())),
        const SizedBox(height: 24),
        if (!_isIngredient && !_isContainer) ...[
          const Text("Ingrédients (pour la fiche technique)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12)),
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
                        onDeleted: () =>
                            setState(() => _ingredientProductIds.remove(id)),
                        backgroundColor: Colors.orange.shade50,
                        deleteIconColor: Colors.red,
                      );
                    }),
                    ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text("Ajouter"),
                        onPressed: _showIngredientPicker),
                  ],
                ),
                if (_ingredientProductIds.isEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text("Aucun ingrédient sélectionné.",
                          style: TextStyle(color: Colors.grey, fontSize: 12))),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        const Text("Filtres Back-Office",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _loadedFilters.map((filter) {
            final isSelected = _selectedFilterIds.contains(filter.id);
            return FilterChip(
              label: Text(filter.name),
              selected: isSelected,
              onSelected: (selected) => setState(() => selected
                  ? _selectedFilterIds.add(filter.id)
                  : _selectedFilterIds.remove(filter.id)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildContentTab() {
    if (_isContainer) return _buildContainerManager();
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
            subtitle:
                "Ajoutez ici les produits qui apparaîtront dans ce dossier.",
            icon: Icons.folder_copy_rounded,
            color: Colors.orange.shade800,
            action: ElevatedButton.icon(
              onPressed: _showProductLinkPicker,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text("Lier un produit existant"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                final product = widget.allProducts.firstWhere(
                    (p) => p.id == prodId,
                    orElse: () => MasterProduct(
                        id: prodId,
                        productId: prodId,
                        name: "Produit Introuvable",
                        createdBy: ''));
                return Padding(
                  key: ValueKey("link_$prodId"),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.transparent,
                          image: (product.photoUrl != null &&
                                  product.photoUrl!.isNotEmpty)
                              ? DecorationImage(
                                  image: kIsWeb
                                      ? NetworkImage(product.photoUrl!)
                                          as ImageProvider
                                      : CachedNetworkImageProvider(
                                          product.photoUrl!),
                                  fit: BoxFit.contain)
                              : null,
                        ),
                        child: (product.photoUrl == null ||
                                product.photoUrl!.isEmpty)
                            ? const Icon(Icons.fastfood, color: Colors.grey)
                            : null,
                      ),
                      title: Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                          icon: const Icon(Icons.link_off_rounded,
                              color: Colors.red),
                          onPressed: () => setState(
                              () => _linkedProductIds.removeAt(index))),
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
            subtitle:
                "Ajoutez des étapes de personnalisation (Cuisson, Sauce, etc.).",
            icon: Icons.layers_rounded,
            color: Colors.blue.shade800,
            action: ElevatedButton.icon(
              onPressed: _showStepPicker,
              icon: const Icon(Icons.add_rounded),
              label: const Text("Ajouter une étape"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Icon(Icons.drag_handle_rounded,
                          color: Colors.blue.shade700),
                      title: Text(section.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          "${section.selectionMin} à ${section.selectionMax} choix"),
                      trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () => setState(
                              () => _associatedSections.removeAt(index))),
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

  Widget _buildSectionHeader(
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required Widget action}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600))
                ])),
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
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: Colors.grey.shade500))
      ]),
    );
  }

  Widget _buildKioskTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text("Catégories Borne",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Text("Sélectionnez où ce produit doit apparaître sur la borne.",
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 16),
        ..._loadedKioskCategories.map((cat) {
          return ExpansionTile(
            title: Text(cat.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            children: cat.filters.map((filter) {
              final isSelected = _selectedKioskFilterIds.contains(filter.id);
              return CheckboxListTile(
                title: Text(filter.name),
                value: isSelected,
                activeColor: Colors.black,
                onChanged: (val) => setState(() => val == true
                    ? _selectedKioskFilterIds.add(filter.id)
                    : _selectedKioskFilterIds.remove(filter.id)),
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
    List<String> finalIngredientsIds =
        (!_isContainer && !_isIngredient) ? _ingredientProductIds : [];
    List<String> finalSectionIds = (!_isContainer && !_isIngredient)
        ? _associatedSections.map((s) => s.sectionId).toList()
        : [];
    try {
      await repo.saveProduct(
        product: widget.isDuplicating ? null : widget.productToEdit,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: _isContainer
            ? 0.0
            : (double.tryParse(_priceController.text.replaceAll(',', '.')) ??
                0.0),
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _IngredientSearchDialog extends StatefulWidget {
  final List<MasterProduct> ingredients;
  const _IngredientSearchDialog({required this.ingredients});
  @override
  State<_IngredientSearchDialog> createState() =>
      _IngredientSearchDialogState();
}

class _IngredientSearchDialogState extends State<_IngredientSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = "";
  @override
  Widget build(BuildContext context) {
    final filtered = widget.ingredients
        .where((i) => i.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
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
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                              _searchController.clear();
                              _query = "";
                            }))
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text("Aucun résultat"))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (c, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final ing = filtered[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey.shade100,
                            backgroundImage: (ing.photoUrl?.isNotEmpty ?? false)
                                ? (kIsWeb
                                    ? NetworkImage(ing.photoUrl!)
                                        as ImageProvider
                                    : CachedNetworkImageProvider(ing.photoUrl!))
                                : null,
                            child: (ing.photoUrl?.isEmpty ?? true)
                                ? const Icon(Icons.kitchen, size: 16)
                                : null,
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"))
      ],
    );
  }
}

class _StepSelectionDialog extends StatefulWidget {
  final List<ProductSection> availableSections;
  final List<SectionGroup> availableGroups;
  const _StepSelectionDialog(
      {required this.availableSections, required this.availableGroups});
  @override
  State<_StepSelectionDialog> createState() => _StepSelectionDialogState();
}

class _StepSelectionDialogState extends State<_StepSelectionDialog>
    with SingleTickerProviderStateMixin {
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
    final filteredSections = widget.availableSections
        .where((s) => s.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final filteredGroups = widget.availableGroups
        .where((g) => g.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
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
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                              _searchController.clear();
                              _query = "";
                            }))
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12)),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                tabs: const [
                  Tab(text: "Section Unique"),
                  Tab(text: "Groupe de Sections")
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  filteredSections.isEmpty
                      ? const Center(child: Text("Aucune section"))
                      : ListView.separated(
                          itemCount: filteredSections.length,
                          separatorBuilder: (c, i) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final s = filteredSections[index];
                            return ListTile(
                              leading:
                                  const Icon(Icons.list, color: Colors.blue),
                              title: Text(s.title),
                              subtitle: Text("${s.items.length} choix"),
                              onTap: () => Navigator.pop(
                                  context, {'type': 'section', 'data': s}),
                            );
                          },
                        ),
                  filteredGroups.isEmpty
                      ? const Center(child: Text("Aucun groupe"))
                      : ListView.separated(
                          itemCount: filteredGroups.length,
                          separatorBuilder: (c, i) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final g = filteredGroups[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_copy,
                                  color: Colors.orange),
                              title: Text(g.name),
                              subtitle: Text("${g.sectionIds.length} sections"),
                              onTap: () => Navigator.pop(
                                  context, {'type': 'group', 'data': g}),
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"))
      ],
    );
  }
}

class ContainerSelectionDialog extends StatefulWidget {
  final List<MasterProduct> allProducts;
  final List<String> alreadyLinkedIds;
  final String? currentProductId;
  final List<ProductFilter> availableFilters;
  const ContainerSelectionDialog({
    super.key,
    required this.allProducts,
    required this.alreadyLinkedIds,
    this.currentProductId,
    this.availableFilters = const [],
  });
  @override
  State<ContainerSelectionDialog> createState() =>
      _ContainerSelectionDialogState();
}

class _ContainerSelectionDialogState extends State<ContainerSelectionDialog> {
  String _searchQuery = '';
  String? _selectedFilterId;
  final List<String> _tempSelectedIds = [];
  @override
  Widget build(BuildContext context) {
    final filteredProducts = widget.allProducts.where((p) {
      if (p.id == widget.currentProductId) return false;
      if (widget.alreadyLinkedIds.contains(p.id)) return false;
      if (p.isContainer) return false;
      if (_searchQuery.isNotEmpty &&
          !p.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (p.isIngredient) return false;
      if (_selectedFilterId != null) {
        if (!p.filterIds.contains(_selectedFilterId)) return false;
      }
      return true;
    }).toList();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 500,
        height: 700,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Ajouter au dossier",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            TextField(
              decoration: InputDecoration(
                hintText: "Rechercher un produit...",
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...widget.availableFilters.map((filter) {
                    final isSelected = _selectedFilterId == filter.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(filter.name),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            _selectedFilterId = val ? filter.id : null;
                          });
                        },
                        selectedColor: Colors.blue.shade100,
                        labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.blue.shade900
                                : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("${filteredProducts.length} produits trouvés",
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: filteredProducts.isEmpty
                    ? const Center(child: Text("Aucun produit correspondant."))
                    : ListView.separated(
                        itemCount: filteredProducts.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final prod = filteredProducts[i];
                          final isSelected = _tempSelectedIds.contains(prod.id);
                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            activeColor: Colors.orange.shade800,
                            title: Text(prod.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                "${prod.price?.toStringAsFixed(2) ?? '0.00'} €",
                                style: TextStyle(color: Colors.grey.shade600)),
                            secondary: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                image: (prod.photoUrl?.isNotEmpty ?? false)
                                    ? DecorationImage(
                                        image: kIsWeb
                                            ? NetworkImage(prod.photoUrl!)
                                                as ImageProvider
                                            : CachedNetworkImageProvider(
                                                prod.photoUrl!),
                                        fit: BoxFit.contain)
                                    : null,
                              ),
                              child: (prod.photoUrl?.isEmpty ?? true)
                                  ? const Icon(Icons.fastfood,
                                      size: 20, color: Colors.grey)
                                  : null,
                            ),
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _tempSelectedIds.add(prod.id);
                                } else {
                                  _tempSelectedIds.remove(prod.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, _tempSelectedIds),
                child:
                    Text("AJOUTER LA SÉLECTION (${_tempSelectedIds.length})"),
              ),
            )
          ],
        ),
      ),
    );
  }
}
