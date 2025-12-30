import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

enum OrderType { onSite, takeaway }

class FranchiseUser {
  final String uid;
  final String email;
  final String role;
  final String? franchisorId;
  final String? companyName;
  final String? contactName;
  final String? phone;
  final String? address;
  final Map<String, bool> enabledModules;

  FranchiseUser({
    required this.uid,
    required this.email,
    required this.role,
    this.franchisorId,
    this.companyName,
    this.contactName,
    this.phone,
    this.address,
    this.enabledModules = const {},
  });

  factory FranchiseUser.fromFirestore(Map<String, dynamic> data, String uid) {
    final modulesData = (data['enabledModules'] as Map<String, dynamic>?)
            ?.map((key, value) => MapEntry(key, value as bool)) ??
        {};

    return FranchiseUser(
      uid: uid,
      email: data['email'] ?? '',
      role: data['role'] ?? 'franchisee',
      franchisorId: data['franchisorId'],
      companyName: data['companyName'],
      contactName: data['contactName'],
      phone: data['phone'],
      address: data['address'],
      enabledModules: modulesData,
    );
  }

  bool get isFranchisor => role == 'franchisor';
}

class MasterProduct {
  final String id;
  final String productId;
  final String name;
  final String? description;
  final String? photoUrl;
  final List<String> sectionIds;
  final bool isComposite;
  final bool isIngredient;
  final List<String> filterIds;
  final List<String> kioskFilterIds;

  MasterProduct({
    required this.id,
    required this.productId,
    required this.name,
    this.description,
    this.photoUrl,
    this.sectionIds = const [],
    required this.isComposite,
    this.isIngredient = false,
    this.filterIds = const [],
    this.kioskFilterIds = const [],
  });

  factory MasterProduct.fromFirestore(Map<String, dynamic> data, String id) =>
      MasterProduct(
        id: id,
        productId: data['productId'] ?? '',
        name: data['name'] ?? '',
        description: data['description'],
        photoUrl: data['photoUrl'],
        sectionIds: List<String>.from(data['sectionIds'] ?? []),
        isComposite: data['isComposite'] ?? false,
        isIngredient: data['isIngredient'] ?? false,
        filterIds: List<String>.from(data['filterIds'] ?? []),
        kioskFilterIds: List<String>.from(data['kioskFilterIds'] ?? []),
      );
}

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

  ProductSection(
      {required this.id,
      required this.sectionId,
      this.title = '',
      this.type = 'radio',
      this.selectionMin = 1,
      this.selectionMax = 1,
      this.items = const [],
      this.filterIds = const []});

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
        filterIds: List<String>.from(data['filterIds'] ?? []));
  }
}

class ProductFilter {
  final String id;
  final String name;

  ProductFilter({required this.id, required this.name});

  factory ProductFilter.fromFirestore(DocumentSnapshot doc) => ProductFilter(
      id: doc.id, name: (doc.data() as Map<String, dynamic>)['name'] ?? '');
}

class SectionGroup {
  final String id;
  final String name;
  final List<String> sectionIds;
  final List<String> filterIds;

  SectionGroup(
      {required this.id,
      required this.name,
      this.sectionIds = const [],
      this.filterIds = const []});

  factory SectionGroup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SectionGroup(
        id: doc.id,
        name: data['name'] ?? '',
        sectionIds: List<String>.from(data['sectionIds'] ?? []),
        filterIds: List<String>.from(data['filterIds'] ?? []));
  }
}

class KioskFilter {
  final String id;
  final String name;
  final int position;

  KioskFilter({required this.id, required this.name, required this.position});

  factory KioskFilter.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return KioskFilter(
        id: doc.id,
        name: data['name'] ?? '',
        position: (data['position'] as num?)?.toInt() ?? 0);
  }
}

class KioskCategory {
  final String id;
  final String name;
  final int position;
  final List<KioskFilter> filters;

  KioskCategory(
      {required this.id,
      required this.name,
      required this.position,
      this.filters = const []});

  factory KioskCategory.fromFirestore(
      DocumentSnapshot doc, List<KioskFilter> filters) {
    final data = doc.data() as Map<String, dynamic>;
    return KioskCategory(
        id: doc.id,
        name: data['name'] ?? '',
        position: (data['position'] as num?)?.toInt() ?? 0,
        filters: filters);
  }
}

class Deal {
  final String id;
  final String name;
  final double price;
  final List<String> sectionIds;

  Deal(
      {required this.id,
      required this.name,
      required this.price,
      required this.sectionIds});

  factory Deal.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Deal(
        id: doc.id,
        name: data['name'] ?? '',
        price: (data['price'] as num?)?.toDouble() ?? 0.0,
        sectionIds: List<String>.from(data['sectionIds'] ?? []));
  }

  Map<String, dynamic> toMap() =>
      {'name': name, 'price': price, 'sectionIds': sectionIds};
}

class TillSession {
  final String id;
  final String franchiseeId;
  final DateTime openingTime;
  final double initialCash;
  final DateTime? closingTime;
  final double? finalCash;
  final bool isClosed;

  TillSession(
      {required this.id,
      required this.franchiseeId,
      required this.openingTime,
      required this.initialCash,
      this.closingTime,
      this.finalCash,
      this.isClosed = false});

  factory TillSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime? parseTimestamp(dynamic value) =>
        (value is Timestamp) ? value.toDate() : null;
    return TillSession(
        id: doc.id,
        franchiseeId: data['franchiseeId'] ?? '',
        openingTime: parseTimestamp(data['openingTime']) ?? DateTime.now(),
        initialCash: (data['initialCash'] as num?)?.toDouble() ?? 0.0,
        closingTime: parseTimestamp(data['closingTime']),
        finalCash: (data['finalCash'] as num?)?.toDouble(),
        isClosed: data['isClosed'] ?? false);
  }

  Map<String, dynamic> toMap() => {
        'franchiseeId': franchiseeId,
        'openingTime': openingTime,
        'initialCash': initialCash,
        'closingTime': closingTime,
        'finalCash': finalCash,
        'isClosed': isClosed
      };
}

