import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:ouiborne/back_office/views/franchisee/till/pos_dialogs.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; // Nécessaire pour le CacheManager custom

// --- IMPORTS ---
import '../../../../../core/auth_provider.dart';
import '../../../../../core/cart_provider.dart';
import '../../../../../core/repository/repository.dart';
import '../../../../models.dart';
import 'widgets/cart_panel.dart';

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
  String? _selectedCategoryId;

  // --- 1. CONFIGURATION DU CACHE PERSISTANT ---
  // On garde les images 1 an et jusqu'à 2000 fichiers pour éviter qu'elles ne s'effacent.
  static final customCacheManager = CacheManager(
    Config(
      'posImageCache', // Clé unique pour isoler ce cache
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 2000,
      repo: JsonCacheInfoRepository(databaseName: 'posImageCache'),
      fileService: HttpFileService(),
    ),
  );

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _effectiveFranchiseeId = widget.franchiseeId ?? auth.franchiseUser!.effectiveStoreId;
    _effectiveFranchisorId = widget.franchisorId ?? (auth.franchiseUser?.franchisorId ?? '');
    _posDataFutureState = _loadData();
  }

  // --- CHARGEMENT ---
  Future<PosData> _loadData() async {
    final repo = FranchiseRepository();
    final firestore = FirebaseFirestore.instance;

    final results = await Future.wait([
      repo.getFiltersStream(_effectiveFranchisorId).first,
      repo.getKioskCategoriesStream(_effectiveFranchisorId).first,
      repo.getSectionsStream(_effectiveFranchisorId).first,
      repo.getPrinterConfigStream(_effectiveFranchiseeId).first,
      firestore.collection('users').doc(_effectiveFranchiseeId).collection('config').doc('filterOrder').get(),
      repo.getFranchiseeVisibleProductsStream(_effectiveFranchiseeId, _effectiveFranchisorId).first,
      firestore.collection('users').doc(_effectiveFranchiseeId).collection('menu').get(),
    ]);

    final visibleProducts = results[5] as List<MasterProduct>;

    // --- OPTIMISATION "INSTANTANÉ" AVEC CACHE LONGUE DURÉE ---
    if (mounted) {
      final imagesToLoad = visibleProducts
          .where((p) => p.photoUrl != null && p.photoUrl!.isNotEmpty)
          .map((p) => precacheImage(
        CachedNetworkImageProvider(
          p.photoUrl!,
          cacheManager: customCacheManager, // Utilisation du cache custom
        ),
        context,
      ))
          .toList();

      await Future.wait(imagesToLoad);
    }
    // ---------------------------------

    final menuSnapshot = results[6] as QuerySnapshot;

    final menuSettings = <String, FranchiseeMenuItem>{
      for (var doc in menuSnapshot.docs)
        doc.id: FranchiseeMenuItem.fromFirestore(doc.data() as Map<String, dynamic>)
    };

    return PosData(
      products: visibleProducts,
      menuSettings: menuSettings,
      productFilters: results[0] as List<ProductFilter>,
      kioskCategories: results[1] as List<KioskCategory>,
      allSections: results[2] as List<ProductSection>,
      printerConfig: results[3] as PrinterConfig,
    );
  }

  // --- AJOUT AU PANIER ---
  void _addToCart(MasterProduct product, PosData posData) {
    final settings = posData.menuSettings[product.productId];
    final double price = settings?.price ?? 0.0;

    context.read<CartProvider>().addItem(CartItem(
      product: product,
      price: price,
      quantity: 1,
      vatRate: settings?.vatRate ?? 10.0,
      selectedOptions: {},
    ));

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("${product.name} ajouté !"),
      duration: const Duration(milliseconds: 400),
      backgroundColor: Colors.green,
    ));
  }

  // --- MODALE DOSSIER ---
  void _showContainerModal(BuildContext context, MasterProduct container, PosData posData) {
    final children = posData.products
        .where((p) => container.containerProductIds.contains(p.productId))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.folder_open, color: Colors.orange),
              const SizedBox(width: 10),
              Flexible(child: Text(container.name, style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.7,
            height: MediaQuery.of(context).size.height * 0.6,
            child: children.isEmpty
                ? const Center(child: Text("Ce dossier est vide."))
                : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.85,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: children.length,
              itemBuilder: (ctx, index) {
                final child = children[index];
                final price = posData.menuSettings[child.productId]?.price ?? 0.0;

                return InkWell(
                  onTap: () => _addToCart(child, posData),
                  child: Card(
                    elevation: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: (child.photoUrl != null && child.photoUrl!.isNotEmpty)
                                ? CachedNetworkImage(
                              imageUrl: child.photoUrl!,
                              cacheManager: customCacheManager, // Cache custom
                              fit: BoxFit.contain,
                              fadeInDuration: Duration.zero,
                              placeholder: (context, url) => const SizedBox(),
                            )
                                : const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(child.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Text("${price.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("FERMER", style: TextStyle(fontSize: 16)),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PosData>(
      future: _posDataFutureState,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text("Préparation de la caisse...", style: TextStyle(color: Colors.grey))
                ],
              ),
            ),
          );
        }

        final posData = snapshot.data!;
        final bool isTablet = MediaQuery.of(context).size.width >= 900;

        List<MasterProduct> displayedProducts = posData.products;
        if (_selectedCategoryId != null) {
          final category = posData.kioskCategories.firstWhere(
                  (c) => c.id == _selectedCategoryId,
              orElse: () => KioskCategory(id: '', name: '', filters: [], position: 0)
          );
          final filterIds = category.filters.map((f) => f.id).toSet();
          displayedProducts = displayedProducts
              .where((p) => p.kioskFilterIds.any((id) => filterIds.contains(id)))
              .toList();
        }

        return Scaffold(
          appBar: AppBar(title: const Text("Caisse Enregistreuse")),
          body: Row(
            children: [
              // GAUCHE : GRILLE
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    // Barre Catégories
                    Container(
                      height: 60,
                      color: Colors.white,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(10),
                        // --- 2. SUPPRESSION DU FILTRE "TOUS" ---
                        itemCount: posData.kioskCategories.length, // On enlève le +1
                        itemBuilder: (context, index) {
                          // On accède directement à l'index sans décalage
                          final cat = posData.kioskCategories[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(cat.name),
                              selected: _selectedCategoryId == cat.id,
                              onSelected: (b) => setState(() => _selectedCategoryId = b ? cat.id : null),
                            ),
                          );
                        },
                      ),
                    ),

                    // Grille Produits
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 4 : 3,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: displayedProducts.length,
                        itemBuilder: (context, index) {
                          final product = displayedProducts[index];
                          final bool isFolder = product.isContainer;
                          final bool hasChildren = product.containerProductIds.isNotEmpty;
                          final bool showAsFolder = isFolder || hasChildren;
                          final settings = posData.menuSettings[product.productId];
                          final price = settings?.price ?? 0.0;

                          return InkWell(
                            onTap: () {
                              if (showAsFolder) {
                                _showContainerModal(context, product, posData);
                              } else {
                                _addToCart(product, posData);
                              }
                            },
                            child: Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: showAsFolder
                                    ? const BorderSide(color: Colors.red, width: 3)
                                    : BorderSide.none,
                              ),
                              color: showAsFolder ? Colors.orange.shade50 : Colors.white,
                              elevation: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                        child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                                            ? CachedNetworkImage(
                                          imageUrl: product.photoUrl!,
                                          cacheManager: customCacheManager, // Cache custom
                                          fit: BoxFit.cover,
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          placeholder: (context, url) => Container(color: Colors.grey[100]),
                                        )
                                            : Icon(showAsFolder ? Icons.folder : Icons.fastfood, size: 50, color: showAsFolder ? Colors.orange : Colors.grey),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      children: [
                                        Text(product.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2),
                                        if (!showAsFolder)
                                          Text("${price.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                        else
                                          const Text("DOSSIER", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ],
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
                ),
              ),

              // DROITE : PANIER
              if (isTablet)
                Expanded(
                  flex: 3,
                  child: CartPanel(
                    posData: posData,
                    franchiseeId: _effectiveFranchiseeId,
                    franchisorId: _effectiveFranchisorId,
                    activeSession: widget.activeSession,
                    isTablet: isTablet,
                    onStockChanged: (id, val) {},
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}