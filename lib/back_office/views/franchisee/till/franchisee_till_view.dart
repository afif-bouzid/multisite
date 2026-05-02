import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:ouiborne/back_office/views/franchisee/till/pos_dialogs.dart';
import 'package:ouiborne/back_office/views/franchisee/till/widgets/cart_panel.dart';
import 'package:ouiborne/back_office/views/franchisee/till/widgets/product_view_content.dart';
import 'package:provider/provider.dart';

// Imports Core
import '../../../../../core/auth_provider.dart';
import '../../../../core/services/printing_service.dart';
import '/models.dart';
import '../../../../../core/repository/repository.dart';

class FranchiseeTillView extends StatefulWidget {
  const FranchiseeTillView({super.key});

  @override
  State<FranchiseeTillView> createState() => _FranchiseeTillViewState();
}

class _FranchiseeTillViewState extends State<FranchiseeTillView> {
  // Variable pour écouter les commandes de la borne
  StreamSubscription? _kioskOrdersSubscription;
  final Set<String> _printedOrders = {};

  // LE BOUCLIER : Détecte si c'est le tout premier chargement
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    // On lance l'écoute des commandes dès que l'écran de caisse s'initialise
    _startListeningToKioskOrders();
  }

  @override
  void dispose() {
    // Très important : on coupe l'écoute quand on quitte la caisse
    _kioskOrdersSubscription?.cancel();
    super.dispose();
  }

  // --- LOGIQUE MÉTIER : DÉTECTION DES PAIEMENTS BORNE & WEB ET IMPRESSION AUTO ---
  void _startListeningToKioskOrders() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final franchiseeId = authProvider.franchiseUser?.effectiveStoreId;
      if (franchiseeId == null) return;

      _kioskOrdersSubscription = FirebaseFirestore.instance
          .collection('pending_orders')
          .where('franchiseeId', isEqualTo: franchiseeId)
          .snapshots()
          .listen((snapshot) async {
        // --- CORRECTION : IGNORER LES COMMANDES AU REDÉMARRAGE ---
        if (_isFirstLoad) {
          // On prend tous les documents qui sont DÉJÀ dans la base au démarrage
          for (var doc in snapshot.docs) {
            // On les ajoute à la mémoire silencieusement sans imprimer
            _printedOrders.add(doc.id);
          }
          _isFirstLoad = false; // On désactive le bouclier
          debugPrint(
              "🚀 Démarrage caisse : ${_printedOrders.length} anciennes commandes bloquées pour impression.");
          return; // On arrête l'exécution ici pour ce premier tour
        }
        // ---------------------------------------------------------

        for (var change in snapshot.docChanges) {
          // On écoute maintenant les AJOUTS (added) ET les MISES À JOUR (modified)
          if (change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified) {
            final newOrder = PendingOrder.fromFirestore(change.doc);

            // LOGIQUE MÉTIER : Ça vient de la borne OU du Click&Collect ET c'est payé
            if ((newOrder.source == 'borne' || newOrder.source == 'kiosk' || newOrder.source == 'click_and_collect') &&
                newOrder.isPaid) {
              // SÉCURITÉ : On vérifie que ce ticket n'a pas DÉJÀ été imprimé
              if (!_printedOrders.contains(newOrder.id)) {
                // On l'ajoute à la mémoire pour bloquer les futures impressions de ce ticket
                _printedOrders.add(newOrder.id);

                try {
                  final printerConfig = await FranchiseRepository()
                      .getPrinterConfigStream(franchiseeId)
                      .first;

                  await PrintingService().printKitchenTicketSafe(
                      printerConfig: printerConfig,
                      itemsToPrint: newOrder.itemsAsMap,
                      identifier: newOrder.identifier,
                      orderType: newOrder.orderType,
                      // ON ENVOIE LE NOM DU RESTAURANT ICI :
                      franchisee: {
                        'companyName': authProvider.franchiseUser?.companyName,
                        'restaurantName':
                        authProvider.franchiseUser?.restaurantName,
                      });

                  debugPrint(
                      "🖨️ ✅ Impression auto cuisine lancée en direct pour : ${newOrder.identifier}");
                } catch (e) {
                  debugPrint(
                      "❌ Erreur lors de l'impression auto en cuisine : $e");
                }
              }
            }
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final franchiseeId = authProvider.franchiseUser!.effectiveStoreId;
    final repository = FranchiseRepository();

    return StreamBuilder<TillSession?>(
      stream: repository.getActiveSession(franchiseeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text("Erreur chargement session: ${snapshot.error}")));
        }

        final activeSession = snapshot.data;

        if (activeSession == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Ouvrir la Caisse")),
            body: Center(child: TillOpenForm(franchiseeId: franchiseeId)),
          );
        } else {
          return _PosContent(
            activeSession: activeSession,
            franchiseeId: franchiseeId,
            franchisorId: authProvider.franchiseUser?.franchisorId ?? '',
          );
        }
      },
    );
  }
}

