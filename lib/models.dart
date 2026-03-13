import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

// ===========================================================================
// 1. UTILISATEURS ET AUTHENTIFICATION
// ===========================================================================

enum OrderType { onSite, takeaway }

class FranchiseUser {
  final String uid;
  final String email;
  final String role;
  final String? franchisorId;
  final String? storeId;
  final String? companyName;
  final String? contactName;
  final String? phone;
  final String? address;
  final Map<String, bool> enabledModules;

  // Champs étendus pour l'affichage borne/écran
  final String? restaurantName;
  final String? screensaverUrl;
  final List<String> screensaverUrls;
  final String? dineInImageUrl;
  final String? takeawayImageUrl;

  FranchiseUser({
    required this.uid,
    required this.email,
    required this.role,
    this.franchisorId,
    this.storeId,
    this.companyName,
    this.contactName,
    this.phone,
    this.address,
    this.enabledModules = const {},
    this.restaurantName,
    this.screensaverUrl,
    this.screensaverUrls = const [],
    this.dineInImageUrl,
    this.takeawayImageUrl,
  });

  factory FranchiseUser.fromFirestore(Map<String, dynamic> data, String uid) {
    final modulesData = (data['enabledModules'] as Map<String, dynamic>?)
        ?.map((key, value) => MapEntry(key, value as bool)) ??
        {};

    List<String> parsedScreensaverUrls = [];
    if (data['screensaverUrls'] != null) {
      parsedScreensaverUrls = List<String>.from(data['screensaverUrls'])
          .where((url) => url.isNotEmpty)
          .toList();
    }

    return FranchiseUser(
      uid: uid,
      email: data['email'] ?? '',
      role: data['role'] ?? 'franchisee',
      franchisorId: data['franchisorId'],
      storeId: data['storeId'],
      companyName: data['companyName'],
      contactName: data['contactName'],
      phone: data['phone'],
      address: data['address'],
      enabledModules: modulesData,
      restaurantName: data['restaurantName'] ?? data['companyName'] ?? 'Restaurant Sans Nom',
      screensaverUrl: data['screensaverUrl'],
      screensaverUrls: parsedScreensaverUrls,
      dineInImageUrl: data['dineInImageUrl'],
      takeawayImageUrl: data['takeawayImageUrl'],
    );
  }

  bool get isFranchisor => role == 'franchisor';
  bool get isFranchisee => role == 'franchisee';
  bool get isEmployee => role == 'employee';
  String get effectiveStoreId => role == 'franchisee' ? uid : (storeId ?? '');
}

// ===========================================================================
// 2. PRODUITS ET OPTIONS (CATALOGUE)
// ===========================================================================

class ProductOption {
  final String id;
  final String name;
  final List<String> sectionIds;
  final String? imageUrl;
  final double priceOverride;

  ProductOption({
    required this.id,
    required this.name,
    this.sectionIds = const [],
    this.imageUrl,
    this.priceOverride = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sectionIds': sectionIds,
      'imageUrl': imageUrl,
      'priceOverride': priceOverride,
    };
  }