class Transaction {
  final String id;
  final String sessionId;
  final String franchiseeId;
  final DateTime timestamp;
  final List<Map<String, dynamic>> items;
  final double total;
  final double vatTotal;
  final Map<String, dynamic> paymentMethods;
  final String status;
  final String orderType;

  Transaction({
    required this.id,
    required this.sessionId,
    required this.franchiseeId,
    required this.timestamp,
    required this.items,
    required this.total,
    required this.vatTotal,
    required this.paymentMethods,
    required this.status,
    required this.orderType,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Transaction(
      id: doc.id,
      sessionId: data['sessionId'] ?? '',
      franchiseeId: data['franchiseeId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      items: List<Map<String, dynamic>>.from(data['items'] ?? []),
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      vatTotal: (data['vatTotal'] as num?)?.toDouble() ?? 0.0,
      paymentMethods: data['paymentMethods'] != null
          ? Map<String, dynamic>.from(data['paymentMethods'])
          : {'Card': (data['total'] as num?)?.toDouble() ?? 0.0},
      status: data['status'] ?? 'pending',
      orderType: data['orderType'] ?? 'onSite',
    );
  }

  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'franchiseeId': franchiseeId,
        'timestamp': timestamp,
        'items': items,
        'total': total,
        'vatTotal': vatTotal,
        'paymentMethods': paymentMethods,
        'status': status,
        'orderType': orderType,
      };
}

class FranchiseeMenuItem {
  final String masterProductId;
  final double price;
  final bool isVisible;
  final double vatRate;
  final bool isAvailable;

  FranchiseeMenuItem(
      {required this.masterProductId,
      this.price = 0.0,
      this.isVisible = false,
      this.vatRate = 10.0,
      this.isAvailable = true});

  factory FranchiseeMenuItem.fromFirestore(Map<String, dynamic> data) =>
      FranchiseeMenuItem(
          masterProductId: data['masterProductId'] ?? '',
          price: (data['price'] as num?)?.toDouble() ?? 0.0,
          isVisible: data['isVisible'] ?? false,
          vatRate: (data['vatRate'] as num?)?.toDouble() ?? 10.0,
          isAvailable: data['isAvailable'] ?? true);
}

class CartItem {
  final String id = const Uuid().v4();
  final MasterProduct product;
  final double price;
  final double vatRate;
  final Map<String, List<SectionItem>> selectedOptions;
  bool isSentToKitchen;

  CartItem({
    required this.product,
    required this.price,
    required this.vatRate,
    this.selectedOptions = const {},
    this.isSentToKitchen = false,
  });

  double get total {
    double finalPrice = price;
    selectedOptions.forEach((_, items) => finalPrice +=
        items.fold(0.0, (sum, item) => sum + item.supplementPrice));
    return finalPrice;
  }
}

class PendingOrder {
  final String id;
  final String franchiseeId;
  final String identifier;
  final List<Map<String, dynamic>> itemsAsMap;
  final DateTime timestamp;
  final double total;

  PendingOrder(
      {required this.id,
      required this.franchiseeId,
      required this.identifier,
      required this.itemsAsMap,
      required this.timestamp,
      required this.total});

  factory PendingOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PendingOrder(
      id: doc.id,
      franchiseeId: data['franchiseeId'] ?? '',
      identifier: data['identifier'] ?? 'Inconnu',
      itemsAsMap: List<Map<String, dynamic>>.from(data['items'] ?? []),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
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

  // --- CORRECTION : Champ manquant ajouté ---
  final bool isKitchenPrintingEnabled;

  PrinterConfig({
    this.name = 'Imprimante Cuisine',
    this.ipAddress = '192.168.1.100',
    this.type = PrinterType.escpos,
    this.paperWidth = PaperWidth.mm80,
    // --- CORRECTION : Valeur par défaut ajoutée ---
    this.isKitchenPrintingEnabled = true,
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
      // --- CORRECTION : Logique de lecture ajoutée (avec valeur par défaut pour la compatibilité) ---
      isKitchenPrintingEnabled: data['isKitchenPrintingEnabled'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ipAddress': ipAddress,
      'type': type.toString(),
      'paperWidth': paperWidth.toString(),
      // --- CORRECTION : Ajouté à la sauvegarde ---
      'isKitchenPrintingEnabled': isKitchenPrintingEnabled,
    };
  }
}

class ReceiptConfig {
  final String? logoUrl;
  final String headerText;
  final String footerText;
  final bool showVatDetails;
  final bool printReceiptOnPayment;

  ReceiptConfig({
    this.logoUrl,
    this.headerText = 'Merci de votre visite !',
    this.footerText = 'À bientôt !',
    this.showVatDetails = true,
    this.printReceiptOnPayment = true,
  });

  factory ReceiptConfig.fromFirestore(Map<String, dynamic> data) {
    return ReceiptConfig(
      logoUrl: data['logoUrl'],
      headerText: data['headerText'] ?? 'Merci de votre visite !',
      footerText: data['footerText'] ?? 'À bientôt !',
      showVatDetails: data['showVatDetails'] ?? true,
      printReceiptOnPayment: data['printReceiptOnPayment'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'logoUrl': logoUrl,
      'headerText': headerText,
      'footerText': footerText,
      'showVatDetails': showVatDetails,
      'printReceiptOnPayment': printReceiptOnPayment,
    };
  }
}
