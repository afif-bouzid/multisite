import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/cart_provider.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../models.dart';
import '../pos_dialogs.dart';

Color? _colorFromHex(String? hexString) {
  if (hexString == null || hexString.isEmpty || !hexString.startsWith('#')) return null;
  try {
    return Color(int.parse("0xFF${hexString.substring(1)}"));
  } catch (e) {
    return null;
  }
}

class BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const BouncingButton({super.key, required this.child, this.onTap});
  @override
  State<BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<BouncingButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Duration _duration = const Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration, lowerBound: 0.95, upperBound: 1.0);
    _controller.value = 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) { _controller.forward(); widget.onTap?.call(); },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}

// =============================================================================
// 1. VUE PRINCIPALE (DASHBOARD)
// =============================================================================
class ProductViewContent extends StatefulWidget {
  final PosData posData;
  final String franchiseeId;
  final bool isTablet;

  const ProductViewContent({
    super.key,
    required this.posData,
    required this.franchiseeId,
    required this.isTablet,
  });

  @override
  State<ProductViewContent> createState() => _ProductViewContentState();
}

class _ProductViewContentState extends State<ProductViewContent> {
  String? _selectedKioskCategoryId;
  String? _selectedKioskFilterId;
  final List<MasterProduct> _folderStack = [];

