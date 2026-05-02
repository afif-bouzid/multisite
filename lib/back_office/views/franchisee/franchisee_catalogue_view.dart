import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
import 'franchisee_container_config_dialog.dart';
import 'franchisee_composite_overrides_dialog.dart';

enum _CatalogueMode { ordering, pricing }

enum _SmartFilter { all, active, inactive, timeRestricted, containers }

class _FilterHeader {
  final String categoryId;
  final String filterName;
  _FilterHeader({required this.categoryId, required this.filterName});
}

class _SubFilterHeader {
  final String parentCategoryId;
  final String subFilterId;
  final String subFilterName;
  _SubFilterHeader(
      {required this.parentCategoryId,
      required this.subFilterId,
      required this.subFilterName});
}

class FranchiseeCatalogueView extends StatefulWidget {
  const FranchiseeCatalogueView({super.key});
  @override
  State<FranchiseeCatalogueView> createState() =>
      _FranchiseeCatalogueViewState();
}

class _FranchiseeCatalogueViewState extends State<FranchiseeCatalogueView> {
  String? _selectedBackOfficeFilterId;
  String? _selectedKioskFilterId;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  _SmartFilter _currentSmartFilter = _SmartFilter.all;
  List<ProductFilter> _allBackOfficeFilters = [];
  List<KioskCategory> _allKioskCategories = [];
  final Map<String, KioskFilter> _kioskFilterMap = {};
  final Map<String, String> _kioskFilterIdToCategoryId = {};
  final Map<String, KioskCategory> _kioskCategoryMap = {};
  bool _isLoadingFilters = true;
  _CatalogueMode _mode = _CatalogueMode.pricing;
  late DocumentReference _filterOrderRef;
  Map<String, List<String>> _customSubFilterOrder = {};
  late CollectionReference _subFilterOrderCollectionRef;
  List<dynamic> _displayList = [];
  bool _isSavingOrder = false;
  bool _isSavingFilterOrder = false;
  bool _isSavingSubFilterOrder = false;
  final Map<String, bool> _expansionState = {};
  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final franchiseeId = authProvider.firebaseUser?.uid;
    if (franchiseeId != null) {
      _filterOrderRef = FirebaseFirestore.instance
          .collection('users')
          .doc(franchiseeId)
          .collection('config')
          .doc('filterOrder');
      _subFilterOrderCollectionRef = FirebaseFirestore.instance
          .collection('users')
          .doc(franchiseeId)
          .collection('sub_filter_orders');
    } else {
      _filterOrderRef =
          FirebaseFirestore.instance.collection('dummy').doc('dummy');
      _subFilterOrderCollectionRef =
          FirebaseFirestore.instance.collection('dummy');
    }
    _loadAndCacheFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadAndCacheFilters() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.franchiseUser?.franchisorId == null) return;
    final franchisorId = authProvider.franchiseUser!.franchisorId!;
    final repository = FranchiseRepository();
    List<String>? loadedFilterOrder;
    Map<String, List<String>> loadedSubFilterOrders = {};
    try {
      final orderSnapshot = await _filterOrderRef.get();
      if (orderSnapshot.exists && orderSnapshot.data() != null) {
        final data = orderSnapshot.data() as Map<String, dynamic>;
        if (data['order'] is List) {
          loadedFilterOrder =
              List<String>.from((data['order'] as List).whereType<String>());
        }
      }
      final subOrderSnapshots = await _subFilterOrderCollectionRef.get();
      for (var doc in subOrderSnapshots.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['order'] is List) {
          loadedSubFilterOrders[doc.id] =
              List<String>.from((data['order'] as List).whereType<String>());
        }
      }
    } catch (e) {
      debugPrint("Erreur lors du chargement des ordres: $e");
    }
    final results = await Future.wait([
      repository.getFiltersStream(franchisorId).first,
      repository.getKioskCategoriesStream(franchisorId).first,
    ]);
    if (mounted) {
      final filters = results[0] as List<ProductFilter>;
      final kioskCategories = results[1] as List<KioskCategory>;
      _kioskFilterMap.clear();
      _kioskFilterIdToCategoryId.clear();
      _kioskCategoryMap.clear();
      for (var cat in kioskCategories) {
        _kioskCategoryMap[cat.id] = cat;
        for (var filter in cat.filters) {
          _kioskFilterMap[filter.id] = filter;
          _kioskFilterIdToCategoryId[filter.id] = cat.id;
        }
      }
      List<KioskCategory> sortedCategories = List.from(kioskCategories);
      if (loadedFilterOrder != null && loadedFilterOrder.isNotEmpty) {
        final categoryMap = {for (var c in kioskCategories) c.id: c};
        final orderedCategories = <KioskCategory>[];
        for (final categoryId in loadedFilterOrder) {
          if (categoryId.isNotEmpty && categoryMap.containsKey(categoryId)) {
            orderedCategories.add(categoryMap[categoryId]!);
            categoryMap.remove(categoryId);
          }
        }
        List<KioskCategory> remaining = categoryMap.values.toList();
        remaining.sort((a, b) => a.position.compareTo(b.position));
        orderedCategories.addAll(remaining);
        sortedCategories = orderedCategories;
      } else {
        sortedCategories.sort((a, b) => a.position.compareTo(b.position));
      }
      List<ProductFilter> sortedFilters = List.from(filters);
      sortedFilters.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _customSubFilterOrder = loadedSubFilterOrders;
        _allBackOfficeFilters = sortedFilters;
        _allKioskCategories = sortedCategories;
        _isLoadingFilters = false;
        for (var cat in _allKioskCategories) {
          _expansionState.putIfAbsent(cat.id, () => false);
        }
        _expansionState.putIfAbsent('null', () => false);
      });
    }
  }

  Future<void> _saveOrder(CollectionReference menuRef) async {
    if (_isSavingOrder) return;
    setState(() => _isSavingOrder = true);
    final batch = FirebaseFirestore.instance.batch();
    final currentFlatProductOrder =
        <({MasterProduct product, FranchiseeMenuItem settings})>[];
    for (var item in _displayList) {
      if (item is ({MasterProduct product, FranchiseeMenuItem settings})) {
        currentFlatProductOrder.add(item);
      }
    }
    for (int i = 0; i < currentFlatProductOrder.length; i++) {
      final item = currentFlatProductOrder[i];
      final docRef = menuRef.doc(item.product.productId);
      batch.update(docRef, {'position': i});
    }
    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Ordre des produits sauvegardé."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur lors de la sauvegarde de l'ordre: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingOrder = false);
      }
    }
  }

  Future<void> _saveFilterOrder() async {
    if (_isSavingFilterOrder) return;
    setState(() => _isSavingFilterOrder = true);
    final currentCategoryOrder = _allKioskCategories.map((c) => c.id).toList();
    try {
      await _filterOrderRef
          .set({'order': currentCategoryOrder}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur sauvegarde ordre catégories: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingFilterOrder = false);
      }
    }
  }

  Future<void> _saveSubFilterOrder(
      String mainCategoryId, List<String> subFilterIds) async {
    if (_isSavingSubFilterOrder) return;
    setState(() => _isSavingSubFilterOrder = true);
    final docRef = _subFilterOrderCollectionRef.doc(mainCategoryId);
    try {
      await docRef.set({'order': subFilterIds}, SetOptions(merge: true));
      if (mounted) {
        _customSubFilterOrder[mainCategoryId] = subFilterIds;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur sauvegarde ordre sous-filtres: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSubFilterOrder = false);
      }
    }
  }

  void _prepareOrderModeData(List<MasterProduct> allMasterProducts,
      Map<String, FranchiseeMenuItem> franchiseeSettings) {
    var allVisibleProductsData = allMasterProducts
        .map((p) => (product: p, settings: franchiseeSettings[p.productId]))
        .where((item) => item.settings != null && item.settings!.isVisible)
        .map((item) => (product: item.product, settings: item.settings!))
        .toList();
    Map<
            String?,
            Map<String?,
                List<({MasterProduct product, FranchiseeMenuItem settings})>>>
        groupedProducts = {};
    for (var item in allVisibleProductsData) {
      if (item.product.kioskFilterIds.isEmpty) {
        groupedProducts
            .putIfAbsent(null, () => {})
            .putIfAbsent('none', () => [])
            .add(item);
      } else {
        for (var kioskFilterId in item.product.kioskFilterIds) {
          String? categoryId = _kioskFilterIdToCategoryId[kioskFilterId];
          groupedProducts
              .putIfAbsent(categoryId, () => {})
              .putIfAbsent(kioskFilterId, () => [])
              .add(item);
        }
      }
    }
    groupedProducts.forEach((mainCategoryId, subGroups) {
      subGroups.forEach((subFilterId, productList) {
        productList.sort((a, b) {
          int posCompare = a.settings.position.compareTo(b.settings.position);
          if (posCompare != 0) return posCompare;
          return a.product.name.compareTo(b.product.name);
        });
      });
    });
    _displayList = [];
    for (var category in _allKioskCategories) {
      if (groupedProducts.containsKey(category.id)) {
        _displayList.add(
            _FilterHeader(categoryId: category.id, filterName: category.name));
        if (_expansionState.putIfAbsent(category.id, () => false)) {
          final subGroups = groupedProducts[category.id]!;
          List<String> subFilterOrder =
              _customSubFilterOrder[category.id] ?? [];
          List<String> availableSubFilterIds =
              subGroups.keys.where((id) => id != null).cast<String>().toList();
          final subGroupMap = Map.from(subGroups);
          List<String> sortedSubFilterIds = [];
          Set<String> addedSubFilterIds = {};
          for (String sfId in subFilterOrder) {
            if (availableSubFilterIds.contains(sfId)) {
              sortedSubFilterIds.add(sfId);
              addedSubFilterIds.add(sfId);
            }
          }
          availableSubFilterIds.sort((a, b) {
            String nameA =
                _kioskFilterMap[a]?.name ?? (a == 'none' ? 'Autres' : a);
            String nameB =
                _kioskFilterMap[b]?.name ?? (b == 'none' ? 'Autres' : b);
            return nameA.compareTo(nameB);
          });
          for (String sfId in availableSubFilterIds) {
            if (!addedSubFilterIds.contains(sfId)) {
              sortedSubFilterIds.add(sfId);
            }
          }
          if (subGroupMap.containsKey('none') &&
              !sortedSubFilterIds.contains('none')) {
            sortedSubFilterIds.add('none');
          }
          for (String subFilterId in sortedSubFilterIds) {
            final productList = subGroupMap[subFilterId]!;
            if (productList.isNotEmpty) {
              String subFilterName = _kioskFilterMap[subFilterId]?.name ??
                  (subFilterId == 'none' ? 'Autres' : 'Inconnu');
              _displayList.add(_SubFilterHeader(
                  parentCategoryId: category.id,
                  subFilterId: subFilterId,
                  subFilterName: subFilterName));
              final subFilterKey = '${category.id}_$subFilterId';
              if (_expansionState.putIfAbsent(subFilterKey, () => false)) {
                _displayList.addAll(productList);
              }
            }
          }
        }
      }
    }
    if (groupedProducts.containsKey(null)) {
      _displayList
          .add(_FilterHeader(categoryId: 'null', filterName: "Non classés"));
      final unclassifiedProductsMap = groupedProducts[null]!;
      final unclassifiedProducts =
          unclassifiedProductsMap.values.expand((list) => list).toList();
      if (_expansionState.putIfAbsent('null', () => false)) {
        _displayList.addAll(unclassifiedProducts);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    if (authProvider.franchiseUser?.franchisorId == null ||
        authProvider.firebaseUser?.uid == null) {
      return const Center(
          child: Text("Erreur: Données utilisateur introuvables."));
    }
    final franchisorId = authProvider.franchiseUser!.franchisorId!;
    final franchiseeId = authProvider.firebaseUser!.uid;
    final repository = FranchiseRepository();
    final franchiseeMenuRef = FirebaseFirestore.instance
        .collection('users')
        .doc(franchiseeId)
        .collection('menu');
    Map<String, FranchiseeMenuItem> currentFranchiseeSettings = {};
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text("Gestion Catalogue",
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        bottom: PreferredSize(
          preferredSize:
              Size.fromHeight(_mode == _CatalogueMode.pricing ? 140 : 60),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildModeToggle(),
              ),
              const SizedBox(height: 8),
              if (_mode == _CatalogueMode.pricing) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un produit...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = "");
                                _searchFocusNode.unfocus();
                              })
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 16),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val.toLowerCase());
                    },
                  ),
                ),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSmartFilterChip("Tout", _SmartFilter.all),
                      const SizedBox(width: 8),
                      _buildSmartFilterChip("Dossiers", _SmartFilter.containers,
                          icon: Icons.folder, color: Colors.indigo),
                      const SizedBox(width: 8),
                      _buildSmartFilterChip("Actifs", _SmartFilter.active,
                          icon: Icons.check_circle_outline,
                          color: Colors.green),
                      const SizedBox(width: 8),
                      _buildSmartFilterChip("Inactifs", _SmartFilter.inactive,
                          icon: Icons.cancel_outlined, color: Colors.grey),
                      const SizedBox(width: 8),
                      _buildSmartFilterChip(
                          "Horaires", _SmartFilter.timeRestricted,
                          icon: Icons.schedule, color: Colors.blue),
                      const VerticalDivider(width: 20),
                      if (_allBackOfficeFilters.isNotEmpty) ...[
                        const Center(
                            child: Text("Rayons: ",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey))),
                        const SizedBox(width: 8),
                        ..._allBackOfficeFilters.map((f) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f.name),
                                selected: _selectedBackOfficeFilterId == f.id,
                                onSelected: (sel) {
                                  setState(() {
                                    _selectedBackOfficeFilterId =
                                        sel ? f.id : null;
                                    _selectedKioskFilterId = null;
                                  });
                                },
                              ),
                            )),
                      ]
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: StreamBuilder<List<MasterProduct>>(
              stream: repository.getMasterProductsStream(franchisorId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    _isLoadingFilters) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text("Le catalogue du franchiseur est vide."));
                }
                List<MasterProduct> allRawProducts = snapshot.data!;
                List<MasterProduct> visibleProducts = allRawProducts
                    .where((product) => !product.isIngredient)
                    .toList();
                return StreamBuilder<QuerySnapshot>(
                  stream: franchiseeMenuRef.snapshots(),
                  builder: (context, menuSnapshot) {
                    if (menuSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    currentFranchiseeSettings =
                        Map<String, FranchiseeMenuItem>.fromEntries(
                      (menuSnapshot.data?.docs ?? []).map(
                        (doc) => MapEntry(
                          doc.id,
                          FranchiseeMenuItem.fromFirestore(
                              doc.data() as Map<String, dynamic>),
                        ),
                      ),
                    );
                    if (_mode == _CatalogueMode.ordering) {
                      return _buildOrderView(franchiseeMenuRef, visibleProducts,
                          currentFranchiseeSettings);
                    }
                    List<MasterProduct> filteredProducts = visibleProducts;
                    if (_searchQuery.isNotEmpty) {
                      filteredProducts = filteredProducts
                          .where((p) =>
                              p.name.toLowerCase().contains(_searchQuery))
                          .toList();
                    }
                    if (_currentSmartFilter == _SmartFilter.active) {
                      filteredProducts = filteredProducts
                          .where((p) =>
                              currentFranchiseeSettings[p.productId]
                                  ?.isVisible ==
                              true)
                          .toList();
                    } else if (_currentSmartFilter == _SmartFilter.inactive) {
                      filteredProducts = filteredProducts
                          .where((p) =>
                              currentFranchiseeSettings[p.productId]
                                  ?.isVisible !=
                              true)
                          .toList();
                    } else if (_currentSmartFilter ==
                        _SmartFilter.timeRestricted) {
                      filteredProducts = filteredProducts.where((p) {
                        final s = currentFranchiseeSettings[p.productId];
                        return s != null && s.availableStartTime != null;
                      }).toList();
                    } else if (_currentSmartFilter == _SmartFilter.containers) {
                      filteredProducts =
                          filteredProducts.where((p) => p.isContainer).toList();
                    }
                    if (_selectedBackOfficeFilterId != null) {
                      filteredProducts = filteredProducts
                          .where((p) =>
                              p.filterIds.contains(_selectedBackOfficeFilterId))
                          .toList();
                    }
                    if (_selectedKioskFilterId != null) {
                      filteredProducts = filteredProducts
                          .where((p) =>
                              p.kioskFilterIds.contains(_selectedKioskFilterId))
                          .toList();
                    }
                    if (filteredProducts.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text("Aucun produit ne correspond.",
                                textAlign: TextAlign.center),
                          ],
                        ),
                      );
                    }
                    return _buildPriceView(
                        filteredProducts,
                        currentFranchiseeSettings,
                        franchiseeMenuRef,
                        allRawProducts);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartFilterChip(String label, _SmartFilter value,
      {IconData? icon, Color? color}) {
    final isSelected = _currentSmartFilter == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: isSelected ? Colors.white : color),
            const SizedBox(width: 6)
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(
            () => _currentSmartFilter = selected ? value : _SmartFilter.all);
      },
      backgroundColor: Colors.white,
      selectedColor: color ?? Theme.of(context).primaryColor,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.grey.shade300)),
      showCheckmark: false,
    );
  }

  Widget _buildModeToggle() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_CatalogueMode>(
        segments: const [
          ButtonSegment(
            value: _CatalogueMode.pricing,
            label: Text("Catalogue & Prix"),
            icon: Icon(Icons.edit_note),
          ),
          ButtonSegment(
            value: _CatalogueMode.ordering,
            label: Text("Ordre d'affichage"),
            icon: Icon(Icons.sort),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (newSelection) {
          setState(() {
            _mode = newSelection.first;
            _searchController.clear();
            _searchQuery = "";
            _searchFocusNode.unfocus();
          });
        },
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildPriceView(
      List<MasterProduct> productsToDisplay,
      Map<String, FranchiseeMenuItem> franchiseeSettings,
      CollectionReference franchiseeMenuRef,
      List<MasterProduct> allMasterProducts) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final franchiseeId = authProvider.firebaseUser?.uid;
    final franchisorId = authProvider.franchiseUser?.franchisorId;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: productsToDisplay.length,
      itemBuilder: (context, index) {
        final product = productsToDisplay[index];
        final settings = franchiseeSettings[product.productId];
        return FranchiseeProductCard(
          product: product,
          settings: settings ??
              FranchiseeMenuItem(
                  masterProductId: product.productId,
                  price: product.price),
          franchiseeId: franchiseeId!,
          franchisorId: franchisorId!,
          franchiseeMenuRef: franchiseeMenuRef,
          onTapConfig: () {
            _showPriceDialog(context, franchiseeMenuRef, product, settings,
                isComposite: product.isComposite,
                isContainer: product.isContainer,
                franchiseeId: franchiseeId,
                franchisorId: franchisorId,
                allProducts: allMasterProducts,
                franchiseeSettings: franchiseeSettings);
          },
          onConfirmDisable: () {
            _confirmDisable(context, franchiseeMenuRef, product, settings);
          },
          onToggleStock: (bool newValue) {
            franchiseeMenuRef
                .doc(product.productId)
                .set({'isAvailable': newValue}, SetOptions(merge: true));
          },
          onToggleVisibility: (bool newValue) {
            franchiseeMenuRef
                .doc(product.productId)
                .set({'isVisible': newValue}, SetOptions(merge: true));
          },
        );
      },
    );
  }

  Future<void> _saveChildProductPrice(CollectionReference menuRef,
      MasterProduct product, double newPrice) async {
    try {
      await menuRef.doc(product.productId).set({
        'masterProductId': product.productId,
        'price': newPrice,
        'isActive': true,
        'isVisible': true,
        'isAvailable': true,
        'name': product.name,
        'isContainer': product.isContainer,
        'containerProductIds': product.containerProductIds,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Prix mis à jour : ${newPrice.toStringAsFixed(2)} €"),
          duration: const Duration(milliseconds: 800),
        ));
      }
    } catch (e) {
      debugPrint("Erreur sauvegarde prix enfant: $e");
    }
  }

  Future<void> _confirmDisable(
      BuildContext context,
      CollectionReference menuRef,
      MasterProduct product,
      FranchiseeMenuItem? settings) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Désactiver et Réinitialiser ?"),
        content: const Text(
            "Désactiver ce produit supprimera également tous ses prix et ordres personnalisés.\n\nContinuer ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text("Confirmer", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final mainDocRef = menuRef.doc(product.productId);
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
          mainDocRef,
          {
            'isVisible': false,
            'isAvailable': false,
            'position': settings?.position ?? 0
          },
          SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildOrderView(
      CollectionReference franchiseeMenuRef,
      List<MasterProduct> allMasterProducts,
      Map<String, FranchiseeMenuItem> franchiseeSettings) {
    if (_isLoadingFilters) {
      return const Center(
          child: CircularProgressIndicator(key: Key("order_view_loader")));
    }
    if (_isSavingOrder || _isSavingFilterOrder || _isSavingSubFilterOrder) {
      return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text("Sauvegarde...")
      ]));
    }
    _prepareOrderModeData(allMasterProducts, franchiseeSettings);
    if (_displayList.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                  "Aucun produit visible pour l'organisation.\nActivez des produits depuis l'onglet 'Catalogue & Prix' d'abord.",
                  textAlign: TextAlign.center)));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
      itemCount: _displayList.length,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final item = _displayList[index];
        if (item is _FilterHeader) {
          bool isExpanded =
              _expansionState.putIfAbsent(item.categoryId, () => false);
          return ReorderableDragStartListener(
            key: ValueKey('header_${item.categoryId}'),
            index: index,
            child: ExpansionTile(
              key: PageStorageKey<String>('expansion_${item.categoryId}'),
              initiallyExpanded: isExpanded,
              maintainState: true,
              collapsedBackgroundColor: Colors.grey[200],
              backgroundColor: Colors.grey[100],
              leading: const Icon(Icons.drag_handle),
              title: Text(item.filterName,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Theme.of(context).primaryColorDark)),
              onExpansionChanged: (bool expanded) {
                setState(() {
                  _expansionState[item.categoryId] = expanded;
                  _prepareOrderModeData(allMasterProducts, franchiseeSettings);
                });
              },
              children: const <Widget>[],
            ),
          );
        } else if (item is _SubFilterHeader) {
          final subFilterKey = '${item.parentCategoryId}_${item.subFilterId}';
          bool isExpanded =
              _expansionState.putIfAbsent(subFilterKey, () => false);
          return ReorderableDragStartListener(
            key: ValueKey('subheader_$subFilterKey'),
            index: index,
            child: Container(
              padding: const EdgeInsets.only(left: 16.0),
              child: ExpansionTile(
                key: PageStorageKey<String>('expansion_$subFilterKey'),
                initiallyExpanded: isExpanded,
                maintainState: true,
                leading: const Icon(Icons.drag_handle, size: 20),
                title: Text(item.subFilterName,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[800])),
                onExpansionChanged: (bool expanded) {
                  setState(() {
                    _expansionState[subFilterKey] = expanded;
                    _prepareOrderModeData(
                        allMasterProducts, franchiseeSettings);
                  });
                },
                children: const <Widget>[],
              ),
            ),
          );
        } else if (item is ({
          MasterProduct product,
          FranchiseeMenuItem settings
        })) {
          final bool isAvailable = item.settings.isAvailable;
          return ReorderableDragStartListener(
            key: ValueKey(item.product.productId),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(left: 32.0, bottom: 4.0, top: 4.0),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0.5,
                color: isAvailable ? Colors.white : Colors.red.shade50,
                child: ListTile(
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.drag_handle, color: Colors.grey),
                  title: Text(item.product.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color:
                              isAvailable ? Colors.black : Colors.grey.shade700,
                          decoration: isAvailable
                              ? TextDecoration.none
                              : TextDecoration.lineThrough)),
                  trailing: Text(
                      "${(item.settings.price ?? item.product.price ?? 0.0).toStringAsFixed(2)} €",
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          );
        }
        return SizedBox(key: ValueKey('unknown_$index'));
      },
      onReorder: (int oldDisplayIndex, int newDisplayIndex) {
        if (newDisplayIndex > oldDisplayIndex) {
          newDisplayIndex -= 1;
        }
        final dynamic movedItem = _displayList.removeAt(oldDisplayIndex);
        _displayList.insert(newDisplayIndex, movedItem);
        setState(() {});
        if (movedItem is _FilterHeader) {
          _saveFilterOrder();
        } else if (movedItem is _SubFilterHeader) {
          _saveSubFilterOrder(movedItem.parentCategoryId, []);
        } else if (movedItem is ({
          MasterProduct product,
          FranchiseeMenuItem settings
        })) {
          _saveOrder(franchiseeMenuRef);
        }
      },
    );
  }

  void _showPriceDialog(BuildContext context, CollectionReference menuRef,
      MasterProduct product, FranchiseeMenuItem? currentSettings,
      {bool isComposite = false,
      bool isContainer = false,
      required String franchiseeId,
      required String franchisorId,
      List<MasterProduct>? allProducts,
      Map<String, FranchiseeMenuItem>? franchiseeSettings}) {
    final String initialPrice = currentSettings?.price?.toStringAsFixed(2) ?? '';
    final priceController = TextEditingController(text: initialPrice);
    final Map<String, TextEditingController> optionControllers = {};
    for (var opt in product.options) {
      double? existingPrice = currentSettings?.optionPrices[opt.id];
      optionControllers[opt.id] = TextEditingController(
          text: existingPrice != null ? existingPrice.toStringAsFixed(2) : "");
    }
    final List<double> vatRates = [5.5, 10.0, 20.0];
    double selectedVat = currentSettings?.vatRate ?? 10.0;
    double selectedTakeawayVat = currentSettings?.takeawayVatRate ?? 5.5;
    bool hidePrice = currentSettings?.hidePriceOnCard ?? false;
    final bool showCompositionBtn = isComposite ||
        product.sectionIds.isNotEmpty ||
        product.ingredientProductIds.isNotEmpty;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    if (currentSettings?.availableStartTime != null) {
      final parts = currentSettings!.availableStartTime!.split(':');
      startTime =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    if (currentSettings?.availableEndTime != null) {
      final parts = currentSettings!.availableEndTime!.split(':');
      endTime =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> selectTime(bool isStart) async {
              final picked = await showTimePicker(
                  context: context,
                  initialTime: (isStart ? startTime : endTime) ??
                      const TimeOfDay(hour: 12, minute: 0));
              if (picked != null) {
                setStateDialog(() {
                  if (isStart) {
                    startTime = picked;
                  } else {
                    endTime = picked;
                  }
                });
              }
            }

            return SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showCompositionBtn && !isContainer) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          icon: const Icon(Icons.restaurant_menu),
                          label: const Text(
                              "Gérer la composition (Prix & Ingrédients)",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  FranchiseeCompositeOverridesDialog(
                                franchiseeId: franchiseeId,
                                franchisorId: franchisorId,
                                product: product,
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 20),
                    ],
                    if (isContainer) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          icon: const Icon(Icons.folder_open),
                          label: const Text("Gérer le contenu du dossier",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => FranchiseeContainerConfigDialog(
                                containerProduct: product,
                                allProducts: allProducts ?? [],
                                franchiseeSettings: franchiseeSettings ?? {},
                                onUpdateChildPrice: (child, newPrice) {},
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 20),
                    ],
                    Text("Prix et Taxes",
                        style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: priceController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: "Prix TTC (€)",
                        hintText:
                            "Conseillé : ${product.price?.toStringAsFixed(2) ?? '0.00'} €",
                        helperText: "Laissez vide pour le prix franchiseur",
                        prefixIcon: const Icon(Icons.euro),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          tooltip: "Effacer pour revenir au prix franchiseur",
                          onPressed: () => priceController.clear(),
                        ),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: DropdownButtonFormField<double>(
                                initialValue: vatRates.contains(selectedVat)
                                    ? selectedVat
                                    : null,
                                items: vatRates
                                    .map((r) => DropdownMenuItem(
                                        value: r, child: Text("$r%")))
                                    .toList(),
                                onChanged: (v) =>
                                    setStateDialog(() => selectedVat = v!),
                                decoration: const InputDecoration(
                                    labelText: "TVA Place",
                                    border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: DropdownButtonFormField<double>(
                                initialValue:
                                    vatRates.contains(selectedTakeawayVat)
                                        ? selectedTakeawayVat
                                        : null,
                                items: vatRates
                                    .map((r) => DropdownMenuItem(
                                        value: r, child: Text("$r%")))
                                    .toList(),
                                onChanged: (v) => setStateDialog(
                                    () => selectedTakeawayVat = v!),
                                decoration: const InputDecoration(
                                    labelText: "TVA Emp.",
                                    border: OutlineInputBorder()))),
                      ],
                    ),
                    SwitchListTile(
                        title: const Text("Masquer prix (Carte)"),
                        value: hidePrice,
                        onChanged: (v) => setStateDialog(() => hidePrice = v),
                        contentPadding: EdgeInsets.zero),
                    const Divider(height: 24),
                    Text("Disponibilité",
                        style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                              icon: const Icon(Icons.start),
                              onPressed: () => selectTime(true),
                              label:
                                  Text(startTime?.format(context) ?? "Début"))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton.icon(
                              icon: const Icon(Icons.stop),
                              onPressed: () => selectTime(false),
                              label: Text(endTime?.format(context) ?? "Fin"))),
                    ]),
                    if (startTime != null || endTime != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => setStateDialog(() {
                            startTime = null;
                            endTime = null;
                          }),
                          icon: const Icon(Icons.delete,
                              color: Colors.red, size: 16),
                          label: const Text("Effacer horaires",
                              style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    const Divider(height: 24),
                    if (product.options.isNotEmpty) ...[
                      Text("Options / Suppléments",
                          style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ...product.options.map((opt) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(opt.name,
                                      style: const TextStyle(fontSize: 14))),
                              SizedBox(
                                width: 100,
                                child: TextFormField(
                                  controller: optionControllers[opt.id],
                                  decoration: const InputDecoration(
                                    labelText: "Prix €",
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    hintText: "0.00",
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () async {
                final String rawText =
                    priceController.text.replaceAll(',', '.').trim();
                final double? parsedPrice = double.tryParse(rawText);
                if (parsedPrice != null && parsedPrice < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Erreur : Le prix ne peut pas être inférieur à zéro."),
                        backgroundColor: Colors.red),
                  );
                  return; // On arrête l'exécution ici
                }

                String? startStr = startTime != null
                    ? "${startTime!.hour}:${startTime!.minute.toString().padLeft(2, '0')}"
                    : null;
                String? endStr = endTime != null
                    ? "${endTime!.hour}:${endTime!.minute.toString().padLeft(2, '0')}"
                    : null;
                Map<String, double> newOptionPrices = {};
                optionControllers.forEach((key, controller) {
                  final String optText =
                      controller.text.replaceAll(',', '.').trim();
                  if (optText.isNotEmpty) {
                    double? val = double.tryParse(optText);
                    if (val != null) newOptionPrices[key] = val;
                  }
                });
                final Map<String, dynamic> data = {
                  'vatRate': selectedVat,
                  'takeawayVatRate': selectedTakeawayVat,
                  'hidePriceOnCard': hidePrice,
                  'availableStartTime': startStr,
                  'availableEndTime': endStr,
                  'optionPrices': newOptionPrices,
                  'masterProductId': product.productId,
                  'isVisible': true,
                  'isAvailable': true,
                  'isContainer': isContainer,
                  'containerProductIds': product.containerProductIds,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                if (rawText.isEmpty) {
                  data['price'] = FieldValue.delete();
                } else {
                  data['price'] = parsedPrice ?? 0.0;
                }
                await menuRef
                    .doc(product.productId)
                    .set(data, SetOptions(merge: true));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(rawText.isEmpty
                            ? "Prix réinitialisé au prix franchiseur"
                            : "Prix mis à jour")),
                  );
                }
              },
              child: const Text("Enregistrer")),
        ],
      ),
    );
  }
}

