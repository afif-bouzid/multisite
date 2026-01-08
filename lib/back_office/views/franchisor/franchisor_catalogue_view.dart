import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth_provider.dart';
import '../../../core/constants.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
import 'image_input_card.dart';

// --- ENUMS ---
enum ProductTypeFilter { sellable, ingredients }
enum SellableTypeFilter { all, simple, composite }

class CatalogueView extends StatefulWidget {
  const CatalogueView({super.key});

  @override
  State<CatalogueView> createState() => _CatalogueViewState();
}

class _CatalogueViewState extends State<CatalogueView> {
  // --- CONTROLLERS & STATE ---
  final _searchController = TextEditingController();

  // Données
  List<MasterProduct> _allProducts = [];
  Map<String, String> _sectionNames = {};
  List<ProductFilter> _cachedFilters = [];
  List<KioskCategory> _cachedKioskCategories = [];
  Map<String, String> _kioskFilterNames = {};
  Map<String, String> _filterToCategoryMap = {};

  // Filtres actifs
  String _searchQuery = '';
  ProductTypeFilter _productTypeFilter = ProductTypeFilter.sellable;
  SellableTypeFilter _sellableTypeFilter = SellableTypeFilter.all;

  String? _selectedKioskCategoryId;
  String? _selectedSubFilterId;
  String? _selectedBackOfficeFilterId;

  // --- NOUVEAU : Gestion des sections repliées ---
  final Set<String> _collapsedSections = {};

  bool _isLoading = true;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    final repo = FranchiseRepository();
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    _subscriptions.add(repo.getMasterProductsStream(uid).listen((products) {
      if (mounted) {
        products.sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    }));

    _subscriptions.add(repo.getSectionsStream(uid).listen((sections) {
      final map = <String, String>{};
      for (var s in sections) map[s.sectionId] = s.title;
      if (mounted) setState(() => _sectionNames = map);
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
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (var sub in _subscriptions) sub.cancel();
    super.dispose();
  }

  List<MasterProduct> _getFilteredProducts() {
    return _allProducts.where((p) {
      if (_searchQuery.isNotEmpty && !p.name.toLowerCase().contains(_searchQuery)) return false;

      if (_productTypeFilter == ProductTypeFilter.sellable && p.isIngredient) return false;
      if (_productTypeFilter == ProductTypeFilter.ingredients && !p.isIngredient) return false;

      if (_productTypeFilter == ProductTypeFilter.sellable) {
        if (_sellableTypeFilter == SellableTypeFilter.simple && p.isComposite) return false;
        if (_sellableTypeFilter == SellableTypeFilter.composite && !p.isComposite) return false;
      }

      if (_selectedBackOfficeFilterId != null) {
        if (!p.filterIds.contains(_selectedBackOfficeFilterId)) return false;
      }

      if (_selectedKioskCategoryId != null) {
        bool belongsToCategory = false;
        for (var fId in p.kioskFilterIds) {
          if (_filterToCategoryMap[fId] == _selectedKioskCategoryId) {
            belongsToCategory = true;
            break;
          }
        }
        if (!belongsToCategory) return false;

        if (_selectedSubFilterId != null) {
          if (!p.kioskFilterIds.contains(_selectedSubFilterId)) return false;
        }
      }
      return true;
    }).toList();
  }

  void _onReorder(int oldIndex, int newIndex, List<MasterProduct> currentList) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = currentList.removeAt(oldIndex);
      currentList.insert(newIndex, item);
    });
    await FranchiseRepository().updateMasterProductsOrder(currentList);
  }