  @override
  void initState() {
    super.initState();

    // Sélection automatique de la première catégorie et de son premier filtre
    final categories = _getValidCategories();
    if (categories.isNotEmpty) {
      _selectedKioskCategoryId = categories.first.id;
      _autoSelectFirstFilter(categories.first);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAllActiveImages();
    });
  }

  // ✅ Helper pour sélectionner automatiquement le premier filtre valide
  void _autoSelectFirstFilter(KioskCategory cat) {
    final validFilters = _getValidFiltersForCategory(cat);
    if (validFilters.isNotEmpty) {
      _selectedKioskFilterId = validFilters.first.id;
    } else {
      _selectedKioskFilterId = null;
    }
  }

  // ✅ Helper pour récupérer les filtres valides d'une catégorie
  List<KioskFilter> _getValidFiltersForCategory(KioskCategory cat) {
    final activeProducts = widget.posData.products.where((p) => !p.isIngredient && (widget.posData.menuSettings[p.productId]?.isVisible ?? false));
    final activeFilterIds = activeProducts.expand((p) => p.kioskFilterIds).toSet();
    return cat.filters.where((f) => activeFilterIds.contains(f.id)).toList();
  }

  List<KioskCategory> _getValidCategories() {
    final visibleProducts = widget.posData.products.where((p) => !p.isIngredient && (widget.posData.menuSettings[p.productId]?.isVisible ?? false));
    final visibleFilterIds = visibleProducts.expand((p) => p.kioskFilterIds).toSet();

    return widget.posData.kioskCategories
        .where((c) => c.filters.any((f) => visibleFilterIds.contains(f.id)))
        .toList();
  }

  void _precacheAllActiveImages() {
    if (!mounted) return;
    final activeProducts = widget.posData.products.where((p) {
      final isVisible = widget.posData.menuSettings[p.productId]?.isVisible ?? false;
      return isVisible && !p.isIngredient && p.photoUrl != null && p.photoUrl!.isNotEmpty;
    });
    for (var product in activeProducts) {
      precacheImage(
        CachedNetworkImageProvider(product.photoUrl!, maxWidth: 300),
        context,
      );
    }
  }

  List<MasterProduct> _getFilteredProducts() {
    return widget.posData.products.where((p) {
      if (p.isIngredient) return false;
      final settings = widget.posData.menuSettings[p.productId];
      if (settings == null || !settings.isVisible) return false;

      if (_selectedKioskCategoryId != null) {
        final cat = widget.posData.kioskCategories.firstWhereOrNull((c) => c.id == _selectedKioskCategoryId);
        if (cat == null) return false;

        final catFilterIds = cat.filters.map((f) => f.id).toSet();
        if (!p.kioskFilterIds.any((id) => catFilterIds.contains(id))) return false;

        if (_selectedKioskFilterId != null) {
          if (!p.kioskFilterIds.contains(_selectedKioskFilterId)) return false;
        }
      }
      return true;
    }).toList();
  }

  void _handleProductTap(MasterProduct product, FranchiseeMenuItem settings) {
    if (product.isContainer || (product.containerProductIds.isNotEmpty)) {
      setState(() => _folderStack.add(product));
      return;
    }
    _addProductToCart(product, settings);
  }

  void _addProductToCart(MasterProduct product, FranchiseeMenuItem settings) async {
    final cart = Provider.of<CartProvider>(context, listen: false);

    bool hasOptions = product.sectionIds.isNotEmpty || product.isComposite || product.ingredientProductIds.isNotEmpty;

    if (hasOptions) {
      final sections = widget.posData.allSections
          .where((s) => product.sectionIds.contains(s.sectionId))
          .toList();

      final CartItem? configuredItem = await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => ProductOptionsPage(
            franchiseeId: widget.franchiseeId,
            product: product,
            basePrice: settings.price,
            vatRate: settings.vatRate,
            sections: sections,
            allProductsRef: widget.posData.products,
          ),
        ),
      );

      if (configuredItem != null) {
        cart.addItem(configuredItem);
        _showFlashFeedback("AJOUTÉ : ${product.name}");
      }
    } else {
      cart.addItem(CartItem(
        product: product,
        quantity: 1,
        price: settings.price,
        vatRate: settings.vatRate,
        selectedOptions: {},
      ));
      _showFlashFeedback("AJOUTÉ");
    }
  }

  void _showFlashFeedback(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
        duration: const Duration(milliseconds: 300),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  void _navigateBack() {
    if (_folderStack.isNotEmpty) setState(() => _folderStack.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 160, child: _buildFastSidebar()),
          Expanded(
            child: Container(
              color: const Color(0xFFF5F5F5),
              child: _folderStack.isNotEmpty
                  ? _buildFolderView(_folderStack.last)
                  : Column(
                children: [
                  _buildSubCategoryFilters(),
                  Expanded(child: _buildProductGrid()),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      if (_folderStack.isNotEmpty) return _buildFolderView(_folderStack.last);
      return Column(
        children: [
          _buildSubCategoryFilters(),
          Expanded(child: _buildProductGrid()),
        ],
      );
    }
  }

  Widget _buildFolderView(MasterProduct folder) {
    final validIds = folder.containerProductIds.toSet();
    final contentProducts = widget.posData.products
        .where((p) => validIds.contains(p.productId) || validIds.contains(p.id))
        .toList();

    return Column(
      children: [
        Container(
          height: 70,
          color: Colors.orange.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                height: 50, width: 140,
                child: ElevatedButton.icon(
                  onPressed: _navigateBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
                  label: const Text("RETOUR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: Text(folder.name.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        Expanded(child: _buildOptimizedGrid(contentProducts, isInsideFolder: true)),
      ],
    );
  }

  Widget _buildFastSidebar() {
    final categories = _getValidCategories();

    return Container(
      color: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ...categories.map((cat) => _buildSidebarTile(cat.name.toUpperCase(), _selectedKioskCategoryId == cat.id, () {
            setState(() {
              _selectedKioskCategoryId = cat.id;
              _folderStack.clear();
              // ✅ Auto-sélection du premier filtre pour éviter le mélange
              _autoSelectFirstFilter(cat);
            });
          })),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          border: const Border(bottom: BorderSide(color: Colors.black12)),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : Colors.black87, letterSpacing: 0.5),
          maxLines: 2,
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    final products = _getFilteredProducts();
    if (products.isEmpty) return const Center(child: Text("VIDE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)));
    return _buildOptimizedGrid(products, isInsideFolder: false);
  }

  Widget _buildOptimizedGrid(List<MasterProduct> products, {required bool isInsideFolder}) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      cacheExtent: 500,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final settings = widget.posData.menuSettings[product.productId];
        if (settings == null) return const SizedBox.shrink();
        return _buildUltraFastCard(product, settings, onTap: settings.isAvailable ? () => _handleProductTap(product, settings) : null);
      },
    );
  }

  Widget _buildUltraFastCard(MasterProduct product, FranchiseeMenuItem settings, {required VoidCallback? onTap}) {
    final bool isContainer = product.isContainer || (product.containerProductIds.isNotEmpty);
    Color placeholderColor = _colorFromHex(product.color) ?? Colors.grey.shade100;
    if (isContainer) placeholderColor = const Color(0xFFFFCC80);
    final bool hasCustomization = product.ingredientProductIds.isNotEmpty || product.sectionIds.isNotEmpty;

    return BouncingButton(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2))],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: product.photoUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      maxWidthDiskCache: 400,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (context, url) => Container(color: placeholderColor),
                      errorWidget: (context, url, error) => Container(color: placeholderColor, child: const Icon(Icons.broken_image, color: Colors.black12)),
                    )
                  else
                    Container(color: placeholderColor, child: Icon(isContainer ? Icons.folder : Icons.restaurant, color: Colors.black12, size: 40)),

                  if (isContainer) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.all(6), color: Colors.black, child: const Icon(Icons.arrow_forward, size: 14, color: Colors.white))),
                  if (!settings.isAvailable)
                    Container(
                        color: Colors.black.withOpacity(0.6),
                        alignment: Alignment.center,
                        child: Transform.rotate(
                          angle: -0.2,
                          child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(8)),
                              child: const Text("ÉPUISÉ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2))
                          ),
                        )
                    ),
                  if (hasCustomization && !isContainer && settings.isAvailable)
                    Positioned(
                      bottom: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.edit, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(4),
                color: isContainer ? const Color(0xFFFFE0B2) : Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(product.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.1, color: Colors.black87)),
                    if (!isContainer && !settings.hidePriceOnCard) ...[
                      const SizedBox(height: 4),
                      Text("${settings.price.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
                    ]
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ VUE SOUS-FILTRES OPTIMISÉE
  Widget _buildSubCategoryFilters() {
    if (_selectedKioskCategoryId == null) return const SizedBox.shrink();

    final cat = widget.posData.kioskCategories.firstWhereOrNull((c) => c.id == _selectedKioskCategoryId);
    if (cat == null) return const SizedBox.shrink();

    // Récupération des filtres valides
    final validFilters = _getValidFiltersForCategory(cat);

    // ❌ S'il y a moins de 2 filtres, on cache complètement la barre
    if (validFilters.length < 2) return const SizedBox.shrink();

    return Container(
      height: 75,
      color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: validFilters.length, // ❌ Plus de bouton "TOUT" (+1 supprimé)
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final f = validFilters[index];
          return _buildChip(
              f.name.toUpperCase(),
              _selectedKioskFilterId == f.id,
                  () => setState(() => _selectedKioskFilterId = f.id)
          );
        },
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: isSelected ? 0 : 1),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }
}