  factory ProductOption.fromMap(Map<String, dynamic> map) {
    return ProductOption(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      sectionIds: List<String>.from(map['sectionIds'] ?? []),
      imageUrl: map['imageUrl'],
      priceOverride: (map['priceOverride'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MasterProduct {
  final String id;          // ID du document Firebase
  final String productId;   // ID logique du produit
  final String name;
  final String? description;
  final String? photoUrl;
  final String? color;

  // AJOUT : Prix conseillé par le franchiseur
  final double? price;

  // Indicateurs
  final bool isComposite;
  final bool isIngredient;
  final bool isContainer;

  // Listes d'IDs
  final List<String> containerProductIds; // Les enfants du dossier
  final List<String> filterIds;
  final List<String> sectionIds;
  final List<String> kioskFilterIds;
  final List<String> ingredientProductIds;

  // Options
  final List<ProductOption> options;
  final int? position;
  final String createdBy;

  MasterProduct({
    required this.id,
    required this.productId,
    required this.name,
    this.description,
    this.photoUrl,
    this.color,
    this.price, // AJOUT
    this.isComposite = false,
    this.isIngredient = false,
    this.isContainer = false,
    this.containerProductIds = const [],
    this.options = const [],
    this.filterIds = const [],
    this.sectionIds = const [],
    this.kioskFilterIds = const [],
    this.ingredientProductIds = const [],
    this.position,
    this.createdBy = '',
  });

  factory MasterProduct.fromFirestore(Map<String, dynamic> data, String id) {
    return MasterProduct(
      id: id,
      productId: data['productId'] ?? id,
      name: data['name'] ?? '',
      description: data['description'],
      photoUrl: data['photoUrl'] ?? data['imageUrl'],
      color: data['color'],

      // AJOUT : Récupération du prix conseillé
      price: (data['price'] as num?)?.toDouble(),

      // Booléens
      isComposite: data['isComposite'] ?? false,
      isIngredient: data['isIngredient'] ?? false,
      isContainer: data['isContainer'] ?? false,

      // Listes
      containerProductIds: List<String>.from(data['containerProductIds'] ?? []),
      filterIds: List<String>.from(data['filterIds'] ?? []),
      sectionIds: List<String>.from(data['sectionIds'] ?? []),
      kioskFilterIds: List<String>.from(data['kioskFilterIds'] ?? []),
      ingredientProductIds: List<String>.from(data['ingredientProductIds'] ?? []),

      // Options
      options: (data['options'] as List<dynamic>?)
          ?.map((e) => ProductOption.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],

      position: data['position'],
      createdBy: data['createdBy'] ?? '',
    );
  }

  factory MasterProduct.empty() {
    return MasterProduct(id: '', productId: '', name: '');
  }
}

// ===========================================================================
// 3. SECTIONS, FILTRES ET GROUPES
// ===========================================================================

class SectionItem {
  MasterProduct product;
  double supplementPrice;

  SectionItem({required this.product, this.supplementPrice = 0.0});
}

class ProductSection {
  String id;
  String sectionId;
  String title;
  String type;
  int selectionMin;
  int selectionMax;
  List<SectionItem> items;
  List<String> filterIds;

  ProductSection({
    required this.id,
    required this.sectionId,
    this.title = '',
    this.type = 'radio',
    this.selectionMin = 1,
    this.selectionMax = 1,
    this.items = const [],
    this.filterIds = const [],
  });

  factory ProductSection.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, List<SectionItem> items) {
    final data = doc.data() as Map<String, dynamic>;
    return ProductSection(
      id: doc.id,
      sectionId: data['sectionId'] ?? '',
      title: data['title'] ?? '',
      type: data['type'] ?? 'radio',
      selectionMin: (data['selectionMin'] as num?)?.toInt() ?? 1,
      selectionMax: (data['selectionMax'] as num?)?.toInt() ?? 1,
      items: items,
      filterIds: List<String>.from(data['filterIds'] ?? []),
    );
  }
}

class ProductFilter {
  final String id;
  final String name;
  final int position;
  final String? color;

  ProductFilter({
    required this.id,
    required this.name,
    this.position = 9999,
    this.color,
  });

  factory ProductFilter.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProductFilter(
      id: doc.id,
      name: data['name'] ?? '',
      position: (data['position'] is num)
          ? (data['position'] as num).toInt()
          : int.tryParse(data['position']?.toString() ?? '9999') ?? 9999,
      color: data['color'],
    );
  }
}

class SectionGroup {
  final String id;
  final String name;
  final List<String> sectionIds;
  final List<String> filterIds;

  SectionGroup({
    required this.id,
    required this.name,
    this.sectionIds = const [],
    this.filterIds = const [],
  });

  factory SectionGroup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SectionGroup(
      id: doc.id,
      name: data['name'] ?? '',
      sectionIds: List<String>.from(data['sectionIds'] ?? []),
      filterIds: List<String>.from(data['filterIds'] ?? []),
    );
  }
}

// ===========================================================================
// 4. STRUCTURE BORNE (KIOSK)
// ===========================================================================

class KioskMedia {
  final String id;
  final String franchisorId;
  final String name;
  final String type;
  final String url;
  final String? thumbnailUrl;

  KioskMedia({
    required this.id,
    required this.franchisorId,
    required this.name,
    required this.type,
    required this.url,
    this.thumbnailUrl,
  });

  factory KioskMedia.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return KioskMedia(
      id: doc.id,
      franchisorId: data['franchisorId'] ?? '',
      name: data['name'] ?? 'Média sans nom',
      type: data['type'] ?? 'image',
      url: data['url'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'franchisorId': franchisorId,
      'name': name,
      'type': type,
      'url': url,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class KioskFilter {
  final String id;
  final String name;
  final int position;
  final String? color;
  final String? imageUrl;

  KioskFilter({
    required this.id,
    required this.name,
    required this.position,
    this.color,
    this.imageUrl,
  });

  factory KioskFilter.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return KioskFilter(
      id: doc.id,
      name: data['name'] ?? '',
      position: (data['position'] as num?)?.toInt() ?? 0,
      color: data['color'],
      imageUrl: data['imageUrl'],
    );
  }

  KioskFilter copyWith({String? id, String? name, int? position, String? color, String? imageUrl}) {
    return KioskFilter(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      color: color ?? this.color,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class KioskCategory {
  final String id;
  final String name;
  final int position;
  final String? imageUrl;
  final List<KioskFilter> filters;

  KioskCategory({
    required this.id,
    required this.name,
    required this.position,
    this.imageUrl,
    this.filters = const [],
  });

  factory KioskCategory.fromFirestore(DocumentSnapshot doc, List<KioskFilter> filters) {
    final data = doc.data() as Map<String, dynamic>;
    return KioskCategory(
      id: doc.id,
      name: data['name'] ?? '',
      position: (data['position'] as num?)?.toInt() ?? 0,
      imageUrl: data['imageUrl'],
      filters: filters,
    );
  }

  KioskCategory copyWith({String? id, String? name, int? position, String? imageUrl, List<KioskFilter>? filters}) {
    return KioskCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      imageUrl: imageUrl ?? this.imageUrl,
      filters: filters ?? this.filters,
    );
  }
}

// ===========================================================================
// 5. TRANSACTIONS, VENTES ET PANIER
// ===========================================================================

class Deal {
  final String id;
  final String name;
  final double price;
  final List<String> sectionIds;

  Deal({
    required this.id,
    required this.name,
    required this.price,
    required this.sectionIds,
  });

  factory Deal.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Deal(
      id: doc.id,
      name: data['name'] ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      sectionIds: List<String>.from(data['sectionIds'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'price': price, 'sectionIds': sectionIds};
}

class TillSession {
  final String id;
  final String franchiseeId;
  final DateTime openingTime;
  final double initialCash;
  final DateTime? closingTime;
  final double? finalCash;
  final bool isClosed;

  TillSession({
    required this.id,
    required this.franchiseeId,
    required this.openingTime,
    required this.initialCash,
    this.closingTime,
    this.finalCash,
    this.isClosed = false,
  });

  factory TillSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime? parseTimestamp(dynamic value) => (value is Timestamp) ? value.toDate() : null;
    return TillSession(
      id: doc.id,
      franchiseeId: data['franchiseeId'] ?? '',
      openingTime: parseTimestamp(data['openingTime']) ?? DateTime.now(),
      initialCash: (data['initialCash'] as num?)?.toDouble() ?? 0.0,
      closingTime: parseTimestamp(data['closingTime']),
      finalCash: (data['finalCash'] as num?)?.toDouble(),
      isClosed: data['isClosed'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'franchiseeId': franchiseeId,
    'openingTime': openingTime,
    'initialCash': initialCash,
    'closingTime': closingTime,
    'finalCash': finalCash,
    'isClosed': isClosed,
  };
}

class Transaction {
  final String id;
  final String sessionId;
  final String franchiseeId;
  final DateTime timestamp;
  final List<Map<String, dynamic>> items;
  final double subTotal;
  final double discountAmount;
  final double total;
  final double vatTotal;
  final Map<String, dynamic> paymentMethods;
  final String status;
  final String orderType;
  final String identifier;
  final String source;
  final String? customerName;
  final String? kioskName;

  Transaction({
    required this.id,
    required this.sessionId,
    required this.franchiseeId,
    required this.timestamp,
    required this.items,
    required this.subTotal,
    required this.discountAmount,
    required this.total,
    required this.vatTotal,
    required this.paymentMethods,
    required this.status,
    required this.orderType,
    required this.identifier,
    this.source = 'caisse',
    this.customerName,
    this.kioskName,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final total = (data['total'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = (data['discountAmount'] as num?)?.toDouble() ?? 0.0;
    final subTotal = (data['subTotal'] as num?)?.toDouble() ?? (total + discountAmount);

    return Transaction(
      id: doc.id,
      sessionId: data['sessionId'] ?? '',
      franchiseeId: data['franchiseeId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      items: List<Map<String, dynamic>>.from(data['items'] ?? []),
      subTotal: subTotal,
      discountAmount: discountAmount,
      total: total,
      vatTotal: (data['vatTotal'] as num?)?.toDouble() ?? 0.0,
      paymentMethods: data['paymentMethods'] != null
          ? Map<String, dynamic>.from(data['paymentMethods'])
          : {'Card': total},
      status: data['status'] ?? 'pending',
      orderType: data['orderType'] ?? 'onSite',
      identifier: data['identifier'] ?? '',
      source: data['source'] ?? 'caisse',
      customerName: data['customerName'],
      kioskName: data['kioskName'],
    );
  }

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    'franchiseeId': franchiseeId,
    'timestamp': timestamp,
    'items': items,
    'subTotal': subTotal,
    'discountAmount': discountAmount,
    'total': total,
    'vatTotal': vatTotal,
    'paymentMethods': paymentMethods,
    'status': status,
    'orderType': orderType,
    'identifier': identifier,
    'source': source,
    'customerName': customerName,
    'kioskName': kioskName,
  };
}

class FranchiseeMenuItem {
  final String masterProductId;
  final double price;
  final Map<String, double> optionPrices;
  final bool isVisible;
  final double vatRate;
  final double takeawayVatRate;
  final bool isAvailable;
  final int position;
  final String? availableStartTime;
  final String? availableEndTime;
  final bool hidePriceOnCard;

  FranchiseeMenuItem({
    required this.masterProductId,
    this.price = 0.0,
    this.optionPrices = const {},
    this.isVisible = false,
    this.vatRate = 10.0,
    this.takeawayVatRate = 5.5,
    this.isAvailable = true,
    this.position = 0,
    this.availableStartTime,
    this.availableEndTime,
    this.hidePriceOnCard = false,
  });

  factory FranchiseeMenuItem.fromFirestore(Map<String, dynamic> data) {
    final rawOptionPrices = data['optionPrices'] as Map<String, dynamic>?;
    final parsedOptionPrices = rawOptionPrices
        ?.map((key, value) => MapEntry(key, (value as num).toDouble())) ??
        {};
    return FranchiseeMenuItem(
      masterProductId: data['masterProductId'] ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      optionPrices: parsedOptionPrices,
      isVisible: data['isVisible'] ?? false,
      vatRate: (data['vatRate'] as num?)?.toDouble() ?? 10.0,
      takeawayVatRate: (data['takeawayVatRate'] as num?)?.toDouble() ?? 5.5,
      isAvailable: data['isAvailable'] ?? true,
      position: (data['position'] as num?)?.toInt() ?? 0,
      availableStartTime: data['availableStartTime'],
      availableEndTime: data['availableEndTime'],
      hidePriceOnCard: data['hidePriceOnCard'] ?? false,
    );
  }

  bool isCurrentlyAvailableInTimeSlot() {
    if (availableStartTime == null || availableEndTime == null) return true;
    if (availableStartTime!.isEmpty || availableEndTime!.isEmpty) return true;

    final now = DateTime.now();
    final currentTime = now.hour * 60 + now.minute;
    try {
      final startParts = availableStartTime!.split(':');
      final endParts = availableEndTime!.split(':');
      final start = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final end = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      return currentTime >= start && currentTime <= end;
    } catch (e) {
      return true;
    }
  }
}

class CartItem {
  final String id;
  final MasterProduct product;
  final int priceCents;
  double vatRate;
  final Map<String, List<SectionItem>> selectedOptions;
  final List<String> removedIngredientProductIds;
  final List<String> removedIngredientNames;

  bool isSentToKitchen;
  final List<ProductSection> baseSections;
  int quantity;

  CartItem({
    required this.product,
    required double price,
    required this.vatRate,
    this.selectedOptions = const {},
    this.removedIngredientProductIds = const [],
    this.removedIngredientNames = const [],
    this.isSentToKitchen = false,
    this.baseSections = const [],
    this.quantity = 1,
    String? id,
  }) : id = id ?? const Uuid().v4(),
        priceCents = (price * 100).round();

  double get price => priceCents / 100.0;

  int get totalCents {
    int unitPriceCents = priceCents;
    selectedOptions.forEach((_, items) {
      for (var item in items) {
        unitPriceCents += (item.supplementPrice * 100).round();
      }
    });
    return unitPriceCents * quantity;
  }

  double get total => totalCents / 100.0;

  double get totalArticlePrice => (priceCents * quantity) / 100.0;

  CartItem copyWith({
    String? id,
    MasterProduct? product,
    double? price,
    double? vatRate,
    Map<String, List<SectionItem>>? selectedOptions,
    List<String>? removedIngredientProductIds,
    List<String>? removedIngredientNames,
    bool? isSentToKitchen,
    List<ProductSection>? baseSections,
    int? quantity,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      price: price ?? this.price,
      vatRate: vatRate ?? this.vatRate,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      removedIngredientProductIds: removedIngredientProductIds ?? this.removedIngredientProductIds,
      removedIngredientNames: removedIngredientNames ?? this.removedIngredientNames,
      isSentToKitchen: isSentToKitchen ?? this.isSentToKitchen,
      baseSections: baseSections ?? this.baseSections,
      quantity: quantity ?? this.quantity,
    );
  }
}

class PendingOrder {
  final String id;
  final String franchiseeId;
  final String identifier;
  final List<Map<String, dynamic>> itemsAsMap;
  final DateTime timestamp;
  final double total;
  final String source;
  final String orderType;

  PendingOrder({
    required this.id,
    required this.franchiseeId,
    required this.identifier,
    required this.itemsAsMap,
    required this.timestamp,
    required this.total,
    this.source = 'pos',
    this.orderType = 'onSite',
  });

  factory PendingOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PendingOrder(
      id: doc.id,
      franchiseeId: data['franchiseeId'] ?? '',
      identifier: data['identifier'] ?? 'Inconnu',
      itemsAsMap: List<Map<String, dynamic>>.from(data['items'] ?? []),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      source: data['source'] ?? 'pos',
      orderType: data['orderType'] ?? 'onSite',
    );
  }
}

enum PrinterType { escpos }
enum PaperWidth { mm58, mm80 }

class PrinterConfig {
  final String name;
  final String ipAddress;
  final PrinterType type;
  final PaperWidth paperWidth;
  final bool isKitchenPrintingEnabled;
  final bool isBluetooth;
  final String? macAddress;

  PrinterConfig({
    this.name = 'Imprimante Cuisine',
    this.ipAddress = '192.168.1.100',
    this.type = PrinterType.escpos,
    this.paperWidth = PaperWidth.mm80,
    this.isKitchenPrintingEnabled = true,
    this.isBluetooth = false,
    this.macAddress,
  });

  factory PrinterConfig.fromFirestore(Map<String, dynamic> data) {
    return PrinterConfig(
      name: data['name'] ?? 'Imprimante Cuisine',
      ipAddress: data['ipAddress'] ?? '192.168.1.100',
      type: PrinterType.values.firstWhere(
            (e) => e.toString() == data['type'],
        orElse: () => PrinterType.escpos,
      ),
      paperWidth: PaperWidth.values.firstWhere(
            (e) => e.toString() == data['paperWidth'],
        orElse: () => PaperWidth.mm80,
      ),
      isKitchenPrintingEnabled: data['isKitchenPrintingEnabled'] ?? true,
      isBluetooth: data['isBluetooth'] ?? false,
      macAddress: data['macAddress'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ipAddress': ipAddress,
      'type': type.toString(),
      'paperWidth': paperWidth.toString(),
      'isKitchenPrintingEnabled': isKitchenPrintingEnabled,
      'isBluetooth': isBluetooth,
      'macAddress': macAddress,
    };
  }
}

class ReceiptConfig {
  final String headerText;
  final String footerText;
  final bool showVatDetails;
  final bool printReceiptOnPayment;

  ReceiptConfig({
    required this.headerText,
    required this.footerText,
    required this.showVatDetails,
    required this.printReceiptOnPayment,
  });

  Map<String, dynamic> toMap() {
    return {
      'headerText': headerText,
      'footerText': footerText,
      'showVatDetails': showVatDetails,
      'printReceiptOnPayment': printReceiptOnPayment,
    };
  }

  factory ReceiptConfig.fromMap(Map<String, dynamic> map) {
    return ReceiptConfig(
      headerText: map['headerText'] ?? '',
      footerText: map['footerText'] ?? '',
      showVatDetails: map['showVatDetails'] ?? true,
      printReceiptOnPayment: map['printReceiptOnPayment'] ?? true,
    );
  }
}


class AvailabilitySchedule {
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;

  AvailabilitySchedule({
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
  });

  factory AvailabilitySchedule.fromMap(Map<String, dynamic> map) {
    return AvailabilitySchedule(
      daysOfWeek: List<int>.from(map['daysOfWeek'] ?? []),
      startTime: map['startTime'] ?? "00:00",
      endTime: map['endTime'] ?? "23:59",
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'daysOfWeek': daysOfWeek,
      'startTime': startTime,
      'endTime': endTime,
    };
  }

  bool isAvailableNow() {
    final now = DateTime.now();
    if (!daysOfWeek.contains(now.weekday)) {
      return false;
    }
    try {
      final int currentMinutes = now.hour * 60 + now.minute;
      final startParts = startTime.split(':');
      final int startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endParts = endTime.split(':');
      final int endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } catch (e) {
      return true;
    }
  }
}

// Legacy class (préservée si utilisée ailleurs)
class Product {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  final String? description;
  final String? categoryId;
  final bool isActive;
  final bool isMaster;
  final bool isContainer;
  final List<String> containerProductIds;

  Product({
    required this.id,
    required this.name,
    this.price = 0.0,
    this.imageUrl,
    this.description,
    this.categoryId,
    this.isActive = true,
    this.isMaster = false,
    this.isContainer = false,
    this.containerProductIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'description': description,
      'categoryId': categoryId,
      'isActive': isActive,
      'isMaster': isMaster,
      'isContainer': isContainer,
      'containerProductIds': containerProductIds,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map, String id) {
    return Product(
      id: id,
      name: map['name'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      imageUrl: map['imageUrl'],
      description: map['description'],
      categoryId: map['categoryId'],
      isActive: map['isActive'] ?? true,
      isMaster: map['isMaster'] ?? false,
      isContainer: map['isContainer'] ?? false,
      containerProductIds: map['containerProductIds'] != null
          ? List<String>.from(map['containerProductIds'])
          : [],
    );
  }
}