class FranchiseeProductCard extends StatelessWidget {
  final MasterProduct product;
  final FranchiseeMenuItem settings;
  final String franchiseeId;
  final String franchisorId;
  final CollectionReference franchiseeMenuRef;
  final VoidCallback onTapConfig;
  final VoidCallback onConfirmDisable;
  final Function(bool) onToggleStock;
  final Function(bool) onToggleVisibility;
  const FranchiseeProductCard({
    super.key,
    required this.product,
    required this.settings,
    required this.franchiseeId,
    required this.franchisorId,
    required this.franchiseeMenuRef,
    required this.onTapConfig,
    required this.onConfirmDisable,
    required this.onToggleStock,
    required this.onToggleVisibility,
  });
  @override
  Widget build(BuildContext context) {
    final bool isVisible = settings.isVisible;
    final bool isAvailable = settings.isAvailable;
    final bool hasHours = settings.availableStartTime != null;
    final String? imageUrl = product.photoUrl;
    Color accentColor = Theme.of(context).primaryColor;
    IconData fallbackIcon = Icons.fastfood;
    String typeLabel = "";
    Color cardColor = isVisible ? Colors.white : Colors.grey.shade50;
    if (product.isContainer) {
      accentColor = Colors.indigo;
      fallbackIcon = Icons.folder;
      typeLabel = "Dossier";
      if (isVisible) cardColor = Colors.indigo.shade50;
    } else if (product.isComposite) {
      accentColor = Colors.orange.shade800;
      fallbackIcon = Icons.restaurant_menu;
      typeLabel = "Menu";
    }
    final bool hasComposition = product.isComposite ||
        product.sectionIds.isNotEmpty ||
        product.ingredientProductIds.isNotEmpty;
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: isVisible ? Colors.transparent : Colors.grey.shade300,
            width: 1),
      ),
      color: cardColor,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 110,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              _buildPlaceholder(accentColor, fallbackIcon),
                          errorWidget: (context, url, error) =>
                              _buildPlaceholder(accentColor, fallbackIcon,
                                  isMissing: true),
                        )
                      else
                        _buildPlaceholder(accentColor, fallbackIcon,
                            isMissing: true),
                      if (!isVisible)
                        Container(
                          color: Colors.white.withValues(alpha: 0.85),
                          alignment: Alignment.center,
                          child: const Chip(
                              label: Text("MASQUÉ",
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold))),
                        )
                      else if (!isAvailable)
                        Container(
                          color: Colors.black.withValues(alpha: 0.6),
                          alignment: Alignment.center,
                          child: const Icon(Icons.remove_shopping_cart,
                              color: Colors.white, size: 30),
                        ),
                      if (typeLabel.isNotEmpty)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: const BorderRadius.only(
                                    bottomRight: Radius.circular(10))),
                            child: Text(typeLabel.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isVisible
                                        ? Colors.black87
                                        : Colors.grey),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Switch(
                              value: isVisible,
                              activeThumbColor: Colors.green,
                              onChanged: (val) => val
                                  ? onToggleVisibility(true)
                                  : onConfirmDisable(),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (!product.isContainer)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: isVisible
                                    ? Colors.blueGrey.shade50
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              "${(settings.price ?? product.price ?? 0.0).toStringAsFixed(2)} €",
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: isVisible ? accentColor : Colors.grey),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (hasHours)
                              _DetailChip(
                                  icon: Icons.schedule,
                                  label:
                                      "${settings.availableStartTime} - ${settings.availableEndTime}",
                                  color: Colors.blue.shade700,
                                  bgColor: Colors.blue.shade50),
                            if (isVisible)
                              isAvailable
                                  ? _DetailChip(
                                      icon: Icons.check,
                                      label: "En Stock",
                                      color: Colors.green.shade700,
                                      bgColor: Colors.green.shade50)
                                  : _DetailChip(
                                      icon: Icons.block,
                                      label: "Épuisé",
                                      color: Colors.red.shade700,
                                      bgColor: Colors.red.shade50),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isVisible) ...[
            const Divider(height: 1),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: onTapConfig,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                product.isContainer
                                    ? Icons.folder_open
                                    : (hasComposition
                                        ? Icons.restaurant_menu
                                        : Icons.settings_outlined),
                                size: 20,
                                color: hasComposition
                                    ? Colors.orange.shade800
                                    : Colors.grey.shade800),
                            const SizedBox(width: 8),
                            Text(
                                product.isContainer
                                    ? "OUVRIR DOSSIER"
                                    : (hasComposition
                                        ? "COMPOSITION & PRIX"
                                        : "PRIX & CONFIG"),
                                style: TextStyle(
                                    color: hasComposition
                                        ? Colors.orange.shade800
                                        : Colors.grey.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(
                      width: 1,
                      indent: 8,
                      endIndent: 8,
                      color: Colors.grey.shade300),
                  Expanded(
                    flex: 1,
                    child: InkWell(
                      onTap: () => onToggleStock(!isAvailable),
                      child: Container(
                        color: isAvailable
                            ? Colors.transparent
                            : Colors.orange.shade50,
                        alignment: Alignment.center,
                        child: Text(
                          isAvailable ? "Mettre en Rupture" : "Restocker",
                          style: TextStyle(
                            color: isAvailable
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPlaceholder(Color color, IconData icon,
      {bool isMissing = false}) {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isMissing ? Icons.image_not_supported : icon,
                size: 30, color: color.withValues(alpha: 0.4)),
            if (isMissing)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("No Image",
                      style:
                          TextStyle(fontSize: 9, color: Colors.grey.shade500))),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  const _DetailChip(
      {required this.icon,
      required this.label,
      required this.color,
      required this.bgColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