// =============================================================================
// 2. PAGE D'OPTIONS (MODALE AVEC CACHE STATIQUE)
// =============================================================================

class ProductOptionsPage extends StatefulWidget {
  final String franchiseeId;
  final MasterProduct product;
  final double basePrice;
  final double vatRate;
  final List<ProductSection> sections;
  final Map<String, List<SectionItem>>? initialOptions;
  final List<MasterProduct> allProductsRef;

  const ProductOptionsPage({
    super.key,
    required this.franchiseeId,
    required this.product,
    required this.basePrice,
    required this.vatRate,
    required this.sections,
    required this.allProductsRef,
    this.initialOptions,
  });

  @override
  State<ProductOptionsPage> createState() => _ProductOptionsPageState();
}

class _PosCache {
  static final Map<String, Map<String, double>> prices = {};
  static final Map<String, MasterProduct> ingredients = {};
}

class _ProductOptionsPageState extends State<ProductOptionsPage> {
  final Map<String, Map<String, int>> _selectionQuantities = {};
  final Map<String, SectionItem> _itemLookup = {};

  List<MasterProduct> _baseIngredients = [];
  Map<String, double> _supplementOverrides = {};
  final Set<String> _removedIngredientIds = {};

  @override
  void initState() {
    super.initState();
    for (var section in widget.sections) {
      for (var item in section.items) {
        _itemLookup[item.product.id] = item;
      }
    }
    if (widget.initialOptions != null) {
      widget.initialOptions!.forEach((sectionId, itemsList) {
        final Map<String, int> sectionMap = {};
        for (var item in itemsList) {
          sectionMap[item.product.id] = (sectionMap[item.product.id] ?? 0) + 1;
        }
        _selectionQuantities[sectionId] = sectionMap;
      });
    }

    if (widget.product.ingredientProductIds.isNotEmpty) {
      final local = widget.allProductsRef
          .where((p) => widget.product.ingredientProductIds.contains(p.productId))
          .toList();

      if (local.length >= widget.product.ingredientProductIds.length) {
        _baseIngredients = local;
      } else {
        final cached = widget.product.ingredientProductIds
            .map((id) => _PosCache.ingredients[id])
            .whereType<MasterProduct>()
            .toList();

        if (cached.length >= widget.product.ingredientProductIds.length) {
          _baseIngredients = cached;
        } else {
          _fetchIngredients();
        }
      }
    }

    if (_PosCache.prices.containsKey(widget.product.productId)) {
      _supplementOverrides = _PosCache.prices[widget.product.productId]!;
    } else {
      _fetchPrices();
    }
  }

