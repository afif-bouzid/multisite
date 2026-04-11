import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ouiborne/back_office/views/franchisee/pos_container_dialog.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../../../../core/auth_provider.dart';
import '../../../../models.dart';
import '../../../../core/repository/repository.dart';
class POSView extends StatefulWidget {
  const POSView({super.key});
  @override
  State<POSView> createState() => _POSViewState();
}
class _POSViewState extends State<POSView> {
  List<MasterProduct> _allProducts = [];
  Map<String, FranchiseeMenuItem> _menuConfig = {};
  List<KioskCategory> _categories = [];
  final List<CartItem> _cart = [];
  String? _selectedCategoryId;
  final String _searchQuery = "";
  bool _isLoading = true;
  final List<StreamSubscription> _subs = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initData());
  }
  @override
  void dispose() {
    for (var s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
  void _initData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.franchiseUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (user.franchisorId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final repo = FranchiseRepository();
    final String franchisorId = user.franchisorId!;
    final String myStoreId = user.role == 'employee' ? (user.storeId ?? user.uid) : user.uid;
    _subs.add(repo.getMasterProductsStream(franchisorId).listen((products) {
      if (mounted) setState(() => _allProducts = products);
    }));
    _subs.add(repo.getFranchiseeMenuStream(myStoreId).listen((items) {
      final map = <String, FranchiseeMenuItem>{};
      for (var item in items) {
        map[item.masterProductId] = item;
      }
      if (mounted) setState(() => _menuConfig = map);
    }));
    _subs.add(repo.getKioskCategoriesStream(franchisorId).listen((cats) {
      if (mounted) {
        setState(() {
          _categories = cats;
          _isLoading = false;
        });
      }
    }));
  }
  List<MasterProduct> _getVisibleProducts() {
    var visibleList = _allProducts.where((p) {
      final config = _menuConfig[p.productId];
      return config != null && config.isVisible;
    }).toList();
    if (_selectedCategoryId != null) {
      final category = _categories.firstWhereOrNull((c) => c.id == _selectedCategoryId);
      if (category != null) {
        final categoryFilterIds = category.filters.map((f) => f.id).toList();
        visibleList = visibleList.where((p) {
          return p.kioskFilterIds.any((id) => categoryFilterIds.contains(id));
        }).toList();
      }
    }
    if (_searchQuery.isNotEmpty) {
      visibleList = visibleList.where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    visibleList.sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));
    return visibleList;
  }
  double _getFranchiseePrice(String productId) {
    return _menuConfig[productId]?.price ?? 0.0;
  }
  void _onProductTap(MasterProduct product) {
    if (product.isContainer) {
      showDialog(
        context: context,
        builder: (_) => PosContainerDialog(
          container: product,
          allProducts: _allProducts, 
          onProductSelected: (selectedSubProduct) {
            _processProductSelection(selectedSubProduct);
          },
        ),
      );
    } else {
      _processProductSelection(product);
    }
  }
  void _processProductSelection(MasterProduct product) {
    final hasSections = product.sectionIds.isNotEmpty;
    if (hasSections) {
      _showOptionsModal(product);
    } else {
      _addToCart(product);
    }
  }
  void _showOptionsModal(MasterProduct product) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.franchiseUser;
    if (user == null || user.franchisorId == null) return;
    final repo = FranchiseRepository();
    final sections = await repo.getSectionsForProduct(user.franchisorId!, product.sectionIds);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _ProductOptionsDialog(
        product: product,
        sections: sections,
        basePrice: _getFranchiseePrice(product.productId),
        vatRate: _menuConfig[product.productId]?.vatRate ?? 10.0,
        onConfirm: (CartItem item) {
          setState(() {
            _cart.add(item);
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }
  void _addToCart(MasterProduct product) {
    final menuItem = _menuConfig[product.productId];
    final price = menuItem?.price ?? 0.0;
    final vat = menuItem?.vatRate ?? 10.0;
    setState(() {
      _cart.add(CartItem(
        product: product,
        price: price,
        vatRate: vat,
        selectedOptions: {},
      ));
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _buildCategoryTabs(),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildProductGrid(),
                ),
              ],
            ),
          ),
          Container(
            width: 380,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              children: [
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  color: const Color(0xFF2D3436),
                  child: const Text("TICKET", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                Expanded(child: _buildCartList()),
                _buildCartTotal(),
              ],
            ),
          )
        ],
      ),
    );
  }
  Widget _buildCategoryTabs() {
    return Container(
      color: Colors.white,
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        children: [
          _buildTabChip("TOUT", null),
          ..._categories.map((c) => _buildTabChip(c.name.toUpperCase(), c.id)),
        ],
      ),
    );
  }
  Widget _buildTabChip(String label, String? id) {
    final isSelected = _selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) => setState(() => _selectedCategoryId = id),
        selectedColor: const Color(0xFF2D3436),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
        ),
      ),
    );
  }
  Widget _buildProductGrid() {
    final visibleProducts = _getVisibleProducts();
    if (visibleProducts.isEmpty) {
      return const Center(child: Text("Aucun produit disponible"));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.75,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16
      ),
      itemCount: visibleProducts.length,
      itemBuilder: (context, index) {
        final product = visibleProducts[index];
        final price = _getFranchiseePrice(product.productId);
        return InkWell(
          onTap: () => _onProductTap(product),
          child: _buildProductCardDesign(product, price),
        );
      },
    );
  }
  Widget _buildProductCardDesign(MasterProduct product, double price, {bool isInsideModal = false}) {
    final bool isContainer = product.isContainer;
    final Color borderColor = isContainer ? Colors.orange.shade300 : Colors.transparent;
    final Color footerColor = isContainer ? Colors.orange.shade50 : Colors.grey.shade50;
    final IconData icon = isContainer ? Icons.folder_copy_rounded : Icons.fastfood_rounded;
    final Color iconColor = isContainer ? Colors.orange.shade300 : Colors.grey.shade300;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isContainer ? Border.all(color: borderColor, width: 2) : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                  ? Hero(
                tag: isInsideModal ? "modal_${product.id}" : "grid_${product.id}",
                child: CachedNetworkImage(
                  imageUrl: product.photoUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (context, url, error) => Icon(icon, size: 50, color: iconColor),
                ),
              )
                  : Center(child: Icon(icon, size: 50, color: iconColor)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: footerColor,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2D3436)),
                ),
                const SizedBox(height: 6),
                if (isContainer)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "MENU / DOSSIER",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.orange.shade900),
                    ),
                  )
                else
                  Text(
                    "${price.toStringAsFixed(2)} €",
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text("Panier vide", style: TextStyle(color: Colors.grey[400])),
        ],
      ));
    }
    return ListView.separated(
      itemCount: _cart.length,
      separatorBuilder: (c, i) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _cart[index];
        return ListTile(
          dense: true,
          title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: item.selectedOptions.isNotEmpty
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: item.selectedOptions.entries.map((e) {
              return Text("+ ${e.value.map((i) => i.product.name).join(', ')}", style: TextStyle(fontSize: 11, color: Colors.grey[600]));
            }).toList(),
          )
              : null,
          trailing: Text("${item.total.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold)),
          onLongPress: () => setState(() => _cart.removeAt(index)),
        );
      },
    );
  }
  Widget _buildCartTotal() {
    double total = _cart.fold(0, (sum, item) => sum + item.total);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.grey[50], border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text("${total.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF2D3436))),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _cart.isEmpty ? null : () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Paiement non implémenté")));
              },
              child: const Text("ENCAISSER", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }
}
class _ProductOptionsDialog extends StatefulWidget {
  final MasterProduct product;
  final List<ProductSection> sections;
  final double basePrice;
  final double vatRate;
  final Function(CartItem) onConfirm;
  const _ProductOptionsDialog({
    required this.product,
    required this.sections,
    required this.basePrice,
    required this.vatRate,
    required this.onConfirm
  });
  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}
