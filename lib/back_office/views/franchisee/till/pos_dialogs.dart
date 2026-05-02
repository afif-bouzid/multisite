import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/repository/repository.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../core/services/printing_service.dart';
import '/models.dart';

class PosData {
  final List<MasterProduct> products;
  final Map<String, FranchiseeMenuItem> menuSettings;
  final List<ProductFilter> productFilters;
  final List<KioskCategory> kioskCategories;
  final List<ProductSection> allSections;
  final PrinterConfig printerConfig;
  PosData({
    required this.products,
    required this.menuSettings,
    required this.productFilters,
    required this.kioskCategories,
    required this.allSections,
    required this.printerConfig,
  });
}

class PosOptionSelectorDialog extends StatelessWidget {
  final MasterProduct product;
  final FranchiseeMenuItem settings;
  const PosOptionSelectorDialog(
      {super.key, required this.product, required this.settings});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        "CHOISIR LA FORMULE : ${product.name.toUpperCase()}",
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: AppColors.bkBlack),
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemCount: product.options.length,
          itemBuilder: (context, index) {
            final opt = product.options[index];
            final price = settings.optionPrices[opt.id] ?? settings.price;
            return Material(
              color: AppColors.bkOffWhite,
              elevation: 4,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade300, width: 1)),
              child: InkWell(
                onTap: () => Navigator.pop(context, opt),
                borderRadius: BorderRadius.circular(16),
                splashColor: AppColors.bkYellow.withOpacity(0.3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.grey.shade200, blurRadius: 4)
                          ],
                        ),
                        child: const Icon(Icons.restaurant_menu_rounded,
                            size: 32, color: AppColors.bkBlack),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.name.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: AppColors.bkBlack),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${price.toStringAsFixed(2)} €",
                              style: const TextStyle(
                                  color: AppColors.bkBlack,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actionsPadding: const EdgeInsets.all(24),
      actions: [
        SizedBox(
          height: 60,
          width: double.infinity,
          child: OutlinedButton(
              onPressed: () => Navigator.pop(context, null),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.grey, width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("ANNULER",
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                      fontWeight: FontWeight.bold))),
        )
      ],
    );
  }
}

class CompositeProductDialog extends StatefulWidget {
  final MasterProduct product;
  final String franchiseeId;
  final double basePrice;
  final double vatRate;
  final List<ProductSection> allSections;
  final ProductOption? initialOption;
  final Map<String, List<SectionItem>>? initialSelectedOptions;
  final List<String>? initialRemovedIngredients;
  const CompositeProductDialog({
    super.key,
    required this.product,
    required this.franchiseeId,
    required this.basePrice,
    required this.vatRate,
    required this.allSections,
    this.initialOption,
    this.initialSelectedOptions,
    this.initialRemovedIngredients,
  });
  @override
  State<CompositeProductDialog> createState() => _CompositeProductDialogState();
}