  Future<void> _fetchIngredients() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('master_products')
          .where('productId', whereIn: widget.product.ingredientProductIds)
          .get();

      final fetched = snapshot.docs.map((d) => MasterProduct.fromFirestore(d.data(), d.id)).toList();
      for (var p in fetched) {
        _PosCache.ingredients[p.productId] = p;
      }
      if (mounted) setState(() => _baseIngredients = fetched);
    } catch (_) {}
  }

  Future<void> _fetchPrices() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.franchiseeId)
          .collection('menu')
          .doc(widget.product.productId)
          .collection('supplement_overrides')
          .get();

      final prices = {
        for (var doc in snapshot.docs)
          doc.id: (doc.data()['price'] as num?)?.toDouble() ?? 0.0
      };
      _PosCache.prices[widget.product.productId] = prices;
      if (mounted) setState(() => _supplementOverrides = prices);
    } catch (_) {}
  }

  double _getActualPrice(SectionItem item) {
    if (_supplementOverrides.containsKey(item.product.productId)) {
      return _supplementOverrides[item.product.productId]!;
    }
    return item.supplementPrice;
  }

  double get _totalPrice {
    double total = widget.basePrice;
    _selectionQuantities.forEach((sectionId, itemsMap) {
      itemsMap.forEach((itemId, qty) {
        final item = _itemLookup[itemId];
        if (item != null) {
          total += (_getActualPrice(item) * qty);
        }
      });
    });
    return total;
  }

  void _updateQuantity(ProductSection section, SectionItem item, int delta) {
    setState(() {
      final sectionMap = _selectionQuantities[section.sectionId] ?? {};
      int currentQty = sectionMap[item.product.id] ?? 0;

      if (section.type == 'unique' || section.type == 'radio') {
        if (delta > 0) {
          sectionMap.clear();
          sectionMap[item.product.id] = 1;
        }
      } else {
        int newQty = currentQty + delta;
        if (newQty < 0) newQty = 0;
        if (delta > 0 && section.selectionMax > 0) {
          int totalInSection = sectionMap.values.fold(0, (sum, q) => sum + q);
          if (totalInSection >= section.selectionMax) return;
        }
        if (newQty == 0) sectionMap.remove(item.product.id);
        else sectionMap[item.product.id] = newQty;
      }
      _selectionQuantities[section.sectionId] = sectionMap;
    });
  }

  bool _areRequirementsMet() {
    for (var section in widget.sections) {
      final sectionMap = _selectionQuantities[section.sectionId] ?? {};
      int totalQty = sectionMap.values.fold(0, (sum, q) => sum + q);
      if (totalQty < section.selectionMin) return false;
    }
    return true;
  }

  bool _validate() {
    for (var section in widget.sections) {
      final sectionMap = _selectionQuantities[section.sectionId] ?? {};
      int totalQty = sectionMap.values.fold(0, (sum, q) => sum + q);
      if (totalQty < section.selectionMin) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("CHOIX OBLIGATOIRE : ${section.title.toUpperCase()}"),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.fixed));
        return false;
      }
    }
    return true;
  }

  void _onConfirm() {
    if (!_validate()) return;
    final Map<String, List<SectionItem>> finalOptions = {};
    _selectionQuantities.forEach((sectionId, itemsMap) {
      final List<SectionItem> itemsList = [];
      itemsMap.forEach((itemId, qty) {
        final item = _itemLookup[itemId];
        if (item != null) {
          final adjustedItem = SectionItem(
            product: item.product,
            supplementPrice: _getActualPrice(item),
          );
          for (int i = 0; i < qty; i++) itemsList.add(adjustedItem);
        }
      });
      if (itemsList.isNotEmpty) finalOptions[sectionId] = itemsList;
    });

    Navigator.pop(context, CartItem(
      product: widget.product,
      quantity: 1,
      price: widget.basePrice,
      vatRate: widget.vatRate,
      selectedOptions: finalOptions,
      removedIngredientProductIds: _removedIngredientIds.toList(),
      removedIngredientNames: _baseIngredients
          .where((p) => _removedIngredientIds.contains(p.productId))
          .map((p) => p.name)
          .toList(),
    ));
  }

  void _showIngredientModifier() async {
    await showDialog(
      context: context,
      builder: (ctx) => _IngredientCustomizationDialog(
        baseIngredients: _baseIngredients,
        initiallyRemovedIds: _removedIngredientIds.toList(),
      ),
    ).then((result) {
      if (result != null && result is List<String>) {
        setState(() {
          _removedIngredientIds.clear();
          _removedIngredientIds.addAll(result);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isModif = widget.initialOptions != null;
    final bool isFormValid = _areRequirementsMet();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            color: isModif ? Colors.blue.shade900 : Colors.black,
            child: Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(isModif ? Icons.edit : Icons.add_circle_outline, color: Colors.white, size: 30),
                        const SizedBox(width: 15),
                        Flexible(
                          child: Text(
                            widget.product.name.toUpperCase(),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_baseIngredients.isNotEmpty) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _showIngredientModifier,
                      icon: const Icon(Icons.layers_clear, size: 18),
                      label: Text(
                        _removedIngredientIds.isEmpty ? "INGRÉDIENTS" : "MODIFIÉ (${_removedIngredientIds.length})",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],

                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 40),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              children: [
                if (_removedIngredientIds.isNotEmpty && _baseIngredients.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      "SANS : ${_baseIngredients.where((p) => _removedIngredientIds.contains(p.productId)).map((p) => p.name).join(", ")}",
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),

                ...widget.sections.map((section) => _buildSectionBlock(section)),

                if (widget.sections.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text("Aucune option supplémentaire.", style: TextStyle(color: Colors.grey, fontSize: 16))),
                  ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 85,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFormValid
                        ? (isModif ? Colors.blue.shade700 : Colors.green.shade700)
                        : Colors.grey.shade400,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isFormValid ? _onConfirm : null,
                  child: Text(
                    "${isModif ? 'ENREGISTRER' : 'VALIDER LA SÉLECTION'}  —  ${_totalPrice.toStringAsFixed(2)} €",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBlock(ProductSection section) {
    final bool isMultiple = section.type != 'unique' && section.type != 'radio';
    final sectionMap = _selectionQuantities[section.sectionId] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Text(section.title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.black)),
              if (section.selectionMin > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(4)),
                  child: const Text("OBLIGATOIRE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                )
              ],
              if (isMultiple && section.selectionMax > 0) ...[
                const SizedBox(width: 8),
                Text("(Max ${section.selectionMax})", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.bold)),
              ]
            ],
          ),
        ),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 80,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: section.items.length,
          itemBuilder: (context, index) {
            final item = section.items[index];
            final int qty = sectionMap[item.product.id] ?? 0;
            final bool isSelected = qty > 0;
            final double displayPrice = _getActualPrice(item);

            VoidCallback onTapAction;
            if (isMultiple) {
              onTapAction = () {
                final int delta = isSelected ? -qty : 1;
                _updateQuantity(section, item, delta);
              };
            } else {
              onTapAction = () => _updateQuantity(section, item, 1);
            }

            return Material(
              color: isSelected ? (isMultiple ? Colors.blue.shade50 : Colors.black) : Colors.white,
              elevation: isSelected ? 2 : 1,
              shadowColor: Colors.black26,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: isSelected
                        ? (isMultiple ? Colors.blue : Colors.black)
                        : Colors.grey.shade300,
                    width: isSelected ? 2 : 1
                ),
              ),
              child: InkWell(
                onTap: onTapAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                item.product.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: isSelected && !isMultiple ? Colors.white : Colors.black87
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis
                            ),
                            if (displayPrice > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                    "+${displayPrice.toStringAsFixed(2)}€",
                                    style: TextStyle(
                                        color: isSelected && !isMultiple ? Colors.greenAccent : Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12
                                    )
                                ),
                              )
                          ],
                        ),
                      ),

                      if (isMultiple)
                        Icon(
                          isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                          color: isSelected ? Colors.blue : Colors.grey.shade400,
                          size: 28,
                        )
                      else if (isSelected)
                        const Icon(Icons.check_circle, color: Colors.white, size: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 35),
      ],
    );
  }
}