class _PosContent extends StatefulWidget {
  final TillSession activeSession;
  final String franchiseeId;
  final String franchisorId;

  const _PosContent({
    required this.activeSession,
    required this.franchiseeId,
    required this.franchisorId,
  });

  @override
  State<_PosContent> createState() => _PosContentState();
}

class _PosContentState extends State<_PosContent> {
  Future<PosData>? _posDataFutureState;

  @override
  void initState() {
    super.initState();
    _posDataFutureState = _loadData();
  }

  Future<PosData> _loadData() async {
    final repo = FranchiseRepository();
    final firestore = FirebaseFirestore.instance;

    try {
      final results = await Future.wait([
        repo.getFiltersStream(widget.franchisorId).first,
        repo.getKioskCategoriesStream(widget.franchisorId).first,
        repo.getSectionsStream(widget.franchisorId).first,
        repo.getPrinterConfigStream(widget.franchiseeId).first,
        firestore
            .collection('users')
            .doc(widget.franchiseeId)
            .collection('config')
            .doc('filterOrder')
            .get(),
        repo
            .getFranchiseeVisibleProductsStream(
            widget.franchiseeId, widget.franchisorId)
            .first,
        firestore
            .collection('users')
            .doc(widget.franchiseeId)
            .collection('menu')
            .get(),
      ]);

      var productFilters = results[0] as List<ProductFilter>;
      var kioskCategories = results[1] as List<KioskCategory>;
      final allSections = results[2] as List<ProductSection>;
      final printerConfig = results[3] as PrinterConfig;
      final filterOrderDoc = results[4] as DocumentSnapshot;
      final visibleProducts = results[5] as List<MasterProduct>;
      final menuSnapshot = results[6] as QuerySnapshot;

      // Tri des catégories
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

      // Tri des produits
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
              body: Center(child: CircularProgressIndicator()));
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
        // Détection Tablette (Surface Pro en paysage > 900px)
        final bool isTablet = MediaQuery.of(context).size.width >= 900;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ZONE GAUCHE : Catalogue Produits
              Expanded(
                flex: 7,
                child: ProductViewContent(
                    posData: posData,
                    franchiseeId: widget.franchiseeId,
                    isTablet: isTablet),
              ),

              // ZONE DROITE : Panier / Ticket
              if (isTablet)
                Expanded(
                  flex: 3,
                  child: CartPanel(
                    posData: posData,
                    franchiseeId: widget.franchiseeId,
                    franchisorId: widget.franchisorId,
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

// --- Formulaire d'ouverture de caisse (Si aucune session active) ---
class TillOpenForm extends StatefulWidget {
  final String franchiseeId;

  const TillOpenForm({super.key, required this.franchiseeId});

  @override
  State<TillOpenForm> createState() => _TillOpenFormState();
}

class _TillOpenFormState extends State<TillOpenForm> {
  final _formKey = GlobalKey<FormState>();
  final _initialCashController = TextEditingController(text: '0.00');
  bool _isLoading = false;

  Future<void> _openTill() async {
    if (!_formKey.currentState!.validate()) return;
    final initialCash =
    double.tryParse(_initialCashController.text.replaceAll(',', '.'));
    if (initialCash == null || initialCash < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Montant invalide."),
            backgroundColor: Colors.orange));
      }
      return;
    }
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    try {
      await repository.openTillSession(
          franchiseeId: widget.franchiseeId, initialCash: initialCash);

      // ✅ Reset le compteur de commandes des bornes
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.franchiseeId)
          .collection('config')
          .doc('session_order_counter')
          .set({'count': 0, 'daily_queue': []});

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 60, color: Color(0xFF2C3E50)),
                  const SizedBox(height: 16),
                  Text("Ouverture de Caisse",
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _initialCashController,
                    decoration: const InputDecoration(
                        labelText: "Fonds de caisse initial (€)",
                        prefixIcon: Icon(Icons.euro_symbol)),
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _openTill,
                      icon: _isLoading
                          ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: const Text("Démarrer la Session"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF27AE60),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}