class _CompositeProductDialogState extends State<CompositeProductDialog> {
  late List<ProductSection> _relevantSections = [];
  ProductOption? _selectedOption;
  final Map<String, List<SectionItem>> _selectedOptions = {};
  Map<String, double> _supplementOverrides = {};
  List<MasterProduct> _baseIngredients = [];
  final List<String> _removedIngredientProductIds = [];
  bool _isLoadingIngredients = false;
  bool _isLoadingSections = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialOption != null) {
      _selectedOption = widget.initialOption;
    } else if (widget.product.options.isNotEmpty) {
      _selectedOption = widget.product.options.first;
    }
    if (widget.initialSelectedOptions != null) {
      widget.initialSelectedOptions!.forEach((key, list) {
        _selectedOptions[key] = List.from(list);
      });
    }
    if (widget.initialRemovedIngredients != null) {
      _removedIngredientProductIds.addAll(widget.initialRemovedIngredients!);
    }
    _loadSections();
    _loadSupplementOverrides();
    if (widget.product.ingredientProductIds.isNotEmpty) {
      _loadBaseIngredients();
    }
  }

  void _loadSections() {
    setState(() => _isLoadingSections = true);
    final List<String> sectionsToDisplayIds =
        _selectedOption != null && _selectedOption!.sectionIds.isNotEmpty
            ? _selectedOption!.sectionIds
            : widget.product.sectionIds;
    List<ProductSection> sections = widget.allSections
        .where((s) => sectionsToDisplayIds.contains(s.sectionId))
        .toList();
    sections.sort((a, b) {
      int indexA = widget.product.sectionIds.indexOf(a.sectionId);
      int indexB = widget.product.sectionIds.indexOf(b.sectionId);
      if (indexA == -1) indexA = 999;
      if (indexB == -1) indexB = 999;
      return indexA.compareTo(indexB);
    });
    setState(() {
      _relevantSections = sections;
      _isLoadingSections = false;
    });
  }

  Widget _buildOptionsSelector() {
    if (widget.product.options.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.product.options.length,
        separatorBuilder: (c, i) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final option = widget.product.options[index];
          final isSelected = _selectedOption?.id == option.id;
          return ChoiceChip(
            label: Text(option.name.toUpperCase()),
            selected: isSelected,
            selectedColor: AppColors.bkYellow,
            backgroundColor: Colors.grey.shade100,
            labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.black87,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal),
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedOption = option;
                  _selectedOptions.clear();
                });
                _loadSections();
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _loadBaseIngredients() async {
    setState(() => _isLoadingIngredients = true);
    try {
      List<MasterProduct> loadedIngredients = [];
      List<String> ids = widget.product.ingredientProductIds;
      for (var i = 0; i < ids.length; i += 10) {
        final end = (i + 10 < ids.length) ? i + 10 : ids.length;
        final sublist = ids.sublist(i, end);
        final snapshot = await FirebaseFirestore.instance
            .collection('master_products')
            .where('productId', whereIn: sublist)
            .get();
        for (var doc in snapshot.docs) {
          loadedIngredients
              .add(MasterProduct.fromFirestore(doc.data(), doc.id));
        }
      }
      if (mounted) setState(() => _baseIngredients = loadedIngredients);
    } catch (e) {
      debugPrint("Erreur chargement ingrédients: $e");
    } finally {
      if (mounted) setState(() => _isLoadingIngredients = false);
    }
  }

  Future<void> _loadSupplementOverrides() async {
    try {
      final overridesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.franchiseeId)
          .collection('menu')
          .doc(widget.product.productId)
          .collection('supplement_overrides')
          .get();
      if (mounted) {
        setState(() => _supplementOverrides = {
              for (var doc in overridesSnapshot.docs)
                doc.id: (doc.data()['price'] as num?)?.toDouble() ?? 0.0
            });
      }
    } catch (_) {}
  }

  void _onOptionSelected(ProductSection section, SectionItem item) {
    setState(() {
      final sectionId = section.sectionId;
      if (!_selectedOptions.containsKey(sectionId)) {
        _selectedOptions[sectionId] = [];
      }
      List<SectionItem> selections = _selectedOptions[sectionId]!;
      final isSelected = selections.any((i) => i.product.id == item.product.id);
      if (section.type == 'radio') {
        _selectedOptions[sectionId] = [item];
      } else if (section.type == 'checkbox') {
        if (isSelected) {
          selections.removeWhere((i) => i.product.id == item.product.id);
        } else {
          if (selections.length >= section.selectionMax) {
            _showMaxSnackBar(section.selectionMax);
          } else {
            selections.add(item);
          }
        }
      }
    });
  }

  void _onIncrementOption(ProductSection section, SectionItem item, int delta) {
    setState(() {
      final sectionId = section.sectionId;
      if (!_selectedOptions.containsKey(sectionId)) {
        _selectedOptions[sectionId] = [];
      }
      List<SectionItem> selections = _selectedOptions[sectionId]!;
      int qty = selections.where((i) => i.product.id == item.product.id).length;
      if (delta > 0) {
        if (selections.length < section.selectionMax) {
          selections.add(item);
        } else {
          _showMaxSnackBar(section.selectionMax);
        }
      } else if (qty > 0) {
        final index =
            selections.indexWhere((i) => i.product.id == item.product.id);
        if (index != -1) selections.removeAt(index);
      }
    });
  }

  void _showMaxSnackBar(int max) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Maximum de $max choix atteint.",
          style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: Colors.red.shade800,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
    ));
  }

  double _getFinalSupplementPrice(SectionItem item) =>
      _supplementOverrides[item.product.productId] ?? item.supplementPrice;
  bool _areMinimumsMet() {
    for (var section in _relevantSections) {
      if ((_selectedOptions[section.sectionId]?.length ?? 0) <
          section.selectionMin) {
        return false;
      }
    }
    return true;
  }

  void _validateAndClose() {
    double currentTotal =
        widget.basePrice + (_selectedOption?.priceOverride ?? 0.0);
    _selectedOptions.forEach((_, items) {
      for (var item in items) {
        currentTotal += _getFinalSupplementPrice(item);
      }
    });
    final cartItem = CartItem(
      product: widget.product,
      price: widget.basePrice + (_selectedOption?.priceOverride ?? 0.0),
      vatRate: widget.vatRate,
      selectedOptions: _selectedOptions,
      removedIngredientProductIds: _removedIngredientProductIds,
      removedIngredientNames: _baseIngredients
          .where((p) => _removedIngredientProductIds.contains(p.productId))
          .map((p) => p.name)
          .toList(),
    );
    Navigator.pop(context, cartItem);
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double currentTotal =
        widget.basePrice + (_selectedOption?.priceOverride ?? 0.0);
    _selectedOptions.forEach((_, items) {
      for (var item in items) {
        currentTotal += _getFinalSupplementPrice(item);
      }
    });
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("COMPOSITION : ${widget.product.name.toUpperCase()}",
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  color: AppColors.bkBlack)),
          const Divider(thickness: 2, color: AppColors.bkBlack),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: screenHeight * 0.85,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOptionsSelector(),
              if (_isLoadingIngredients || _isLoadingSections)
                const LinearProgressIndicator(color: AppColors.bkYellow),
              if (_baseIngredients.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.shade100,
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    title: const Text("INGRÉDIENTS DE BASE",
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: _removedIngredientProductIds.isEmpty
                          ? const Text("Recette Standard",
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold))
                          : Text(
                              "SANS : ${_baseIngredients.where((p) => _removedIngredientProductIds.contains(p.productId)).map((p) => p.name).join(", ")}",
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                    ),
                    trailing: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.edit, size: 20),
                      label: const Text("MODIFIER"),
                      onPressed: () async {
                        final result = await showDialog<List<String>>(
                          context: context,
                          builder: (context) => _IngredientCustomizationDialog(
                            baseIngredients: _baseIngredients,
                            initiallyRemovedIds: _removedIngredientProductIds,
                          ),
                        );
                        if (result != null) {
                          setState(() {
                            _removedIngredientProductIds.clear();
                            _removedIngredientProductIds.addAll(result);
                          });
                        }
                      },
                    ),
                  ),
                ),
              if (_relevantSections.isEmpty && _baseIngredients.isEmpty)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                            "Aucune option disponible pour cette configuration.",
                            style:
                                TextStyle(color: Colors.grey, fontSize: 18)))),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.franchiseeId)
                    .collection('menu')
                    .snapshots(),
                builder: (context, snapshot) {
                  Map<String, bool> stockMap = {};
                  if (snapshot.hasData) {
                    for (var doc in snapshot.data!.docs) {
                      stockMap[doc.id] =
                          (doc.data() as Map<String, dynamic>)['isAvailable'] ??
                              true;
                    }
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _relevantSections.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 30),
                    itemBuilder: (context, index) {
                      final section = _relevantSections[index];
                      final selections =
                          _selectedOptions[section.sectionId] ?? [];
                      final isMinMet =
                          selections.length >= section.selectionMin;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: isMinMet
                                  ? AppColors.bkBlack
                                  : Colors.red.shade700,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    isMinMet
                                        ? Icons.check_circle
                                        : Icons.info_outline,
                                    color: Colors.white,
                                    size: 24),
                                const SizedBox(width: 12),
                                Text(
                                  "${section.title.toUpperCase()} (${selections.length} / ${section.selectionMax})",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.6,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: section.items.length,
                            itemBuilder: (context, itemIndex) {
                              final item = section.items[itemIndex];
                              final isAvailable =
                                  stockMap[item.product.productId] ?? true;
                              final supplement = _getFinalSupplementPrice(item);
                              int qty = 0;
                              bool isSelected = false;
                              if (section.type == 'increment') {
                                qty = selections
                                    .where(
                                        (i) => i.product.id == item.product.id)
                                    .length;
                                isSelected = qty > 0;
                              } else {
                                isSelected = selections.any(
                                    (i) => i.product.id == item.product.id);
                              }
                              final maxReached =
                                  selections.length >= section.selectionMax;
                              bool canInteract =
                                  isAvailable || isSelected || qty > 0;
                              bool isDisabled = !canInteract ||
                                  (section.type == 'increment' &&
                                      maxReached &&
                                      qty == 0) ||
                                  (section.type != 'increment' &&
                                      !isSelected &&
                                      maxReached &&
                                      section.type != 'radio');
                              return _buildOptionCard(
                                section: section,
                                item: item,
                                isSelected: isSelected,
                                isDisabled: isDisabled,
                                isAvailable: isAvailable,
                                quantity: qty,
                                supplementPrice: supplement,
                                onTap: () {
                                  if (section.type == 'increment') {
                                    _onIncrementOption(section, item, 1);
                                  } else {
                                    _onOptionSelected(section, item);
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.all(24),
      actions: [
        SizedBox(
          height: 60,
          child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ANNULER",
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                      fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 16),
        SizedBox(
          height: 60,
          width: 250,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _areMinimumsMet() ? AppColors.bkYellow : Colors.grey.shade300,
              foregroundColor: AppColors.bkBlack,
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _areMinimumsMet() ? _validateAndClose : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("AJOUTER",
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                if (currentTotal > 0) ...[
                  const VerticalDivider(
                      width: 24, thickness: 1, color: Colors.black26),
                  Text("${currentTotal.toStringAsFixed(2)} €",
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 18)),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required ProductSection section,
    required SectionItem item,
    required bool isSelected,
    required bool isDisabled,
    required bool isAvailable,
    required int quantity,
    required double supplementPrice,
    required VoidCallback onTap,
  }) {
    final bool isActive = isSelected || quantity > 0;
    return Material(
      elevation: isActive ? 3 : 1,
      color: isDisabled
          ? Colors.grey.shade50
          : (isActive ? AppColors.bkYellow : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isDisabled
                ? Colors.transparent
                : (isActive ? Colors.black : Colors.grey.shade300),
            width: isActive ? 2 : 1),
      ),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (section.type != 'increment')
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: section.type == 'radio'
                      ? Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isDisabled ? Colors.grey : Colors.black)
                      : Icon(
                          isSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: isDisabled ? Colors.grey : Colors.black),
                ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isActive ? FontWeight.w900 : FontWeight.w600,
                        color: isDisabled ? Colors.grey : Colors.black,
                        decoration:
                            !isAvailable ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (!isAvailable)
                      const Text("ÉPUISÉ",
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                    if (supplementPrice > 0 && isAvailable)
                      Text("+ ${supplementPrice.toStringAsFixed(2)} €",
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54)),
                  ],
                ),
              ),
              if (section.type == 'increment')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIncBtn(Icons.remove, quantity > 0,
                        () => _onIncrementOption(section, item, -1),
                        isRed: true),
                    SizedBox(
                        width: 32,
                        child: Center(
                            child: Text("$quantity",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18)))),
                    _buildIncBtn(Icons.add, !isDisabled && isAvailable,
                        () => _onIncrementOption(section, item, 1)),
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncBtn(IconData icon, bool enabled, VoidCallback onTap,
      {bool isRed = false}) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: enabled
              ? (isRed ? Colors.red.shade100 : Colors.black)
              : Colors.grey.shade200,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 16,
            color: enabled ? (isRed ? Colors.red : Colors.white) : Colors.grey),
      ),
    );
  }
}

