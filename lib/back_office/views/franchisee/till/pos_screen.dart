import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/auth_provider.dart';
import '../../../../../core/models/models.dart';
import '../../../../../core/repository/repository.dart';
import 'pos_dialogs.dart';
import 'widgets/cart_panel.dart';
import 'widgets/product_view_content.dart';

class PosView extends StatefulWidget {
  final TillSession activeSession;
  final String? franchiseeId;
  final String? franchisorId;

  const PosView({
    super.key,
    required this.activeSession,
    this.franchiseeId,
    this.franchisorId,
  });

  @override
  State<PosView> createState() => _PosViewState();
}

class _PosViewState extends State<PosView> {
  Future<PosData>? _posDataFutureState;
  late String _effectiveFranchiseeId;
  late String _effectiveFranchisorId;
  final OrderType _orderType = OrderType.onSite;

  @override
  void initState() {
    super.initState();

    final auth = Provider.of<AuthProvider>(context, listen: false);

    _effectiveFranchiseeId =
        widget.franchiseeId ?? auth.franchiseUser!.effectiveStoreId;

    _effectiveFranchisorId =
        widget.franchisorId ?? (auth.franchiseUser?.franchisorId ?? '');
    _posDataFutureState = _loadData();
  }

  Future<PosData> _loadData() async {
    if (_effectiveFranchiseeId.isEmpty || _effectiveFranchisorId.isEmpty) {
      throw Exception("IDs manquants pour charger le POS.");
    }

    final repo = FranchiseRepository();
    final firestore = FirebaseFirestore.instance;

    try {
      final results = await Future.wait([
        repo.getFiltersStream(_effectiveFranchisorId).first,
        repo.getKioskCategoriesStream(_effectiveFranchisorId).first,
        repo.getSectionsStream(_effectiveFranchisorId).first,
        repo.getPrinterConfigStream(_effectiveFranchiseeId).first,
        firestore
            .collection('users')
            .doc(_effectiveFranchiseeId)
            .collection('config')
            .doc('filterOrder')
            .get(),
        firestore
            .collection('users')
            .doc(_effectiveFranchiseeId)
            .collection('sub_filter_orders')
            .get(),
        repo
            .getFranchiseeVisibleProductsStream(
                _effectiveFranchiseeId, _effectiveFranchisorId)
            .first,
        firestore
            .collection('users')
            .doc(_effectiveFranchiseeId)
            .collection('menu')
            .get(),
      ]);

      var productFilters = results[0] as List<ProductFilter>;
      var kioskCategories = results[1] as List<KioskCategory>;
      final allSections = results[2] as List<ProductSection>;
      final printerConfig = results[3] as PrinterConfig;
      final filterOrderDoc = results[4] as DocumentSnapshot;
      final visibleProducts = results[6] as List<MasterProduct>;
      final menuSnapshot = results[7] as QuerySnapshot;

      List<String> customFilterOrder = [];
      if (filterOrderDoc.exists &&
          (filterOrderDoc.data() as Map<String, dynamic>?)?['order'] is List) {
        customFilterOrder = List<String>.from(
            (filterOrderDoc.data() as Map<String, dynamic>)['order']);
      }

      if (customFilterOrder.isNotEmpty) {
        final categoryMap = {for (var c in kioskCategories) c.id: c};
        final sortedCategories = <KioskCategory>[];
        for (final categoryId in customFilterOrder) {
          if (categoryMap.containsKey(categoryId)) {
            sortedCategories.add(categoryMap[categoryId]!);
            categoryMap.remove(categoryId);
          }
        }
        final remaining = categoryMap.values.toList();
        remaining.sort((a, b) => a.position.compareTo(b.position));
        sortedCategories.addAll(remaining);
        kioskCategories = sortedCategories;
      } else {
        kioskCategories.sort((a, b) => a.position.compareTo(b.position));
      }

      productFilters.sort((a, b) => a.name.compareTo(b.name));

      final menuSettings = <String, FranchiseeMenuItem>{
        for (var doc in menuSnapshot.docs)
          doc.id: FranchiseeMenuItem.fromFirestore(
              doc.data() as Map<String, dynamic>)
      };

      visibleProducts.sort((a, b) {
        final settingsA = menuSettings[a.productId];
        final settingsB = menuSettings[b.productId];
        if (settingsA == null) return 1;
        if (settingsB == null) return -1;
        int posCompare = settingsA.position.compareTo(settingsB.position);
        if (posCompare != 0) return posCompare;
        return a.name.compareTo(b.name);
      });

      return PosData(
        products: visibleProducts,
        menuSettings: menuSettings,
        productFilters: productFilters,
        kioskCategories: kioskCategories,
        allSections: allSections,
        printerConfig: printerConfig,
      );
    } catch (e) {
      debugPrint("ERREUR CHARGEMENT POS: $e");
      rethrow;
    }
  }

  void _handleStockChange(String productId, bool isAvailable) {
    setState(() {
      _posDataFutureState = _posDataFutureState?.then((posData) {
        final currentSettings = posData.menuSettings[productId];
        if (currentSettings != null) {
          final newSettings = FranchiseeMenuItem(
              masterProductId: currentSettings.masterProductId,
              price: currentSettings.price,
              isVisible: currentSettings.isVisible,
              vatRate: currentSettings.vatRate,
              position: currentSettings.position,
              isAvailable: isAvailable,
              takeawayVatRate: currentSettings.takeawayVatRate,
              optionPrices: currentSettings.optionPrices,
              hidePriceOnCard: currentSettings.hidePriceOnCard,
              availableStartTime: currentSettings.availableStartTime,
              availableEndTime: currentSettings.availableEndTime);
          posData.menuSettings[productId] = newSettings;
        }
        return posData;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PosData>(
      future: _posDataFutureState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text("Erreur de chargement : ${snapshot.error}"),
                const SizedBox(height: 16),
                ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _posDataFutureState = _loadData();
                      });
                    },
                    child: const Text("Réessayer"))
              ],
            )),
          );
        }

        final posData = snapshot.data!;

        final bool isTablet = MediaQuery.of(context).size.width >= 900;

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: ProductViewContent(
                    posData: posData,
                    franchiseeId: _effectiveFranchiseeId,
                    isTablet: isTablet),
              ),
              if (isTablet)
                Expanded(
                  flex: 3,
                  child: CartPanel(
                    posData: posData,
                    franchiseeId: _effectiveFranchiseeId,
                    franchisorId: _effectiveFranchisorId,
                    activeSession: widget.activeSession,
                    isTablet: isTablet,
                    onStockChanged: _handleStockChange,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
