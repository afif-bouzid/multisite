import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/cart_provider.dart';
import '/models.dart';
import '../../../../../core/theme/app_colors.dart';
import '../pos_dialogs.dart';

Color? _colorFromHex(String? hexString) {
  if (hexString == null || hexString.isEmpty || !hexString.startsWith('#')) {
    return null;
  }
  try {
    return Color(int.parse("0xFF${hexString.substring(1)}"));
  } catch (e) {
    return null;
  }
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

  @override
  Widget build(BuildContext context) {
    if (widget.isTablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: _buildKioskCategorySidebar(),
          ),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildSubCategoryFilters(),
                Expanded(child: _buildProductGrid()),
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildMobileKioskCategoryFilters(),
          _buildSubCategoryFilters(),
          Expanded(child: _buildProductGrid()),
        ],
      );
    }
  }

  Widget _buildKioskCategorySidebar() {
    final Set<String> allVisibleProductKioskFilterIds = widget.posData.products
        .where((p) =>
            !p.isIngredient &&
            (widget.posData.menuSettings[p.productId]?.isVisible ?? false))
        .expand((p) => p.kioskFilterIds)
        .toSet();

    final relevantCategories = widget.posData.kioskCategories
        .where((c) => c.filters
            .any((f) => allVisibleProductKioskFilterIds.contains(f.id)))
        .toList();

    return Container(
      color: Colors.white,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          _buildFilterTile(
            "Tous",
            _selectedKioskCategoryId == null,
            () => setState(() {
              _selectedKioskCategoryId = null;
              _selectedKioskFilterId = null;
            }),
          ),
          ...relevantCategories.map((cat) => _buildFilterTile(
                cat.name,
                _selectedKioskCategoryId == cat.id,
                () => setState(() {
                  _selectedKioskCategoryId = cat.id;
                  _selectedKioskFilterId = null;
                }),
              )),
        ],
      ),
    );
  }

  Widget _buildMobileKioskCategoryFilters() {
    final Set<String> activeFilterIds = widget.posData.products
        .where((p) =>
            !p.isIngredient &&
            (widget.posData.menuSettings[p.productId]?.isVisible ?? false))
        .expand((p) => p.kioskFilterIds)
        .toSet();

    final relevantCategories = widget.posData.kioskCategories
        .where((c) => c.filters.any((f) => activeFilterIds.contains(f.id)))
        .toList();

    if (relevantCategories.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: relevantCategories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildMainFilterChip(
                "Tous",
                _selectedKioskCategoryId == null,
                () => setState(() {
                      _selectedKioskCategoryId = null;
                      _selectedKioskFilterId = null;
                    }));
          }
          final cat = relevantCategories[index - 1];
          return _buildMainFilterChip(
              cat.name,
              _selectedKioskCategoryId == cat.id,
              () => setState(() {
                    _selectedKioskCategoryId = cat.id;
                    _selectedKioskFilterId = null;
                  }));
        },
      ),
    );
  }

  Widget _buildFilterTile(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 12.0),
      child: Material(
        color: isSelected ? AppColors.bkYellow : Colors.white,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        elevation: isSelected ? 2 : 0,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(right: 12.0),
                    child: Icon(Icons.arrow_right,
                        color: AppColors.bkBlack, size: 28),
                  ),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color:
                          isSelected ? AppColors.bkBlack : Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainFilterChip(
      String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
          label: Text(label), selected: isSelected, onSelected: (_) => onTap()),
    );
  }

  Widget _buildSubCategoryFilters() {
    if (_selectedKioskCategoryId == null) return const SizedBox.shrink();
    final selectedCategory = widget.posData.kioskCategories
        .firstWhereOrNull((c) => c.id == _selectedKioskCategoryId);
    if (selectedCategory == null) return const SizedBox.shrink();

    final Set<String> activeFilterIds = widget.posData.products
        .where((p) =>
            !p.isIngredient &&
            (widget.posData.menuSettings[p.productId]?.isVisible ?? false))
        .expand((p) => p.kioskFilterIds)
        .toSet();

    final relevantFilters = selectedCategory.filters
        .where((f) => activeFilterIds.contains(f.id))
        .toList();

    if (relevantFilters.isEmpty) return const SizedBox.shrink();

    return Container(
      height: widget.isTablet ? 70 : 60,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: relevantFilters.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSubFilterChip("Toutes", _selectedKioskFilterId == null,
                (v) {
              if (v) setState(() => _selectedKioskFilterId = null);
            });
          }
          final filter = relevantFilters[index - 1];
          return _buildSubFilterChip(
              filter.name, _selectedKioskFilterId == filter.id, (v) {
            setState(() => _selectedKioskFilterId = v ? filter.id : null);
          }, colorString: filter.color, imageUrl: filter.imageUrl);
        },
      ),
    );
  }

  Widget _buildSubFilterChip(
      String label, bool isSelected, ValueChanged<bool> onSelected,
      {String? colorString, String? imageUrl}) {
    final Color? chipColor = _colorFromHex(colorString);
    Widget? avatar;
    if (imageUrl != null) {
      avatar =
          CircleAvatar(backgroundImage: CachedNetworkImageProvider(imageUrl));
    } else if (chipColor != null) {
      avatar = CircleAvatar(backgroundColor: chipColor, radius: 12);
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Transform.scale(
        scale: 1.1,
        child: ChoiceChip(
          avatar: avatar,
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Text(label,
                style: TextStyle(
                    color: isSelected ? AppColors.bkBlack : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal)),
          ),
          selected: isSelected,
          onSelected: onSelected,
          selectedColor: AppColors.bkYellow,
          backgroundColor: Colors.grey.shade200,
          showCheckmark: false,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? const BorderSide(color: AppColors.bkBlack, width: 2)
                  : BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    List<MasterProduct> displayProducts = widget.posData.products
        .where((p) =>
            !p.isIngredient &&
            (widget.posData.menuSettings[p.productId]?.isVisible ?? false))
        .toList();

    if (_selectedKioskCategoryId != null) {
      final cat = widget.posData.kioskCategories
          .firstWhereOrNull((c) => c.id == _selectedKioskCategoryId);
      if (cat != null) {
        final filterIds = cat.filters.map((f) => f.id).toSet();
        displayProducts = displayProducts
            .where((p) => p.kioskFilterIds.any((id) => filterIds.contains(id)))
            .toList();
        if (_selectedKioskFilterId != null) {
          displayProducts = displayProducts
              .where((p) => p.kioskFilterIds.contains(_selectedKioskFilterId!))
              .toList();
        }
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: displayProducts.length,
      itemBuilder: (context, index) {
        final product = displayProducts[index];
        final settings = widget.posData.menuSettings[product.productId];
        if (settings == null) return const SizedBox.shrink();
        return _buildProductCard(product, settings, widget.posData.allSections);
      },
    );
  }

  Widget _buildProductCard(MasterProduct product, FranchiseeMenuItem settings,
      List<ProductSection> allSections) {
    final isAvailable = settings.isAvailable;
    final hasImage = product.photoUrl != null && product.photoUrl!.isNotEmpty;
    final Color cardBaseColor = _colorFromHex(product.color) ?? Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isAvailable ? () => _onProductTap(product, settings) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: hasImage
                          ? CachedNetworkImage(
                              imageUrl: product.photoUrl!,
                              fit: BoxFit.cover,
                              color: isAvailable
                                  ? null
                                  : Colors.white.withOpacity(0.2),
                              colorBlendMode:
                                  isAvailable ? null : BlendMode.modulate,
                            )
                          : Container(
                              color: cardBaseColor.withOpacity(0.1),
                              child: Icon(
                                product.isComposite
                                    ? Icons.restaurant_menu
                                    : Icons.fastfood,
                                size: 40,
                                color: cardBaseColor,
                              ),
                            ),
                    ),
                    if (isAvailable && !settings.hidePriceOnCard)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.bkBlack,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${settings.price.toStringAsFixed(2)} €",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                      ),
                    if (!isAvailable)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                        ),
                        child: const Center(
                          child: Text("ÉPUISÉ",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18)),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isAvailable ? AppColors.bkBlack : Colors.grey,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onProductTap(
      MasterProduct product, FranchiseeMenuItem settings) async {
    final cart = context.read<CartProvider>();
    double tempVat = settings.vatRate;

    if (product.isComposite) {
      double selectedBasePrice = settings.price;
      List<ProductSection> sectionsToUse = [];

      if (product.options.isNotEmpty) {
        final ProductOption? chosenOption = await showDialog(
            context: context,
            builder: (ctx) =>
                PosOptionSelectorDialog(product: product, settings: settings));
        if (chosenOption == null) return;
        if (settings.optionPrices.containsKey(chosenOption.id)) {
          selectedBasePrice = settings.optionPrices[chosenOption.id]!;
        }

        sectionsToUse = widget.posData.allSections
            .where((s) => chosenOption.sectionIds.contains(s.sectionId))
            .toList();
        sectionsToUse.sort((a, b) {
          return chosenOption.sectionIds
              .indexOf(a.sectionId)
              .compareTo(chosenOption.sectionIds.indexOf(b.sectionId));
        });
      } else {
        sectionsToUse = widget.posData.allSections
            .where((s) => product.sectionIds.contains(s.sectionId))
            .toList();
        sectionsToUse.sort((a, b) => product.sectionIds
            .indexOf(a.sectionId)
            .compareTo(product.sectionIds.indexOf(b.sectionId)));
      }

      final cartItem = await showDialog<CartItem>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => CompositeProductDialog(
          product: product,
          franchiseeId: widget.franchiseeId,
          basePrice: selectedBasePrice,
          vatRate: settings.vatRate,
          allSections: sectionsToUse,
        ),
      );
      if (cartItem != null && mounted) {
        cart.addItem(cartItem);
      }
    } else {
      cart.addItem(
          CartItem(product: product, price: settings.price, vatRate: tempVat));
    }
  }
}
