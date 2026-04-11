import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final bool haptic;
  const BouncingButton({super.key, required this.child, this.onTap, this.haptic = false});
  @override
  State<BouncingButton> createState() => _BouncingButtonState();
}
class _BouncingButtonState extends State<BouncingButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Duration _duration = const Duration(milliseconds: 80);
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration, lowerBound: 0.96, upperBound: 1.0);
    _controller.value = 1.0;
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}
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
    final categories = _getValidCategories();
    if (categories.isNotEmpty) {
      _selectedKioskCategoryId = categories.first.id;
      _autoSelectFirstFilter(categories.first);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAllActiveImages());
  }
  void _autoSelectFirstFilter(KioskCategory cat) {
    final validFilters = _getValidFiltersForCategory(cat);
    _selectedKioskFilterId = validFilters.isNotEmpty ? validFilters.first.id : null;
  }
  List<KioskFilter> _getValidFiltersForCategory(KioskCategory cat) {
    final activeProducts = widget.posData.products.where((p) => !p.isIngredient && (widget.posData.menuSettings[p.productId]?.isVisible ?? false));
    final activeFilterIds = activeProducts.expand((p) => p.kioskFilterIds).toSet();
    return cat.filters.where((f) => activeFilterIds.contains(f.id)).toList();
  }
  List<KioskCategory> _getValidCategories() {
    final visibleProducts = widget.posData.products.where((p) => !p.isIngredient && (widget.posData.menuSettings[p.productId]?.isVisible ?? false));
    final visibleFilterIds = visibleProducts.expand((p) => p.kioskFilterIds).toSet();
    return widget.posData.kioskCategories.where((c) => c.filters.any((f) => visibleFilterIds.contains(f.id))).toList();
  }
  void _precacheAllActiveImages() {
    if (!mounted) return;
    final activeProducts = widget.posData.products.where((p) {
      final isVisible = widget.posData.menuSettings[p.productId]?.isVisible ?? false;
      return isVisible && !p.isIngredient && p.photoUrl != null && p.photoUrl!.isNotEmpty;
    });
    for (var product in activeProducts) {
      precacheImage(CachedNetworkImageProvider(product.photoUrl!, maxWidth: 300), context);
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
      final sections = product.sectionIds
          .map((id) => widget.posData.allSections.firstWhereOrNull((s) => s.sectionId == id))
          .whereType<ProductSection>()
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
            initialOptions: null,
            initialRemovedIngredientIds: null,
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
        content: Text(message.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
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
    final content = _folderStack.isNotEmpty
        ? _buildFolderView(_folderStack.last)
        : Column(children: [_buildSubCategoryFilters(), Expanded(child: _buildProductGrid())]);
    if (widget.isTablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 160, child: _buildFastSidebar()),
          Expanded(child: Container(color: const Color(0xFFF5F5F5), child: content)),
        ],
      );
    }
    return content;
  }
  Widget _buildFolderView(MasterProduct folder) {
    final validIds = folder.containerProductIds.toSet();
    final contentProducts = widget.posData.products
        .where((p) => validIds.contains(p.productId) || validIds.contains(p.id))
        .toList();
    return Column(
      children: [
        Container(
          height: 80,
          color: Colors.orange.shade800,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                height: 55, width: 140,
                child: ElevatedButton.icon(
                  onPressed: _navigateBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
                  label: const Text("RETOUR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: Text(folder.name.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        Expanded(child: _buildOptimizedGrid(contentProducts)),
      ],
    );
  }
  Widget _buildFastSidebar() {
    final categories = _getValidCategories();
    return Container(
      color: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: categories.map((cat) => _buildSidebarTile(cat.name.toUpperCase(), _selectedKioskCategoryId == cat.id, () {
          setState(() {
            _selectedKioskCategoryId = cat.id;
            _folderStack.clear();
            _autoSelectFirstFilter(cat);
          });
        })).toList(),
      ),
    );
  }
  Widget _buildSidebarTile(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          border: const Border(bottom: BorderSide(color: Colors.black12, width: 1)),
        ),
        alignment: Alignment.centerLeft,
        child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : Colors.black87, letterSpacing: 0.5), maxLines: 2),
      ),
    );
  }
  Widget _buildProductGrid() {
    final products = _getFilteredProducts();
    if (products.isEmpty) return const Center(child: Text("VIDE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.grey)));
    return _buildOptimizedGrid(products);
  }
  Widget _buildOptimizedGrid(List<MasterProduct> products) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      cacheExtent: 500,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240, childAspectRatio: 0.75, crossAxisSpacing: 16, mainAxisSpacing: 16,
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
      haptic: true,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
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
                      imageUrl: product.photoUrl!, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: placeholderColor),
                      errorWidget: (_, __, ___) => Container(color: placeholderColor, child: const Icon(Icons.broken_image, color: Colors.black12)),
                    )
                  else
                    Container(color: placeholderColor, child: Icon(isContainer ? Icons.folder : Icons.restaurant, color: Colors.black12, size: 50)),
                  if (isContainer) Positioned(top: 10, right: 10, child: CircleAvatar(backgroundColor: Colors.white, radius: 16, child: const Icon(Icons.arrow_forward, size: 20, color: Colors.black))),
                  if (!settings.isAvailable)
                    Container(color: Colors.black87, alignment: Alignment.center, child: const Text("ÉPUISÉ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 2))),
                  if (hasCustomization && !isContainer && settings.isAvailable)
                    Positioned(bottom: 8, right: 8, child: CircleAvatar(backgroundColor: Colors.white, radius: 14, child: Icon(Icons.tune, size: 18, color: Colors.black))),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(10),
                color: isContainer ? const Color(0xFFFFF3E0) : Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                        product.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black, height: 1.1)
                    ),
                    if (!isContainer && !settings.hidePriceOnCard) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                            "${settings.price.toStringAsFixed(2)} €",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white)
                        ),
                      ),
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
  Widget _buildSubCategoryFilters() {
    if (_selectedKioskCategoryId == null) return const SizedBox.shrink();
    final cat = widget.posData.kioskCategories.firstWhereOrNull((c) => c.id == _selectedKioskCategoryId);
    if (cat == null) return const SizedBox.shrink();
    final validFilters = _getValidFiltersForCategory(cat);
    if (validFilters.length < 2) return const SizedBox.shrink();
    return Container(
      height: 80, color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        itemCount: validFilters.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final f = validFilters[index];
          return _buildChip(f.name.toUpperCase(), _selectedKioskFilterId == f.id, () => setState(() => _selectedKioskFilterId = f.id));
        },
      ),
    );
  }
  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade300, width: 2),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3))] : [],
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
      ),
    );
  }
}
class ProductOptionsPage extends StatefulWidget {
  final String franchiseeId;
  final MasterProduct product;
  final double basePrice;
  final double vatRate;
  final List<ProductSection> sections;
  final Map<String, List<SectionItem>>? initialOptions;
  final List<String>? initialRemovedIngredientIds;
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
    this.initialRemovedIngredientIds,
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
  late List<ProductSection> _sortedSections;
  List<MasterProduct> _baseIngredients = [];
  Map<String, double> _supplementOverrides = {};
  final Set<String> _removedIngredientIds = {};
  @override
  void initState() {
    super.initState();
    _sortedSections = widget.sections.map((section) {
      final itemsCopy = List<SectionItem>.from(section.items);
      itemsCopy.sort((a, b) {
        int indexA = widget.product.ingredientProductIds.indexOf(a.product.productId);
        int indexB = widget.product.ingredientProductIds.indexOf(b.product.productId);
        if (indexA == -1) indexA = 999;
        if (indexB == -1) indexB = 999;
        return indexA.compareTo(indexB);
      });
      return ProductSection(
        id: section.id, 
        sectionId: section.sectionId,
        title: section.title,
        type: section.type,
        selectionMin: section.selectionMin,
        selectionMax: section.selectionMax,
        items: itemsCopy,
      );
    }).toList();
    _sortedSections.sort((a, b) {
      int indexA = widget.product.sectionIds.indexOf(a.sectionId);
      int indexB = widget.product.sectionIds.indexOf(b.sectionId);
      return indexA.compareTo(indexB);
    });
    for (var section in _sortedSections) {
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
    if (widget.initialRemovedIngredientIds != null) {
      _removedIngredientIds.addAll(widget.initialRemovedIngredientIds!);
    }
    if (widget.product.ingredientProductIds.isNotEmpty) {
      final local = widget.allProductsRef.where((p) => widget.product.ingredientProductIds.contains(p.productId)).toList();
      if (local.length >= widget.product.ingredientProductIds.length) {
        _baseIngredients = local;
      } else {
        final cached = widget.product.ingredientProductIds.map((id) => _PosCache.ingredients[id]).whereType<MasterProduct>().toList();
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
      final snapshot = await FirebaseFirestore.instance.collection('master_products').where('productId', whereIn: widget.product.ingredientProductIds).get();
      final fetched = snapshot.docs.map((d) => MasterProduct.fromFirestore(d.data(), d.id)).toList();
      for (var p in fetched) _PosCache.ingredients[p.productId] = p;
      if (mounted) setState(() => _baseIngredients = fetched);
    } catch (_) {}
  }
  Future<void> _fetchPrices() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(widget.franchiseeId).collection('menu').doc(widget.product.productId).collection('supplement_overrides').get();
      final prices = {for (var doc in snapshot.docs) doc.id: (doc.data()['price'] as num?)?.toDouble() ?? 0.0};
      _PosCache.prices[widget.product.productId] = prices;
      if (mounted) setState(() => _supplementOverrides = prices);
    } catch (_) {}
  }
  double _getActualPrice(SectionItem item) => _supplementOverrides[item.product.productId] ?? item.supplementPrice;
  double get _totalPrice {
    double total = widget.basePrice;
    _selectionQuantities.forEach((_, itemsMap) {
      itemsMap.forEach((itemId, qty) {
        final item = _itemLookup[itemId];
        if (item != null) total += (_getActualPrice(item) * qty);
      });
    });
    return total;
  }
  void _updateQuantity(ProductSection section, SectionItem item, int delta) {
    HapticFeedback.lightImpact();
    setState(() {
      final sectionMap = _selectionQuantities[section.sectionId] ?? {};
      int currentQty = sectionMap[item.product.id] ?? 0;
      final String typeLower = section.type.toLowerCase();
      final bool isRadio = typeLower.contains('unique') || typeLower.contains('radio');
      final bool isIncremental = typeLower.contains('increment') || typeLower.contains('quantity') || typeLower.contains('compteur');
      if (isRadio) {
        if (delta > 0) {
          sectionMap.clear();
          sectionMap[item.product.id] = 1;
        }
      } else {
        int newQty = currentQty + delta;
        if (!isIncremental && newQty > 1) newQty = 1;
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
  bool _validate() {
    for (var section in _sortedSections) {
      final sectionMap = _selectionQuantities[section.sectionId] ?? {};
      int totalQty = sectionMap.values.fold(0, (sum, q) => sum + q);
      if (totalQty < section.selectionMin) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("⚠️ OBLIGATOIRE : ${section.title.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(20)));
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
          final adjustedItem = SectionItem(product: item.product, supplementPrice: _getActualPrice(item));
          for (int i = 0; i < qty; i++) {
            itemsList.add(adjustedItem);
          }
        }
      });
      if (itemsList.isNotEmpty) finalOptions[sectionId] = itemsList;
    });
    Navigator.pop(context, CartItem(
      product: widget.product, quantity: 1, price: widget.basePrice, vatRate: widget.vatRate,
      selectedOptions: finalOptions,
      removedIngredientProductIds: _removedIngredientIds.toList(),
      removedIngredientNames: _baseIngredients.where((p) => _removedIngredientIds.contains(p.productId)).map((p) => p.name).toList(),
    ));
  }
  void _showIngredientModifier() async {
    await showDialog(
      context: context,
      builder: (ctx) => _IngredientCustomizationDialog(baseIngredients: _baseIngredients, initiallyRemovedIds: _removedIngredientIds.toList()),
    ).then((result) {
      if (result != null && result is List<String>) setState(() { _removedIngredientIds.clear(); _removedIngredientIds.addAll(result); });
    });
  }
  bool _areRequirementsMet() {
    for (var section in _sortedSections) {
      final sectionMap = _selectionQuantities[section.sectionId] ?? {};
      int totalQty = sectionMap.values.fold(0, (sum, q) => sum + q);
      if (totalQty < section.selectionMin) return false;
    }
    return true;
  }
  @override
  Widget build(BuildContext context) {
    final bool isModif = widget.initialOptions != null || widget.initialRemovedIngredientIds != null;
    final bool isFormValid = _areRequirementsMet();
    final Color primaryColor = isModif ? AppColors.bkBlue : Colors.black;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 16, left: 24, right: 24),
            decoration: BoxDecoration(color: primaryColor),
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 0,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: Icon(isModif ? Icons.edit : Icons.restaurant, color: Colors.white, size: 34),
                      ),
                      const SizedBox(width: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Text(widget.product.name.toUpperCase(),
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                if (_baseIngredients.isNotEmpty)
                  Align(
                    alignment: Alignment.center,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(0.6), width: 3),
                          backgroundColor: Colors.white.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)
                      ),
                      onPressed: _showIngredientModifier,
                      icon: const Icon(Icons.layers_clear, size: 24),
                      label: Text(
                        _removedIngredientIds.isEmpty ? "MODIFIER INGRÉDIENTS" : "MODIFIÉ (${_removedIngredientIds.length})",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 44),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              children: [
                if (_removedIngredientIds.isNotEmpty && _baseIngredients.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 32),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.shade100, width: 2.5)),
                    child: Row(
                      children: [
                        const Icon(Icons.no_food, color: Colors.red, size: 34),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text("SANS : ${_baseIngredients.where((p) => _removedIngredientIds.contains(p.productId)).map((p) => p.name).join(", ")}",
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                      ],
                    ),
                  ),
                ..._sortedSections.map((section) => _buildSectionBlock(section)),
                if (_sortedSections.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Aucune option disponible", style: TextStyle(color: Colors.grey, fontSize: 22, fontWeight: FontWeight.w900)))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, -5))],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 90,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFormValid ? (isModif ? AppColors.bkBlue : AppColors.bkGreen) : Colors.grey.shade300,
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: isFormValid ? _onConfirm : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                          isModif ? 'ENREGISTRER' : 'AJOUTER AU PANIER',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isFormValid ? Colors.white : Colors.grey.shade600, letterSpacing: 1)
                      ),
                      const SizedBox(width: 40),
                      Container(width: 3, height: 40, color: isFormValid ? Colors.white38 : Colors.grey),
                      const SizedBox(width: 40),
                      Text(
                          "${_totalPrice.toStringAsFixed(2)} €",
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isFormValid ? Colors.white : Colors.grey.shade600)
                      ),
                    ],
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
    final String typeLower = section.type.toLowerCase();
    final bool isRadio = typeLower.contains('unique') || typeLower.contains('radio');
    final bool isIncremental = typeLower.contains('increment') || typeLower.contains('quantity') || typeLower.contains('compteur');
    final sectionMap = _selectionQuantities[section.sectionId] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 20, left: 4),
          child: Row(
            children: [
              Text(section.title.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.bkBlack, letterSpacing: 1.2)),
              const SizedBox(width: 20),
              if (section.selectionMin > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFFFEAEA), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade100, width: 2)),
                  child: Text("OBLIGATOIRE", style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              if (section.selectionMax > 0 && !isRadio)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text("(Max ${section.selectionMax})", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w900, fontSize: 17)),
                )
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisExtent: 105,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
          ),
          itemCount: section.items.length,
          itemBuilder: (context, index) {
            final item = section.items[index];
            final int qty = sectionMap[item.product.id] ?? 0;
            final bool isSelected = qty > 0;
            final double displayPrice = _getActualPrice(item);
            final int totalInSection = sectionMap.values.fold(0, (sum, q) => sum + q);
            final bool canAdd = section.selectionMax <= 0 || totalInSection < section.selectionMax;
            if (isIncremental) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade200, width: isSelected ? 4 : 2),
                  boxShadow: [
                    if(isSelected) BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 5))
                  ],
                ),
                child: Row(
                  children: [
                    if (isSelected)
                      InkWell(
                        onTap: () => _updateQuantity(section, item, -1),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                        child: Container(
                          width: 65,
                          height: double.infinity,
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: const BorderRadius.horizontal(left: Radius.circular(16))),
                          child: Icon(Icons.remove, color: Colors.red.shade800, size: 32),
                        ),
                      ),
                    if (isSelected) Container(width: 2, height: double.infinity, color: Colors.grey.shade100),
                    Expanded(
                      child: InkWell(
                        onTap: canAdd ? () => _updateQuantity(section, item, 1) : null,
                        borderRadius: BorderRadius.horizontal(right: const Radius.circular(16), left: isSelected ? Radius.zero : const Radius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.product.name,
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: isSelected ? Colors.black : Colors.grey.shade900, height: 1.1),
                                        maxLines: 2, overflow: TextOverflow.ellipsis),
                                    if (displayPrice > 0)
                                      Text("+${displayPrice.toStringAsFixed(2)}€",
                                          style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w900, fontSize: 15)),
                                  ],
                                ),
                              ),
                              if (qty > 0)
                                Container(
                                  width: 36, height: 36,
                                  margin: const EdgeInsets.only(left: 8),
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                  child: Text("$qty", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                                )
                              else
                                Icon(Icons.add, color: canAdd ? Colors.black : Colors.grey.shade300, size: 32)
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? (isRadio ? Colors.grey.shade100 : Colors.blue.shade50) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSelected ? (isRadio ? Colors.black : AppColors.bkBlue) : Colors.grey.shade200,
                      width: isSelected ? 4 : 2
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    if (isRadio) {
                      _updateQuantity(section, item, 1);
                    } else {
                      if (!isSelected && !canAdd) return;
                      _updateQuantity(section, item, isSelected ? -1 : 1);
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name,
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: isSelected ? Colors.black : Colors.grey.shade900, height: 1.1),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (displayPrice > 0)
                                Text("+${displayPrice.toStringAsFixed(2)}€",
                                    style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w900, fontSize: 15)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isRadio)
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade400, width: 3),
                                color: isSelected ? Colors.black : Colors.transparent
                            ),
                            child: isSelected ? const Icon(Icons.check, size: 22, color: Colors.white) : null,
                          )
                        else
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: isSelected ? AppColors.bkBlue : Colors.white,
                                border: Border.all(color: isSelected ? AppColors.bkBlue : Colors.grey.shade400, width: 3)
                            ),
                            child: isSelected ? const Icon(Icons.check, size: 26, color: Colors.white) : null,
                          )
                      ],
                    ),
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
class _IngredientCustomizationDialog extends StatefulWidget {
  final List<MasterProduct> baseIngredients;
  final List<String> initiallyRemovedIds;
  const _IngredientCustomizationDialog({required this.baseIngredients, required this.initiallyRemovedIds});
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Text("INGRÉDIENTS INCLUS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 0.8)),
      content: SizedBox(
        width: 600,
        height: 500,
        child: ListView.separated(
          itemCount: widget.baseIngredients.length,
          separatorBuilder: (_, __) => const Divider(height: 1, thickness: 2),
          itemBuilder: (context, index) {
            final ingredient = widget.baseIngredients[index];
            final bool isKept = !_removedIds.contains(ingredient.productId);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: Text(ingredient.name,
                  style: TextStyle(
                      decoration: !isKept ? TextDecoration.lineThrough : null,
                      color: !isKept ? Colors.grey : Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 20
                  )),
              trailing: Transform.scale(
                scale: 1.5,
                child: Switch.adaptive(
                  value: isKept,
                  activeColor: AppColors.bkGreen,
                  onChanged: (val) {
                    setState(() { if (val) {
                      _removedIds.remove(ingredient.productId);
                    } else {
                      _removedIds.add(ingredient.productId);
                    } });
                    HapticFeedback.selectionClick();
                  },
                ),
              ),
            );
          },
        ),
      ),
      actionsPadding: const EdgeInsets.all(24),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text("ANNULER", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, fontSize: 18))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
          ),
          onPressed: () => Navigator.pop(context, _removedIds.toList()),
          child: const Text("VALIDER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        ),
      ],
    );
  }
}