class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  final Map<String, List<SectionItem>> _selections = {};
  double get _currentTotal {
    double total = widget.basePrice;
    _selections.forEach((key, items) {
    });
    return total;
  }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 600,
        height: 700,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text("Configurer : ${widget.product.name}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: widget.sections.length,
                separatorBuilder: (c, i) => const Divider(height: 30),
                itemBuilder: (context, index) {
                  final section = widget.sections[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(section.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3436))),
                          const SizedBox(width: 8),
                          if (section.selectionMax > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                              child: Text("Max: ${section.selectionMax}", style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.bold)),
                            )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: section.items.map((item) {
                          final isSelected = _selections[section.sectionId]?.any((s) => s.product.id == item.product.id) ?? false;
                          return FilterChip(
                            label: Text("${item.product.name} ${item.supplementPrice > 0 ? '(+${item.supplementPrice.toStringAsFixed(2)}€)' : ''}"),
                            selected: isSelected,
                            checkmarkColor: Colors.white,
                            selectedColor: Colors.black,
                            backgroundColor: Colors.white,
                            shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
                            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                            onSelected: (selected) {
                              setState(() {
                                final currentList = _selections[section.sectionId] ?? [];
                                if (section.type == 'radio' || section.selectionMax == 1) {
                                  _selections[section.sectionId] = [item];
                                } else {
                                  if (selected) {
                                    if (currentList.length < section.selectionMax) {
                                      currentList.add(item);
                                      _selections[section.sectionId] = currentList;
                                    }
                                  } else {
                                    currentList.removeWhere((i) => i.product.id == item.product.id);
                                    _selections[section.sectionId] = currentList;
                                  }
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Prix Article", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text("${_currentTotal.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D3436))),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: () {
                      widget.onConfirm(CartItem(
                        product: widget.product,
                        price: widget.basePrice,
                        vatRate: widget.vatRate,
                        selectedOptions: _selections,
                      ));
                    },
                    child: const Text("VALIDER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
