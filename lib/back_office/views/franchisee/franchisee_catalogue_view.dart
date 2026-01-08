import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
import 'franchisee_product_card.dart';

enum _CatalogueMode { ordering, pricing }

enum _SmartFilter { all, active, inactive, timeRestricted }

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
  String _searchQuery = "";
  _SmartFilter _currentSmartFilter = _SmartFilter.all;

  List<ProductFilter> _allBackOfficeFilters = [];
  List<KioskCategory> _allKioskCategories = [];
  Map<String, KioskFilter> _kioskFilterMap = {};
  Map<String, String> _kioskFilterIdToCategoryId = {};
  Map<String, KioskCategory> _kioskCategoryMap = {};

  bool _isLoadingFilters = true;
  _CatalogueMode _mode = _CatalogueMode.ordering;

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
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

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
          _kioskFilterMap[filter.id] = filter as KioskFilter;
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
      if (mounted) {
      }
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<List<MasterProduct>>(
            stream: repository.getMasterProductsStream(franchisorId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting ||
                  _isLoadingFilters) {
                return const Expanded(
                    child: Center(child: CircularProgressIndicator()));
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                if (_mode == _CatalogueMode.ordering) {
                  return Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                          stream: franchiseeMenuRef.snapshots(),
                          builder: (context, menuSnapshot) {
                            if (menuSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
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
                            if (!_isLoadingFilters) {
                              _prepareOrderModeData(
                                  [], currentFranchiseeSettings);
                            }
                            return Column(
                              children: [
                                _buildModeToggle(),
                                const Divider(height: 1, thickness: 1),
                                _buildOrderView(franchiseeMenuRef, [],
                                    currentFranchiseeSettings)
                              ],
                            );
                          }));
                }
                return const Expanded(
                    child: Center(
                        child: Text("Le catalogue du franchiseur est vide.")));
              }

              List<MasterProduct> masterProducts = snapshot.data!
                  .where((product) => !product.isIngredient)
                  .toList();

              return Expanded(
                child: StreamBuilder<QuerySnapshot>(
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

                    List<MasterProduct> filteredProducts = masterProducts;

                    if (_searchQuery.isNotEmpty) {
                      filteredProducts = filteredProducts
                          .where((p) =>
                              p.name.toLowerCase().contains(_searchQuery))
                          .toList();
                    }

                    if (_mode == _CatalogueMode.pricing) {
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
                          return s != null &&
                              s.availableStartTime != null &&
                              s.availableEndTime != null;
                        }).toList();
                      }
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

                    if (_mode == _CatalogueMode.ordering) {
                      if (!_isLoadingFilters) {
                        _prepareOrderModeData(
                            masterProducts, currentFranchiseeSettings);
                      } else {
                        return const Center(
                            child: CircularProgressIndicator(
                                key: Key("inner_loader")));
                      }
                    }

                    return Column(
                      children: [
                        if (_mode == _CatalogueMode.pricing)
                          _buildEnhancedHeaderAndFilters(
                              repository, franchisorId, masterProducts),
                        _buildModeToggle(),
                        const Divider(height: 1, thickness: 1),
                        if (_mode == _CatalogueMode.ordering)
                          _buildOrderView(franchiseeMenuRef, masterProducts,
                              currentFranchiseeSettings)
                        else if (filteredProducts.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 48, color: Colors.grey),
                                    SizedBox(height: 16),
                                    Text(
                                        "Aucun produit ne correspond à votre recherche.",
                                        textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          _buildPriceView(filteredProducts,
                              currentFranchiseeSettings, franchiseeMenuRef),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedHeaderAndFilters(FranchiseRepository repository,
      String franchisorId, List<MasterProduct> masterProducts) {
    final sellableProducts =
        masterProducts.where((p) => !p.isIngredient).toList();
    final relevantBackOfficeFilterIds =
        sellableProducts.expand((p) => p.filterIds).toSet();
    final relevantKioskFilterIds = (_selectedBackOfficeFilterId == null
            ? sellableProducts
            : sellableProducts.where(
                (p) => p.filterIds.contains(_selectedBackOfficeFilterId)))
        .expand((p) => p.kioskFilterIds)
        .toSet();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un produit...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchController.clear())
                  : null,
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSmartFilterChip("Tout", _SmartFilter.all),
                const SizedBox(width: 8),
                _buildSmartFilterChip("Actifs", _SmartFilter.active,
                    icon: Icons.check_circle_outline, color: Colors.green),
                const SizedBox(width: 8),
                _buildSmartFilterChip("Inactifs", _SmartFilter.inactive,
                    icon: Icons.cancel_outlined, color: Colors.grey),
                const SizedBox(width: 8),
                _buildSmartFilterChip(
                    "Horaires Restreints", _SmartFilter.timeRestricted,
                    icon: Icons.schedule, color: Colors.blue),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (relevantBackOfficeFilterIds.isNotEmpty) ...[
                  const Text("Rayons: ",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                ],
                _buildBackOfficeFilterSelector(relevantBackOfficeFilterIds),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (relevantKioskFilterIds.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text("Cat. Borne: ",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                  _buildKioskFilterSelector(relevantKioskFilterIds),
                ],
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_CatalogueMode>(
          segments: const [
            ButtonSegment(
              value: _CatalogueMode.ordering,
              label: Text("Ordre d'affichage"),
              icon: Icon(Icons.sort),
            ),
            ButtonSegment(
              value: _CatalogueMode.pricing,
              label: Text("Catalogue & Prix"),
              icon: Icon(Icons.edit_note),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (newSelection) {
            setState(() {
              _mode = newSelection.first;
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Widget _buildPriceView(
      List<MasterProduct> productsToDisplay,
      Map<String, FranchiseeMenuItem> franchiseeSettings,
      CollectionReference franchiseeMenuRef) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final franchiseeId = authProvider.firebaseUser?.uid;
    final franchisorId = authProvider.franchiseUser?.franchisorId;

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: productsToDisplay.length,
        itemBuilder: (context, index) {
          final product = productsToDisplay[index];
          final settings = franchiseeSettings[product.productId];

          return FranchiseeProductCard(
            product: product,
            settings: settings,
            franchiseeId: franchiseeId,
            franchisorId: franchisorId,
            franchiseeMenuRef: franchiseeMenuRef,
            // Action 1 : Clic sur la carte (Dialogue prix standard)
            onTapCard: () => _showPriceDialog(
                context, franchiseeMenuRef, product, settings,
                isComposite: product.isComposite),
            // Action 2 : Switch On/Off
            onToggleSwitch: (bool value) {
              if (value) {
                _showPriceDialog(context, franchiseeMenuRef, product, settings,
                    isComposite: product.isComposite);
              } else {
                _confirmDisable(context, franchiseeMenuRef, product, settings);
              }
            },
            // Action 3 : Gestion du stock (Dispo)
            onToggleStock: () {
              final isAvailable = settings?.isAvailable ?? true;
              franchiseeMenuRef
                  .doc(product.productId)
                  .set({'isAvailable': !isAvailable}, SetOptions(merge: true));
            },
          );
        },
      ),
    );
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
      final overridesColRef = mainDocRef.collection('supplement_overrides');
      final sectionOverridesColRef = mainDocRef.collection('section_overrides');

      final batch = FirebaseFirestore.instance.batch();
      final overridesSnapshot = await overridesColRef.get();
      for (final doc in overridesSnapshot.docs) batch.delete(doc.reference);

      final sectionOverridesSnapshot = await sectionOverridesColRef.get();
      for (final doc in sectionOverridesSnapshot.docs)
        batch.delete(doc.reference);

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

  Widget _buildBackOfficeFilterSelector(Set<String> relevantFilterIds) {
    final relevantFilters = _allBackOfficeFilters
        .where((f) => relevantFilterIds.contains(f.id))
        .toList();
    relevantFilters.sort((a, b) => a.name.compareTo(b.name));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChip(
          label: const Text("Tous"),
          selected: _selectedBackOfficeFilterId == null,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedBackOfficeFilterId = null;
                _selectedKioskFilterId = null;
              });
            }
          },
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 8),
        ...relevantFilters.map((filter) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(filter.name),
                selected: _selectedBackOfficeFilterId == filter.id,
                onSelected: (selected) {
                  setState(() {
                    _selectedBackOfficeFilterId = selected ? filter.id : null;
                    _selectedKioskFilterId = null;
                  });
                },
                visualDensity: VisualDensity.compact,
              ),
            )),
      ],
    );
  }

  Widget _buildKioskFilterSelector(Set<String> relevantKioskFilterIds) {
    final allKioskFilters =
        _allKioskCategories.expand((cat) => cat.filters).toList();
    final relevantFilters = allKioskFilters
        .where((f) => relevantKioskFilterIds.contains(f.id))
        .toList();
    relevantFilters.sort((a, b) => a.position.compareTo(b.position));

    return Row(
      children: [
        ChoiceChip(
          label: const Text("Toutes"),
          selected: _selectedKioskFilterId == null,
          onSelected: (selected) {
            if (selected) {
              setState(() => _selectedKioskFilterId = null);
            }
          },
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 8),
        ...relevantFilters.map((filter) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(filter.name),
                selected: _selectedKioskFilterId == filter.id,
                onSelected: (selected) {
                  setState(() =>
                      _selectedKioskFilterId = selected ? filter.id : null);
                },
                visualDensity: VisualDensity.compact,
              ),
            )),
      ],
    );
  }

  Widget _buildOrderView(
      CollectionReference franchiseeMenuRef,
      List<MasterProduct> allMasterProducts,
      Map<String, FranchiseeMenuItem> franchiseeSettings) {
    if (_isLoadingFilters) {
      return const Expanded(
          child: Center(
              child: CircularProgressIndicator(key: Key("order_view_loader"))));
    }
    if (_isSavingOrder || _isSavingFilterOrder || _isSavingSubFilterOrder) {
      return const Expanded(
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text("Sauvegarde...")
      ])));
    }
    _prepareOrderModeData(allMasterProducts, franchiseeSettings);

    if (_displayList.isEmpty) {
      return const Expanded(
          child: Center(
              child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                      "Aucun produit visible pour l'organisation.\nActivez des produits depuis l'onglet 'Catalogue & Prix' d'abord.",
                      textAlign: TextAlign.center))));
    }

    return Expanded(
      child: ReorderableListView.builder(
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
                    _prepareOrderModeData(
                        allMasterProducts, franchiseeSettings);
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
                padding:
                    const EdgeInsets.only(left: 32.0, bottom: 4.0, top: 4.0),
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
                            color: isAvailable
                                ? Colors.black
                                : Colors.grey.shade700,
                            decoration: isAvailable
                                ? TextDecoration.none
                                : TextDecoration.lineThrough)),
                    trailing: Text(
                        "${item.settings.price.toStringAsFixed(2)} €",
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

          if (movedItem is _FilterHeader) {
            final newCategoryOrder = <KioskCategory>[];
            final Set<String> currentDisplayCategoryIds = {};
            for (final item in _displayList) {
              if (item is _FilterHeader) {
                currentDisplayCategoryIds.add(item.categoryId);
                if (_kioskCategoryMap.containsKey(item.categoryId)) {
                  newCategoryOrder.add(_kioskCategoryMap[item.categoryId]!);
                }
              }
            }
            for (final category in _allKioskCategories) {
              if (!currentDisplayCategoryIds.contains(category.id)) {
                newCategoryOrder.add(category);
              }
            }
            setState(() {
              _allKioskCategories = newCategoryOrder;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _prepareOrderModeData(allMasterProducts, franchiseeSettings);
                setState(() {});
              }
            });
            _saveFilterOrder();
          } else if (movedItem is _SubFilterHeader) {
            String? currentMainCategoryId;
            for (int i = newDisplayIndex - 1; i >= 0; i--) {
              if (_displayList[i] is _FilterHeader) {
                currentMainCategoryId =
                    (_displayList[i] as _FilterHeader).categoryId;
                break;
              }
            }
            if (currentMainCategoryId == null ||
                movedItem.parentCategoryId != currentMainCategoryId) {
              _displayList.removeAt(newDisplayIndex);
              _displayList.insert(oldDisplayIndex, movedItem);
              setState(() {});
              return;
            }
            final String parentId = movedItem.parentCategoryId;
            final newSubFilterOrder = <String>[];
            for (final item in _displayList) {
              if (item is _SubFilterHeader &&
                  item.parentCategoryId == parentId) {
                newSubFilterOrder.add(item.subFilterId);
              }
            }
            setState(() {
              _customSubFilterOrder[parentId] = newSubFilterOrder;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _prepareOrderModeData(allMasterProducts, franchiseeSettings);
                  setState(() {});
                }
              });
            });
            _saveSubFilterOrder(parentId, newSubFilterOrder);
          } else if (movedItem is ({
            MasterProduct product,
            FranchiseeMenuItem settings
          })) {
            String? oldParentCatId;
            String? oldSubFilterId;
            for (int i = oldDisplayIndex; i >= 0; i--) {
              if (i == oldDisplayIndex) continue;
              if (_displayList[i] is _SubFilterHeader) {
                oldSubFilterId =
                    (_displayList[i] as _SubFilterHeader).subFilterId;
                oldParentCatId =
                    (_displayList[i] as _SubFilterHeader).parentCategoryId;
                break;
              } else if (_displayList[i] is _FilterHeader) {
                oldParentCatId = (_displayList[i] as _FilterHeader).categoryId;
                break;
              }
            }
            String? newParentCatId;
            String? newSubFilterId;
            for (int i = newDisplayIndex - 1; i >= 0; i--) {
              if (_displayList[i] is _SubFilterHeader) {
                newSubFilterId =
                    (_displayList[i] as _SubFilterHeader).subFilterId;
                newParentCatId =
                    (_displayList[i] as _SubFilterHeader).parentCategoryId;
                break;
              } else if (_displayList[i] is _FilterHeader) {
                newParentCatId = (_displayList[i] as _FilterHeader).categoryId;
                break;
              }
            }
            if (oldParentCatId != newParentCatId ||
                oldSubFilterId != newSubFilterId) {
              _displayList.removeAt(newDisplayIndex);
              _displayList.insert(oldDisplayIndex, movedItem);
              setState(() {});
              return;
            }
            setState(() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _prepareOrderModeData(allMasterProducts, franchiseeSettings);
                  setState(() {});
                }
              });
            });
            _saveOrder(franchiseeMenuRef);
          } else {
            _displayList.removeAt(newDisplayIndex);
            _displayList.insert(oldDisplayIndex, movedItem);
            setState(() {});
          }
        },
      ),
    );
  }

  void _showPriceDialog(BuildContext context, CollectionReference menuRef,
      MasterProduct product, FranchiseeMenuItem? currentSettings,
      {bool isComposite = false}) {
    final priceController = TextEditingController(
        text: currentSettings?.price.toStringAsFixed(2) ?? '0.00');
    final Map<String, TextEditingController> optionControllers = {};
    for (var opt in product.options) {
      double existingPrice = currentSettings?.optionPrices[opt.id] ?? 0.0;
      optionControllers[opt.id] =
          TextEditingController(text: existingPrice.toStringAsFixed(2));
    }

    final List<double> vatRates = [5.5, 10.0, 20.0];
    double selectedVat = currentSettings?.vatRate ?? 10.0;
    double selectedTakeawayVat = currentSettings?.takeawayVatRate ?? 5.5;

    final int position = currentSettings?.position ?? 0;

    TimeOfDay? startTime = currentSettings?.availableStartTime != null
        ? TimeOfDay(
            hour: int.parse(currentSettings!.availableStartTime!.split(':')[0]),
            minute:
                int.parse(currentSettings.availableStartTime!.split(':')[1]))
        : null;
    TimeOfDay? endTime = currentSettings?.availableEndTime != null
        ? TimeOfDay(
            hour: int.parse(currentSettings!.availableEndTime!.split(':')[0]),
            minute: int.parse(currentSettings.availableEndTime!.split(':')[1]))
        : null;
    bool hidePrice = currentSettings?.hidePriceOnCard ?? false;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Configuration : ${product.name}"),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> selectTime(bool isStart) async {
              final TimeOfDay? picked = await showTimePicker(
                context: context,
                initialTime: (isStart ? startTime : endTime) ??
                    const TimeOfDay(hour: 12, minute: 0),
                builder: (BuildContext context, Widget? child) {
                  return MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setStateDialog(() {
                  if (isStart)
                    startTime = picked;
                  else
                    endTime = picked;
                });
              }
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Fiscalité",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          value: selectedVat,
                          decoration:
                              const InputDecoration(labelText: "TVA Sur Place"),
                          items: vatRates
                              .map((rate) => DropdownMenuItem(
                                  value: rate, child: Text("$rate %")))
                              .toList(),
                          onChanged: (value) =>
                              setStateDialog(() => selectedVat = value ?? 10.0),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          value: selectedTakeawayVat,
                          decoration:
                              const InputDecoration(labelText: "TVA Emporter"),
                          items: vatRates
                              .map((rate) => DropdownMenuItem(
                                  value: rate, child: Text("$rate %")))
                              .toList(),
                          onChanged: (value) => setStateDialog(
                              () => selectedTakeawayVat = value ?? 5.5),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                        labelText: "Prix de base / Défaut (€)",
                        prefixIcon: Icon(Icons.euro_symbol)),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  SwitchListTile(
                    title: const Text("Masquer le prix sur la carte ?"),
                    subtitle: const Text("Utile pour les menus à options"),
                    value: hidePrice,
                    onChanged: (val) => setStateDialog(() => hidePrice = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 30),
                  const Text("Disponibilité Horaire (Optionnel)",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          onPressed: () => selectTime(true),
                          label: Text(startTime == null
                              ? "Début"
                              : startTime!.format(context)),
                        ),
                      ),
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text("à")),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time_filled),
                          onPressed: () => selectTime(false),
                          label: Text(endTime == null
                              ? "Fin"
                              : endTime!.format(context)),
                        ),
                      ),
                    ],
                  ),
                  if (startTime != null || endTime != null)
                    TextButton(
                      onPressed: () => setStateDialog(() {
                        startTime = null;
                        endTime = null;
                      }),
                      child: const Text("Supprimer les horaires",
                          style: TextStyle(color: Colors.red)),
                    ),
                  if (product.options.isNotEmpty) ...[
                    const Divider(height: 30),
                    const Text("Prix par Formule / Option",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...product.options.map((opt) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: TextFormField(
                          controller: optionControllers[opt.id],
                          decoration: InputDecoration(
                              labelText: opt.name,
                              prefixIcon: const Icon(Icons.label_outline),
                              suffixText: "€"),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      );
                    }).toList(),
                  ]
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final double? basePrice =
                  double.tryParse(priceController.text.replaceAll(',', '.'));
              final Map<String, double> newOptionPrices = {};
              optionControllers.forEach((id, ctrl) {
                double? p = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (p != null) newOptionPrices[id] = p;
              });

              if (basePrice != null && basePrice >= 0) {
                String? startStr = startTime != null
                    ? "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}"
                    : null;
                String? endStr = endTime != null
                    ? "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}"
                    : null;

                menuRef.doc(product.productId).set({
                  'masterProductId': product.productId,
                  'price': basePrice,
                  'optionPrices': newOptionPrices,
                  'vatRate': selectedVat,
                  'takeawayVatRate': selectedTakeawayVat,
                  'isVisible': true,
                  'isAvailable': currentSettings?.isAvailable ?? true,
                  'position': position,
                  'availableStartTime': startStr,
                  'availableEndTime': endStr,
                  'hidePriceOnCard': hidePrice,
                }, SetOptions(merge: true));
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Veuillez entrer un prix de base valide.")));
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }
}