class PaidOrdersHistoryDialog extends StatefulWidget {
  final String franchiseeId;
  const PaidOrdersHistoryDialog({super.key, required this.franchiseeId});
  @override
  State<PaidOrdersHistoryDialog> createState() =>
      _PaidOrdersHistoryDialogState();
}

class _PaidOrdersHistoryDialogState extends State<PaidOrdersHistoryDialog> {
  final FranchiseRepository _repository = FranchiseRepository();
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF4F6F8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_edu, size: 28),
                const SizedBox(width: 12),
                const Text("Historique Session en cours",
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, size: 28),
                    onPressed: () => Navigator.pop(context))
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<TillSession?>(
              stream: _repository.getActiveSession(widget.franchiseeId),
              builder: (context, sessionSnapshot) {
                if (!sessionSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (sessionSnapshot.data == null) {
                  return const Center(child: Text("Aucune session active"));
                }
                return StreamBuilder<List<Transaction>>(
                  stream: _repository.getTransactionsInDateRange(
                    widget.franchiseeId,
                    startDate: sessionSnapshot.data!.openingTime,
                    endDate: DateTime.now(),
                  ),
                  builder: (context, transSnapshot) {
                    final transactions = transSnapshot.data ?? [];
                    if (transactions.isEmpty) {
                      return const Center(
                          child: Text("Aucune commande enregistrée."));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.receipt,
                                  color: Colors.blue.shade800),
                            ),
                            title: Text(
                              tx.identifier.isNotEmpty
                                  ? tx.identifier
                                  : "Ticket #${tx.id.substring(0, 5).toUpperCase()}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                                DateFormat('dd/MM HH:mm').format(tx.timestamp)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${tx.total.toStringAsFixed(2)} €",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16)),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right,
                                    color: Colors.grey),
                              ],
                            ),
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) =>
                                    TransactionDetailsDialog(transaction: tx),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionDetailsDialog extends StatefulWidget {
  final Transaction transaction;
  const TransactionDetailsDialog({super.key, required this.transaction});
  @override
  State<TransactionDetailsDialog> createState() =>
      _TransactionDetailsDialogState();
}