  void _toggleSectionCollapse(String sectionId) {
    setState(() {
      if (_collapsedSections.contains(sectionId)) {
        _collapsedSections.remove(sectionId);
      } else {
        _collapsedSections.add(sectionId);
      }
    });
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
              MaterialPageRoute(
                  builder: (_) => ProductFormView(preselectedFilterId: _selectedSubFilterId)
              )
          ),
        ),
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

  // --- NOUVEAU : Header Pliable et Stylisé ---
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
      // Vérifier si cette section est repliée
      // Note: Le ReorderableList ne supporte pas bien le masquage complet des items enfants via un header
      // Pour une vraie fonctionnalité "Accordéon" avec Drag & Drop global, c'est complexe.
      // ICI : On affiche un beau header séparateur.

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
            // Petit bouton d'ajout rapide dans le header
            if (currentSubCatId != "others")
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(preselectedFilterId: currentSubCatId))),
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

  // --- CARTE PRODUIT AVEC SURBRILLANCE RECHERCHE ---

  Widget _buildProductCard(MasterProduct product, FranchiseRepository repo, {required bool enableDrag, Key? key}) {
    final bool isMenu = product.isComposite;
    final bool isIngredient = product.isIngredient;

    List<String> stepNames = [];
    for(var sId in product.sectionIds) {
      if (_sectionNames.containsKey(sId)) stepNames.add(_sectionNames[sId]!);
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
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Plus arrondi
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)), // Ombre plus douce
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 2, offset: const Offset(0, 1))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(productToEdit: product))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // IMAGE
                SizedBox(
                  width: 72, height: 72,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade100),
                          image: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                              ? DecorationImage(image: CachedNetworkImageProvider(product.photoUrl!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: (product.photoUrl == null || product.photoUrl!.isEmpty)
                            ? Center(child: Icon(isIngredient ? Icons.blender : (isMenu ? Icons.fastfood : Icons.restaurant), color: Colors.grey[300]))
                            : null,
                      ),
                      if (isMenu)
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.only(topLeft: Radius.circular(8), bottomRight: Radius.circular(12))),
                            child: const Text("MENU", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                        )
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // INFOS
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TITRE AVEC SURBRILLANCE
                      _buildHighlightedText(product.name, _searchQuery),

                      const SizedBox(height: 6),
                      if (kioskLabel != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.purple.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                          child: Text(kioskLabel, style: TextStyle(fontSize: 11, color: Colors.purple[800], fontWeight: FontWeight.w600)),
                        ),

                      if (stepNames.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.layers_outlined, size: 12, color: Colors.blue[300]),
                            const SizedBox(width: 4),
                            Text("${stepNames.length} étapes", style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.w500)),
                          ],
                        )
                      else
                        Text(
                            product.description != null && product.description!.isNotEmpty ? product.description! : "Sans description",
                            style: TextStyle(color: Colors.grey[400], fontSize: 12, fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis
                        ),
                    ],
                  ),
                ),

                // ACTIONS DISCRETES
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 20, color: Colors.grey[400]),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormView(productToEdit: product, isDuplicating: true))),
                      tooltip: "Dupliquer",
                      splashRadius: 20,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                      onPressed: () => _deleteProduct(context, repo, product),
                      tooltip: "Supprimer",
                      splashRadius: 20,
                    ),
                    if (enableDrag)
                      ReorderableDragStartListener(
                        index: _allProducts.indexOf(product),
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8)
                          ),
                          child: Icon(Icons.drag_indicator_rounded, color: Colors.grey[400], size: 20),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- NOUVEAU : Fonction de surbrillance ---
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D3436)));
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matches = lowerQuery.allMatches(lowerText);

    if (matches.isEmpty) {
      return Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D3436)));
    }

    final List<TextSpan> spans = [];
    int start = 0;

    for (var match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: const TextStyle(color: Color(0xFF2D3436))));
      }
      spans.add(TextSpan(
          text: text.substring(match.start, match.end),
          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, decoration: TextDecoration.underline, decorationColor: Colors.orange)
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: const TextStyle(color: Color(0xFF2D3436))));
    }

    return RichText(text: TextSpan(style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Poppins'), children: spans));
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

  // --- TOP BARS (Identiques mais avec style épuré) ---

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), offset: const Offset(0, 4), blurRadius: 10)]
      ),
      child: Column(
        children: [
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
          Row(
            children: [
              Expanded(child: _buildBigFilterBtn("Vendables", Icons.storefront, ProductTypeFilter.sellable)),
              const SizedBox(width: 12),
              Expanded(child: _buildBigFilterBtn("Ingrédients", Icons.kitchen, ProductTypeFilter.ingredients)),
            ],
          ),
          if (_productTypeFilter == ProductTypeFilter.sellable) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildToggleChip("Produits Simples", SellableTypeFilter.simple),
                const SizedBox(width: 10),
                _buildToggleChip("Menus & Composés", SellableTypeFilter.composite),
              ],
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
          ..._cachedKioskCategories.map((cat) => _buildTabItem(cat.name, cat.id)).toList(),
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
          ...category.filters.map((f) => _buildSubFilterChip(f.name, f.id)).toList(),
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

  void _deleteProduct(BuildContext context, FranchiseRepository repo, MasterProduct product) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Supprimer ?"),
          content: Text("Voulez-vous supprimer définitivement '${product.name}' ?\nL'image sera effacée."),
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

// -----------------------------------------------------------------------------
// VUE FORMULAIRE & POPUPS
// -----------------------------------------------------------------------------

class ProductFormView extends StatefulWidget {
  final MasterProduct? productToEdit;
  final bool isDuplicating;
  final String? preselectedFilterId;

  const ProductFormView({
    super.key,
    this.productToEdit,
    this.isDuplicating = false,
    this.preselectedFilterId,
  });

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
                  return ExpansionTile(title: Text(filter.name), initiallyExpanded: true, children: products.map((p) => CheckboxListTile(title: Text(p.name), value: _selectedProducts.any((sp) => sp.id == p.id), onChanged: (val) { setState(() { if(val!) _selectedProducts.add(p); else _selectedProducts.removeWhere((x)=>x.id==p.id); }); })).toList());
                }).toList(),
                if(ungroupedProducts.isNotEmpty) ExpansionTile(title: const Text("Non classés"), initiallyExpanded: true, children: ungroupedProducts.where((p)=>p.name.toLowerCase().contains(_searchQuery)).map((p) => CheckboxListTile(title: Text(p.name), value: _selectedProducts.any((sp) => sp.id == p.id), onChanged: (val) { setState(() { if(val!) _selectedProducts.add(p); else _selectedProducts.removeWhere((x)=>x.id==p.id); }); })).toList())
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
  final _colorController = TextEditingController();

  String? _selectedColorHex;
  XFile? _imageFile;
  String? _displayUrl;
  String? _originalUrl;

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

  Map<String, XFile?> _pendingOptionImages = {};
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

      if (widget.isDuplicating) {
        _displayUrl = null;
        _originalUrl = null;
      } else {
        _displayUrl = widget.productToEdit!.photoUrl;
        _originalUrl = widget.productToEdit!.photoUrl;
      }

      _isComposite = widget.productToEdit!.isComposite;
      _isIngredient = widget.productToEdit!.isIngredient;
      _selectedFilterIds = List.from(widget.productToEdit!.filterIds);
      _selectedKioskFilterIds = List.from(widget.productToEdit!.kioskFilterIds);
      _productOptions = List.from(widget.productToEdit!.options);

      if (_isComposite) _loadSectionsForProduct();
      if (widget.productToEdit!.ingredientProductIds.isNotEmpty) {
        _loadIngredientsForProduct();
      }
    } else {
      // --- LOGIQUE AJOUT CONTEXTUEL ---
      if (widget.preselectedFilterId != null) {
        _selectedKioskFilterIds.add(widget.preselectedFilterId!);
      }
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) sub.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
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
    for (final snapshot in snapshots) docs.addAll(snapshot.docs);
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
      String? originalUrlForDeletion;

      if (widget.productToEdit != null && !widget.isDuplicating) {
        productToUpdate = widget.productToEdit;
        originalUrlForDeletion = widget.productToEdit!.photoUrl;
      }

      String photoUrlToSend = "";
      if (_imageFile == null && (_displayUrl != null && _displayUrl!.isNotEmpty)) {
        photoUrlToSend = _displayUrl!;
      }

      await repository.saveProduct(
        product: productToUpdate,
        name: _nameController.text,
        description: _descriptionController.text,
        imageFile: _imageFile,
        existingPhotoUrl: originalUrlForDeletion,
        photoUrl: photoUrlToSend,
        color: _selectedColorHex,
        isComposite: _isComposite,
        isIngredient: _isIngredient,
        filterIds: _selectedFilterIds,
        sectionIds: _associatedSections.map((s) => s.sectionId).toList(),
        options: finalOptions,
        ingredientProductIds: _associatedIngredients.map((p) => p.productId).toList(),
        kioskFilterIds: _isIngredient ? [] : _selectedKioskFilterIds,
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
                await FranchiseRepository().saveKioskFilter(categoryId: category.id, name: name, position: 99, imageUrl: '');
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
                ImageInputCard(
                  label: "Photo du produit",
                  imageFile: _imageFile,
                  imageUrl: _displayUrl,
                  size: 180,
                  onPick: () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(source: ImageSource.gallery);
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
                    activeColor: Colors.orange,
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
          spacing: 12,
          runSpacing: 12,
          children: _loadedFilters.map((filter) => FilterChip(
              padding: const EdgeInsets.all(12),
              label: Text(filter.name, style: const TextStyle(fontSize: 16)),
              selected: _selectedFilterIds.contains(filter.id),
              onSelected: (selected) => setState(() {
                selected ? _selectedFilterIds.add(filter.id) : _selectedFilterIds.remove(filter.id);
              }))).toList(),
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
                    spacing: 12,
                    runSpacing: 12,
                    children: category.filters.map((filter) => FilterChip(
                        padding: const EdgeInsets.all(12),
                        label: Text(filter.name, style: const TextStyle(fontSize: 16)),
                        selected: _selectedKioskFilterIds.contains(filter.id),
                        onSelected: (selected) => setState(() {
                          selected ? _selectedKioskFilterIds.add(filter.id) : _selectedKioskFilterIds.remove(filter.id);
                        }))).toList(),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }
}