// =============================================================================
// 3. WIDGET DIALOGUE INGRÉDIENTS (PRIVÉ)
// =============================================================================
class _IngredientCustomizationDialog extends StatefulWidget {
  final List<MasterProduct> baseIngredients;
  final List<String> initiallyRemovedIds;

  const _IngredientCustomizationDialog({
    required this.baseIngredients,
    required this.initiallyRemovedIds,
  });

  @override
  State<_IngredientCustomizationDialog> createState() => _IngredientCustomizationDialogState();
}

class _IngredientCustomizationDialogState extends State<_IngredientCustomizationDialog> {
  late Set<String> _removedIds;

  @override
  void initState() {
    super.initState();
    _removedIds = Set.from(widget.initiallyRemovedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text("Personnaliser les ingrédients", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 500,
        height: 400,
        child: ListView.separated(
          itemCount: widget.baseIngredients.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final ingredient = widget.baseIngredients[index];
            final bool isKept = !_removedIds.contains(ingredient.productId);

            return ListTile(
              title: Text(ingredient.name,
                  style: TextStyle(
                      decoration: !isKept ? TextDecoration.lineThrough : null,
                      color: !isKept ? Colors.grey : Colors.black,
                      fontWeight: FontWeight.bold)),
              subtitle: Text(isKept ? "Inclus" : "Retiré"),
              trailing: Switch(
                value: isKept,
                activeThumbColor: Colors.green,
                onChanged: (bool value) {
                  setState(() {
                    if (value) {
                      _removedIds.remove(ingredient.productId);
                    } else {
                      _removedIds.add(ingredient.productId);
                    }
                  });
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, _removedIds.toList()),
          child: const Text("Valider"),
        ),
      ],
    );
  }
}