class _TransactionDetailsDialogState extends State<TransactionDetailsDialog> {
  final FranchiseRepository _repository = FranchiseRepository();
  bool _isReprinting = false;
  static const Color primaryColor = AppColors.bkBlack;
  Future<void> _handleReprint(BuildContext context,
      {required bool isKitchen}) async {
    if (mounted) setState(() => _isReprinting = true);
    try {
      final printingService = PrintingService();
      final Map<String, dynamic> printerConfig = {
        'isBluetooth': true,
        'paperWidth': '80',
      };
      if (isKitchen) {
        await printingService.printKitchenTicketSafe(
          printerConfig: printerConfig,
          itemsToPrint: widget.transaction.items,
          identifier: widget.transaction.identifier.isNotEmpty
              ? widget.transaction.identifier
              : "TICKET",
          isReprint: true,
        );
      } else {
        await printingService.printReceipt(
          printerConfig: printerConfig,
          transaction: widget.transaction,
          franchisee: {},
          receiptConfig: {},
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Impression envoyée"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Erreur impression: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isReprinting = false);
      }
    }
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, Color valueColor) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text("$label: ",
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.grey)),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                    overflow: TextOverflow.ellipsis))),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amount, bool isBold,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: Colors.black87)),
          Text("${amount.toStringAsFixed(2)} €",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color ?? Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortId = widget.transaction.id.substring(0, 5).toUpperCase();
    final orderTypeLabel = (widget.transaction.orderType == 'takeaway')
        ? "À Emporter"
        : "Sur Place";
    final paymentLabel = widget.transaction.paymentMethods.keys.join(', ');
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Détails Commande",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(thickness: 1.5, color: primaryColor),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.confirmation_number, "Ticket",
                        "#$shortId", Colors.black87),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                        Icons.access_time,
                        "Date",
                        DateFormat('dd/MM/yyyy HH:mm')
                            .format(widget.transaction.timestamp),
                        Colors.black87),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                        (widget.transaction.orderType == 'takeaway')
                            ? Icons.shopping_bag
                            : Icons.restaurant,
                        "Type",
                        orderTypeLabel,
                        Colors.black87),
                    const SizedBox(height: 20),
                    const Text("Articles",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryColor)),
                    const SizedBox(height: 10),
                    ...widget.transaction.items.map((item) {
                      final name = item['name'] ?? 'Inconnu';
                      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                      final double totalItem =
                          (item['total'] as num?)?.toDouble() ?? 0.0;
                      List<dynamic> optionsGroups = [];
                      if (item['options'] is List) {
                        optionsGroups = item['options'];
                      } else if (item['selectedOptions'] is List) {
                        optionsGroups = item['selectedOptions'];
                      }
                      List<dynamic> removedIngredients = [];
                      if (item['removedIngredientNames'] is List) {
                        removedIngredients = item['removedIngredientNames'];
                      } else if (item['removedIngredients'] is List) {
                        removedIngredients = item['removedIngredients'];
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(quantity > 1 ? "${quantity}x $name" : name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text("${totalItem.toStringAsFixed(2)} €",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                            if (removedIngredients.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                    "Sans: ${removedIngredients.join(', ')}",
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic)),
                              ),
                            if (optionsGroups.isNotEmpty)
                              ...optionsGroups.map((opt) {
                                if (opt is Map) {
                                  if (opt['items'] is List) {
                                    return Column(
                                      children: (opt['items'] as List)
                                          .map<Widget>((subOpt) {
                                        final subName = subOpt['name'] ?? '';
                                        final subPrice =
                                            (subOpt['supplementPrice'] as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                        return _buildOptionLine(
                                            subName, subPrice);
                                      }).toList(),
                                    );
                                  } else {
                                    final subName = opt['name'] ?? '';
                                    final subPrice =
                                        (opt['price'] as num?)?.toDouble() ??
                                            0.0;
                                    return _buildOptionLine(subName, subPrice);
                                  }
                                } else if (opt is String) {
                                  return _buildOptionLine(opt, 0.0);
                                }
                                return const SizedBox.shrink();
                              }),
                            const Divider(color: Color(0xFFEEEEEE)),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildSummaryRow("Sous-total", widget.transaction.subTotal, false),
            if (widget.transaction.discountAmount > 0.01)
              _buildSummaryRow(
                  "Remise", -widget.transaction.discountAmount, false,
                  color: Colors.red),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOTAL PAYÉ",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryColor)),
                Text("${widget.transaction.total.toStringAsFixed(2)} €",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryColor)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payment, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text("Payé via $paymentLabel",
                    style: const TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(thickness: 1.5, height: 30),
            const Text("Actions Rapides",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 10),
            if (_isReprinting)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator()))
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () =>
                          _handleReprint(context, isKitchen: false),
                      icon: const Icon(Icons.receipt),
                      label: const Text("Ticket Caisse"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _handleReprint(context, isKitchen: true),
                      icon:
                          const Icon(Icons.soup_kitchen, color: Colors.orange),
                      label: const Text("Ticket Cuisine"),
                    ),
                  ),
                ],
              )
          ],
        ),
      ),
    );
  }

  Widget _buildOptionLine(String name, double price) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("• $name",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          if (price > 0)
            Text("+${price.toStringAsFixed(2)} €",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }
}