class _ProductOptionsDialog extends StatefulWidget {
  final List<ProductOption> initialOptions;
  final Function(List<ProductOption>, Map<String, XFile?>) onConfirm;
  const _ProductOptionsDialog({super.key, required this.initialOptions, required this.onConfirm});
  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  late List<ProductOption> _options;
  final Map<String, XFile?> _newImages = {};
  final ImagePicker _picker = ImagePicker();
  @override
  void initState() {
    super.initState();
    _options = List.from(widget.initialOptions);
  }

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
                ImageInputCard(
                  size: 100,
                  label: "Photo",
                  imageFile: tempImage,
                  imageUrl: null,
                  onPick: () async {
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      setStateDialog(() => tempImage = image);
                    }
                  },
                  onRemove: () {
                    setStateDialog(() => tempImage = null);
                  },
                ),
                const SizedBox(height: 20),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nom (ex: Menu XL)", border: OutlineInputBorder())),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler", style: TextStyle(fontSize: 18))),
              ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      this.setState(() {
                        final newId = const Uuid().v4();
                        _options.add(ProductOption(id: newId, name: nameController.text, sectionIds: []));
                        if (tempImage != null) _newImages[newId] = tempImage;
                      });
                      Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: const Text("Créer", style: TextStyle(fontSize: 18)))
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickImageForOption(String optionId) async {
    // Cette méthode n'est plus utilisée directement avec le widget ImageInputCard
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
            content: SizedBox(
              width: 500,
              height: 600,
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
      content: SizedBox(
        width: 700,
        height: 600,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _options.length,
                itemBuilder: (context, index) {
                  final opt = _options[index];
                  final hasNewImage = _newImages.containsKey(opt.id);
                  // Préparation des variables pour ImageInputCard
                  final displayImageFile = hasNewImage ? _newImages[opt.id] : null;
                  final displayImageUrl = !hasNewImage ? opt.imageUrl : null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: ImageInputCard(
                        size: 60,
                        label: "",
                        imageFile: displayImageFile,
                        imageUrl: displayImageUrl,
                        onPick: () async {
                          final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            setState(() {
                              _newImages[opt.id] = image;
                            });
                          }
                        },
                        onRemove: () {
                          setState(() {
                            // Supprime l'image locale si elle existe
                            _newImages.remove(opt.id);
                            // Supprime l'URL distante en mettant à vide
                            _options[index] = ProductOption(id: opt.id, name: opt.name, sectionIds: opt.sectionIds, imageUrl: "");
                          });
                        },
                      ),
                      title: Text(opt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text("${opt.sectionIds.length} section(s) associée(s)", style: const TextStyle(fontSize: 16)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
        ElevatedButton(
            onPressed: () {
              widget.onConfirm(_options, _newImages);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
            child: const Text("Valider", style: TextStyle(fontSize: 18))),
      ],
    );
  }
}