class StockManagementDialog extends StatefulWidget {
  final String franchisorId;
  final String franchiseeId;
  final Map<String, FranchiseeMenuItem> menuSettings;
  final Function(String, bool) onStockChanged;
  const StockManagementDialog({
    super.key,
    required this.franchisorId,
    required this.franchiseeId,
    required this.menuSettings,
    required this.onStockChanged,
  });
  @override
  State<StockManagementDialog> createState() => _StockManagementDialogState();
}

class _StockManagementDialogState extends State<StockManagementDialog> {
  List<MasterProduct> _products = [];
  List<ProductFilter> _filters = [];
  bool _isLoading = true;
  bool _modeIngredients = false;
  String _search = "";
  String? _selectedFilterId;
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {

    final repo = FranchiseRepository();
    try {
      final results = await Future.wait([
        repo.getMasterProductsStream(widget.franchisorId).first,
        repo.getFiltersStream(widget.franchisorId).first,
      ]);
      if (mounted) {
        setState(() {
          _products = results[0] as List<MasterProduct>;
          _filters = results[1] as List<ProductFilter>;
          _filters.sort((a, b) => a.name.compareTo(b.name));
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
          child: SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator())));
    }
    final menuRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.franchiseeId)
        .collection('menu');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 800,
        height: 900,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_rounded,
                    size: 32, color: Colors.blueGrey),
                const SizedBox(width: 12),
                const Text("Gestion des Stocks & Ruptures",
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, size: 32),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                    child: _buildTabButton(
                        "Produits Carte",
                        !_modeIngredients,
                        () => setState(() {
                              _modeIngredients = false;
                              _selectedFilterId = null;
                            }))),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildTabButton(
                        "Ingrédients",
                        _modeIngredients,
                        () => setState(() {
                              _modeIngredients = true;
                              _selectedFilterId = null;
                            }))),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              decoration: InputDecoration(
                hintText: "Rechercher...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: (val) => setState(() => _search = val.toLowerCase()),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: menuRef.snapshots(),
                builder: (context, snapshot) {
                  Map<String, FranchiseeMenuItem> activeSettings =
                      widget.menuSettings;
                  if (snapshot.hasData) {
                    activeSettings = Map.fromEntries(snapshot.data!.docs.map(
                        (doc) => MapEntry(
                            doc.id,
                            FranchiseeMenuItem.fromFirestore(
                                doc.data() as Map<String, dynamic>))));
                  }
                  final filtered = _products.where((p) {
                    final settings = activeSettings[p.productId];
                    if (settings == null) return false;
                    if (!_modeIngredients) {
                      if (p.isIngredient || !settings.isVisible) return false;
                    } else {
                      if (!p.isIngredient) return false;
                    }
                    if (_search.isNotEmpty &&
                        !p.name.toLowerCase().contains(_search)) {
                      return false;
                    }
                    if (_selectedFilterId != null &&
                        !p.filterIds.contains(_selectedFilterId)) {
                      return false;
                    }
                    return true;
                  }).toList();
                  filtered.sort((a, b) => a.name.compareTo(b.name));
                  final activeFilters =
                      filtered.expand((p) => p.filterIds).toSet();
                  final visibleFilters = _filters
                      .where((f) => activeFilters.contains(f.id))
                      .toList();
                  return Column(
                    children: [
                      if (visibleFilters.isNotEmpty)
                        SizedBox(
                          height: 50,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildFilterChip(
                                  "Tout",
                                  _selectedFilterId == null,
                                  () =>
                                      setState(() => _selectedFilterId = null)),
                              ...visibleFilters.map((f) => _buildFilterChip(
                                  f.name,
                                  _selectedFilterId == f.id,
                                  () => setState(
                                      () => _selectedFilterId = f.id))),
                            ],
                          ),
                        ),
                      if (visibleFilters.isNotEmpty) const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text("Aucun produit trouvé",
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 18)))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final product = filtered[index];
                                  final settings =
                                      activeSettings[product.productId];
                                  final isAvailable =
                                      settings?.isAvailable ?? false;
                                  return Card(
                                    elevation: 0,
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                            color: Colors.grey.shade200)),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            clipBehavior: Clip.antiAlias,
                                            child: (product
                                                        .photoUrl?.isNotEmpty ??
                                                    false)
                                                ? CachedNetworkImage(
                                                    imageUrl: product.photoUrl!,
                                                    fit: BoxFit.cover)
                                                : Icon(
                                                    product.isIngredient
                                                        ? Icons.blender
                                                        : Icons.fastfood,
                                                    color:
                                                        Colors.grey.shade400),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(product.name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16)),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              menuRef
                                                  .doc(product.productId)
                                                  .set({
                                                'isAvailable': !isAvailable
                                              }, SetOptions(merge: true));
                                              widget.onStockChanged(
                                                  product.productId,
                                                  !isAvailable);
                                            },
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12),
                                              decoration: BoxDecoration(
                                                color: isAvailable
                                                    ? Colors.green.shade50
                                                    : Colors.red.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: isAvailable
                                                        ? Colors.green
                                                        : Colors.red,
                                                    width: 2),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                      isAvailable
                                                          ? Icons.check_circle
                                                          : Icons.block,
                                                      color: isAvailable
                                                          ? Colors.green
                                                          : Colors.red,
                                                      size: 20),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    isAvailable
                                                        ? "EN STOCK"
                                                        : "ÉPUISÉ",
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isAvailable
                                                            ? Colors
                                                                .green.shade800
                                                            : Colors
                                                                .red.shade800),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String text, bool isActive, VoidCallback onTap) {
    return Material(
      color: isActive ? AppColors.bkBlack : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isActive
              ? BorderSide.none
              : const BorderSide(color: Colors.black12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(text,
              style: TextStyle(
                  color: isActive ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: Colors.blue.shade100,
        backgroundColor: Colors.white,
        side: isSelected
            ? BorderSide(color: Colors.blue.shade800)
            : const BorderSide(color: Colors.black12),
        labelStyle: TextStyle(
            color: isSelected ? Colors.blue.shade900 : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600),
      ),
    );
  }
}

class _IngredientCustomizationDialog extends StatefulWidget {
  final List<MasterProduct> baseIngredients;
  final List<String> initiallyRemovedIds;
  const _IngredientCustomizationDialog(
      {required this.baseIngredients, required this.initiallyRemovedIds});
  @override
  State<_IngredientCustomizationDialog> createState() =>
      _IngredientCustomizationDialogState();
}

class _IngredientCustomizationDialogState
    extends State<_IngredientCustomizationDialog> {
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
      title: const Text("Personnaliser les ingrédients",
          style: TextStyle(fontWeight: FontWeight.bold)),
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
              subtitle: Text(
                  isKept ? "Inclus dans la recette" : "Retiré par le client"),
              trailing: Switch(
                value: isKept,
                activeThumbColor: Colors.green,
                onChanged: (bool value) => setState(() => value
                    ? _removedIds.remove(ingredient.productId)
                    : _removedIds.add(ingredient.productId)),
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
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bkBlack,
              foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, _removedIds.toList()),
          child: const Text("Valider"),
        ),
      ],
    );
  }
}

class PaymentSuccessDialog extends StatelessWidget {
  const PaymentSuccessDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppColors.bkGreen, size: 100),
            SizedBox(height: 24),
            Text("PAIEMENT VALIDÉ",
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.bkBlack)),
          ],
        ),
      ),
    );
  }
}

class CombineLatestStream<T, R> extends Stream<R> {
  final List<Stream<T>> streams;
  CombineLatestStream(this.streams);
  @override
  StreamSubscription<R> listen(void Function(R event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<R>.fromFuture(
            Future.wait(streams.map((s) => s.first)) as Future<R>)
        .listen(onData,
            onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
