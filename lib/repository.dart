import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class FranchiseRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- CORRECTION DÉFINITIVE : Remplacement de la variable par un getter ---
  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  static final FranchiseRepository _instance = FranchiseRepository._internal();

  factory FranchiseRepository() => _instance;

  FranchiseRepository._internal();

  /// Exécute des requêtes "whereIn" sur de grandes listes d'IDs en les découpant en morceaux de 30.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _performChunkedQuery(
          Query collectionQuery, String field, List<dynamic> ids) async {
    if (ids.isEmpty) {
      return [];
    }
    final List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
    for (var i = 0; i < ids.length; i += 30) {
      final sublist = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      futures.add(collectionQuery.where(field, whereIn: sublist).get()
          as Future<QuerySnapshot<Map<String, dynamic>>>);
    }
    final snapshots = await Future.wait(futures);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
    for (final snapshot in snapshots) {
      docs.addAll(snapshot.docs);
    }
    return docs;
  }

  Future<List<MasterProduct>> getFranchiseeEnabledProducts(
      String franchiseeId, String franchisorId) async {
    final menuSnapshot = await _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('menu')
        .where('isVisible', isEqualTo: true)
        .get();
    final productIds = menuSnapshot.docs.map((doc) => doc.id).toList();

    if (productIds.isEmpty) {
      return [];
    }

    final baseQuery = _firestore
        .collection('master_products')
        .where('createdBy', isEqualTo: franchisorId);
    final productDocs =
        await _performChunkedQuery(baseQuery, 'productId', productIds);
    return productDocs
        .map((doc) => MasterProduct.fromFirestore(doc.data(), doc.id))
        .toList();
  }

  Stream<List<MasterProduct>> getFranchiseeVisibleProductsStream(
      String franchiseeId, String franchisorId) {
    return _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('menu')
        .where('isVisible', isEqualTo: true)
        .snapshots()
        .asyncMap((menuSnapshot) async {
      final productIds = menuSnapshot.docs.map((doc) => doc.id).toList();
      if (productIds.isEmpty) {
        return [];
      }

      final baseQuery = _firestore
          .collection('master_products')
          .where('createdBy', isEqualTo: franchisorId);
      final productDocs =
          await _performChunkedQuery(baseQuery, 'productId', productIds);

      return productDocs
          .map((doc) => MasterProduct.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  Future<String?> createFranchisee({
    required String email,
    required String password,
    required String companyName,
    required String contactName,
    required String phone,
    required String address,
    required Map<String, bool> enabledModules,
  }) async {
    // Cette ligne récupère l'ID de l'utilisateur ACTUELLEMENT CONNECTÉ (le franchiseur).
    final String currentFranchisorId = _currentUserId;

    // Ajout d'une sécurité : si l'ID est vide, on arrête tout.
    if (currentFranchisorId.isEmpty) {
      debugPrint(
          "ERREUR CRITIQUE: L'ID du franchiseur est vide. L'utilisateur n'est probablement pas connecté correctement.");
      return "Erreur : Impossible d'identifier le franchiseur. Veuillez vous reconnecter.";
    }

    try {
      // On crée le NOUVEL utilisateur (le franchisé).
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      User? newUser = userCredential.user; // `newUser` est le FRANCHISÉ.

      if (newUser != null) {
        // newUser.uid est l'ID du FRANCHISÉ.

        // On crée le document pour le FRANCHISÉ et on lui assigne l'ID du FRANCHISEUR.
        await _firestore.collection('users').doc(newUser.uid).set({
          'email': email,
          'role': 'franchisee',
          'franchisorId': currentFranchisorId,
          // Utilisation de l'ID vérifié du franchiseur
          'companyName': companyName,
          'contactName': contactName,
          'phone': phone,
          'address': address,
          'createdAt': FieldValue.serverTimestamp(),
          'enabledModules': enabledModules,
        });

        // Initialisation du catalogue et de la config pour le nouveau compte
        final batch = _firestore.batch();

        final masterProductsSnapshot = await _firestore
            .collection('master_products')
            .where('createdBy', isEqualTo: currentFranchisorId)
            .get();

        if (masterProductsSnapshot.docs.isNotEmpty) {
          for (final productDoc in masterProductsSnapshot.docs) {
            final product =
                MasterProduct.fromFirestore(productDoc.data(), productDoc.id);
            final newMenuItemRef = _firestore
                .collection('users')
                .doc(newUser.uid)
                .collection('menu')
                .doc(product.productId);

            batch.set(newMenuItemRef, {
              'masterProductId': product.productId,
              'price': 0.0,
              'vatRate': 10.0,
              'isVisible': false,
              'isAvailable': false
            });
          }
        }

        final printerConfigRef = _firestore
            .collection('users')
            .doc(newUser.uid)
            .collection('config')
            .doc('printer');
        final defaultPrinterConfig = PrinterConfig();
        batch.set(printerConfigRef, defaultPrinterConfig.toMap());

        final receiptConfigRef = _firestore
            .collection('users')
            .doc(newUser.uid)
            .collection('config')
            .doc('receipt');
        final defaultReceiptConfig = ReceiptConfig();
        batch.set(receiptConfigRef, defaultReceiptConfig.toMap());

        await batch.commit();

        return null;
      }
      return "Erreur inconnue.";
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') return 'Le mot de passe est trop faible.';
      if (e.code == 'email-already-in-use')
        return 'Cette adresse email est déjà utilisée.';
      return e.message;
    } catch (e) {
      return 'Une erreur est survenue: $e';
    }
  }

  Future<String?> updateFranchiseeDetails({
    required String uid,
    required String companyName,
    required String contactName,
    required String phone,
    required String address,
    required Map<String, bool> enabledModules,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'companyName': companyName,
        'contactName': contactName,
        'phone': phone,
        'address': address,
        'enabledModules': enabledModules,
      });
      return null;
    } catch (e) {
      debugPrint("Erreur lors de la mise à jour du franchisé: $e");
      return 'Une erreur est survenue lors de la mise à jour: $e';
    }
  }

  Stream<List<FranchiseUser>> getFranchiseesStream(String franchisorId) {
    return _firestore
        .collection('users')
        .where('franchisorId', isEqualTo: franchisorId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FranchiseUser.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  Future<String?> deleteFranchiseeAccount(String franchiseeId) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable('deleteFranchiseeData');

      final result = await callable.call<Map<String, dynamic>>({
        'franchiseeId': franchiseeId,
      });
      if (result.data['success'] == true) {
        return null;
      } else {
        return result.data['message'] ?? "Une erreur inconnue est survenue.";
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint("Erreur Cloud Function [${e.code}]: ${e.message}");
      return e.message ??
          "Une erreur est survenue lors de la communication avec le serveur.";
    } catch (e) {
      debugPrint("Erreur inattendue: $e");
      return "Une erreur inattendue est survenue.";
    }
  }

  Stream<List<KioskCategory>> getKioskCategoriesStream(String franchisorId) {
    return _firestore
        .collection('kiosk_categories')
        .where('createdBy', isEqualTo: franchisorId)
        .orderBy('position')
        .snapshots()
        .asyncMap((snapshot) async {
      List<KioskCategory> categories = [];
      for (var doc in snapshot.docs) {
        final filtersSnapshot =
            await doc.reference.collection('filters').orderBy('position').get();

        final filters = filtersSnapshot.docs
            .map((filterDoc) => KioskFilter.fromFirestore(filterDoc))
            .toList();
        categories.add(KioskCategory.fromFirestore(doc, filters));
      }
      return categories;
    });
  }

  Future<void> saveKioskCategory(
      {String? id, required String name, required int position}) async {
    final docRef = id != null
        ? _firestore.collection('kiosk_categories').doc(id)
        : _firestore.collection('kiosk_categories').doc();
    await docRef.set(
        {'name': name, 'position': position, 'createdBy': _currentUserId},
        SetOptions(merge: true));
  }

  Future<void> deleteKioskCategory(String categoryId) async =>
      await _firestore.collection('kiosk_categories').doc(categoryId).delete();

  Future<void> saveKioskFilter(
      {required String categoryId,
      String? filterId,
      required String name,
      required int position}) async {
    final docRef = filterId != null
        ? _firestore
            .collection('kiosk_categories')
            .doc(categoryId)
            .collection('filters')
            .doc(filterId)
        : _firestore
            .collection('kiosk_categories')
            .doc(categoryId)
            .collection('filters')
            .doc();
    await docRef
        .set({'name': name, 'position': position}, SetOptions(merge: true));
  }

  Future<void> deleteKioskFilter(
      {required String categoryId, required String filterId}) async {
    await _firestore
        .collection('kiosk_categories')
        .doc(categoryId)
        .collection('filters')
        .doc(filterId)
        .delete();
  }

  Stream<List<ProductFilter>> getFiltersStream(String franchisorId) {
    return _firestore
        .collection('product_filters')
        .where('createdBy', isEqualTo: franchisorId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(ProductFilter.fromFirestore).toList());
  }

  Future<void> addFilter(String name) async => await _firestore
      .collection('product_filters')
      .add({'name': name, 'createdBy': _currentUserId});

  Future<void> deleteFilter(String filterId) async =>
      await _firestore.collection('product_filters').doc(filterId).delete();

  Stream<List<ProductSection>> getSectionsStream(String franchisorId,
      {List<String> filterIds = const []}) {
    Query query = _firestore
        .collection('product_sections')
        .where('createdBy', isEqualTo: franchisorId);
    if (filterIds.isNotEmpty)
      query = query.where('filterIds', arrayContainsAny: filterIds);
    return query.snapshots().asyncMap((snapshot) async {
      List<ProductSection> sections = [];
      for (var doc in snapshot.docs) {
        final sectionId = (doc.data() as Map<String, dynamic>)['sectionId'];
        final itemsSnapshot = await _firestore
            .collection('section_items')
            .where('belongsToSection', isEqualTo: sectionId)
            .get();

        final productIds = itemsSnapshot.docs
            .map((itemDoc) => itemDoc.data()['productId'] as String)
            .toList();
        final supplementPrices = {
          for (var itemDoc in itemsSnapshot.docs)
            itemDoc.data()['productId']:
                (itemDoc.data()['price'] as num?)?.toDouble() ?? 0.0
        };

        List<SectionItem> sectionItems = [];
        if (productIds.isNotEmpty) {
          final productDocs = await _performChunkedQuery(
              _firestore.collection('master_products'),
              'productId',
              productIds);
          for (var prodDoc in productDocs) {
            final product =
                MasterProduct.fromFirestore(prodDoc.data(), prodDoc.id);
            sectionItems.add(SectionItem(
                product: product,
                supplementPrice: supplementPrices[product.productId] ?? 0.0));
          }
        }
        sections.add(ProductSection.fromFirestore(
            doc as DocumentSnapshot<Map<String, dynamic>>, sectionItems));
      }
      return sections;
    });
  }

  Future<List<ProductSection>> getSectionsForProduct(
      String franchisorId, List<String> sectionIds) async {
    if (sectionIds.isEmpty) return [];
    List<ProductSection> fetchedSections = [];

    final sectionDocs = await _performChunkedQuery(
        _firestore
            .collection('product_sections')
            .where('createdBy', isEqualTo: franchisorId),
        'sectionId',
        sectionIds);
    for (var doc in sectionDocs) {
      final sectionId = (doc.data())['sectionId'];
      final itemsSnapshot = await _firestore
          .collection('section_items')
          .where('belongsToSection', isEqualTo: sectionId)
          .get();
      final productIds = itemsSnapshot.docs
          .map((itemDoc) => itemDoc.data()['productId'] as String)
          .toList();
      final supplementPrices = {
        for (var itemDoc in itemsSnapshot.docs)
          itemDoc.data()['productId']:
              (itemDoc.data()['price'] as num?)?.toDouble() ?? 0.0
      };

      List<SectionItem> sectionItems = [];
      if (productIds.isNotEmpty) {
        final productDocs = await _performChunkedQuery(
            _firestore.collection('master_products'), 'productId', productIds);
        for (var prodDoc in productDocs) {
          final product =
              MasterProduct.fromFirestore(prodDoc.data(), prodDoc.id);
          sectionItems.add(SectionItem(
              product: product,
              supplementPrice: supplementPrices[product.productId] ?? 0.0));
        }
      }
      fetchedSections.add(ProductSection.fromFirestore(
          doc as DocumentSnapshot<Map<String, dynamic>>, sectionItems));
    }
    return sectionIds
        .map((id) => fetchedSections.firstWhere((s) => s.sectionId == id,
            orElse: () => ProductSection(id: '', sectionId: '')))
        .where((s) => s.sectionId.isNotEmpty)
        .toList();
  }

  Future<void> saveSection(ProductSection section) async {
    final batch = _firestore.batch();
    final sectionQuery = await _firestore
        .collection('product_sections')
        .where('sectionId', isEqualTo: section.sectionId)
        .limit(1)
        .get();
    final docRef = sectionQuery.docs.isNotEmpty
        ? sectionQuery.docs.first.reference
        : _firestore.collection('product_sections').doc();
    batch.set(
        docRef,
        {
          'sectionId': section.sectionId,
          'title': section.title,
          'type': section.type,
          'selectionMin': section.selectionMin,
          'selectionMax': section.selectionMax,
          'createdBy': _currentUserId,
          'filterIds': section.filterIds,
        },
        SetOptions(merge: true));
    final oldItemsQuery = await _firestore
        .collection('section_items')
        .where('belongsToSection', isEqualTo: section.sectionId)
        .get();
    for (var doc in oldItemsQuery.docs) {
      batch.delete(doc.reference);
    }

    for (final item in section.items) {
      final itemRef = _firestore.collection('section_items').doc();
      batch.set(itemRef, {
        'belongsToSection': section.sectionId,
        'productId': item.product.productId,
        'price': item.supplementPrice,
        'createdBy': _currentUserId
      });
    }
    await batch.commit();
  }

  Future<void> deleteSection(String sectionId) async {
    final batch = _firestore.batch();
    final sectionQuery = await _firestore
        .collection('product_sections')
        .where('sectionId', isEqualTo: sectionId)
        .get();
    for (final doc in sectionQuery.docs) {
      batch.delete(doc.reference);
    }
    final itemsQuery = await _firestore
        .collection('section_items')
        .where('belongsToSection', isEqualTo: sectionId)
        .get();
    for (final doc in itemsQuery.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Stream<List<SectionGroup>> getSectionGroupsStream(String franchisorId,
      {List<String> filterIds = const []}) {
    Query query = _firestore
        .collection('section_groups')
        .where('createdBy', isEqualTo: franchisorId);
    if (filterIds.isNotEmpty)
      query = query.where('filterIds', arrayContainsAny: filterIds);
    return query.snapshots().map(
        (snapshot) => snapshot.docs.map(SectionGroup.fromFirestore).toList());
  }

  Future<void> saveSectionGroup(
      {String? groupId,
      required String name,
      required List<String> sectionIds,
      required List<String> filterIds}) async {
    final docRef = groupId != null
        ? _firestore.collection('section_groups').doc(groupId)
        : _firestore.collection('section_groups').doc();
    await docRef.set({
      'name': name,
      'sectionIds': sectionIds,
      'createdBy': _currentUserId,
      'filterIds': filterIds
    }, SetOptions(merge: true));
  }

  Future<void> deleteSectionGroup(String groupId) async =>
      await _firestore.collection('section_groups').doc(groupId).delete();

  Future<void> duplicateSectionGroup(SectionGroup group) async {
    final newName = '${group.name} (Copie)';
    final docRef = _firestore.collection('section_groups').doc();
    await docRef.set({
      'name': newName,
      'sectionIds': group.sectionIds,
      'createdBy': _currentUserId,
      'filterIds': group.filterIds,
    }, SetOptions(merge: true));
  }

  Stream<List<MasterProduct>> getMasterProductsStream(String franchisorId,
      {List<String> filterIds = const []}) {
    Query query = _firestore
        .collection('master_products')
        .where('createdBy', isEqualTo: franchisorId);
    if (filterIds.isNotEmpty)
      query = query.where('filterIds', arrayContainsAny: filterIds);
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => MasterProduct.fromFirestore(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  Future<void> saveProduct({
    MasterProduct? product,
    required String name,
    required String description,
    required bool isComposite,
    required bool isIngredient,
    required List<String> filterIds,
    required List<String> sectionIds,
    required List<String> kioskFilterIds,
  }) async {
    final docRef = product != null
        ? _firestore.collection('master_products').doc(product.id)
        : _firestore.collection('master_products').doc();
    final productId = product?.productId ?? const Uuid().v4();
    await docRef.set({
      'productId': productId,
      'name': name,
      'description': description,
      'photoUrl': '',
      'createdBy': _currentUserId,
      'isComposite': isComposite,
      'isIngredient': isIngredient,
      'filterIds': filterIds,
      'sectionIds': isComposite ? sectionIds : [],
      'kioskFilterIds': kioskFilterIds,
    }, SetOptions(merge: true));
  }

  Future<void> deleteMasterProduct(MasterProduct product) async {
    final batch = _firestore.batch();
    final masterProductRef =
        _firestore.collection('master_products').doc(product.id);
    batch.delete(masterProductRef);
    final franchiseesSnapshot = await _firestore
        .collection('users')
        .where('franchisorId', isEqualTo: _currentUserId)
        .get();
    for (final franchiseeDoc in franchiseesSnapshot.docs) {
      final franchiseeMenuRef = _firestore
          .collection('users')
          .doc(franchiseeDoc.id)
          .collection('menu')
          .doc(product.productId);
      batch.delete(franchiseeMenuRef);
    }
    final sectionItemsSnapshot = await _firestore
        .collection('section_items')
        .where('productId', isEqualTo: product.productId)
        .get();
    for (final itemDoc in sectionItemsSnapshot.docs) {
      batch.delete(itemDoc.reference);
    }
    await batch.commit();
  }

  Future<void> savePendingOrder(String franchiseeId, String identifier,
      List<CartItem> items, double total) async {
    final itemsAsMap = items
        .map((item) => {
              'masterProductId': item.product.id,
              'basePrice': item.price,
              'vatRate': item.vatRate,
              'isSentToKitchen': item.isSentToKitchen,
              'selectedOptions': item.selectedOptions.entries
                  .map((entry) => {
                        'sectionId': entry.key,
                        'items': entry.value
                            .map((sectionItem) => {
                                  'masterProductId': sectionItem.product.id,
                                  'supplementPrice':
                                      sectionItem.supplementPrice,
                                })
                            .toList(),
                      })
                  .toList(),
            })
        .toList();
    await _firestore.collection('pending_orders').add({
      'franchiseeId': franchiseeId,
      'identifier': identifier,
      'items': itemsAsMap,
      'total': total,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<PendingOrder>> getPendingOrdersStream(String franchiseeId) {
    return _firestore
        .collection('pending_orders')
        .where('franchiseeId', isEqualTo: franchiseeId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PendingOrder.fromFirestore(doc))
            .toList());
  }

  Future<void> deletePendingOrder(String orderId) async {
    await _firestore.collection('pending_orders').doc(orderId).delete();
  }

  Stream<List<TillSession>> getFranchiseeSessions(String franchiseeId,
      {DateTime? startDate, DateTime? endDate}) {
    Query query = _firestore
        .collection('sessions')
        .where('franchiseeId', isEqualTo: franchiseeId)
        .orderBy('openingTime', descending: true);
    if (startDate != null)
      query = query.where('openingTime', isGreaterThanOrEqualTo: startDate);
    if (endDate != null)
      query = query.where('openingTime',
          isLessThanOrEqualTo: endDate.add(const Duration(days: 1)));
    return query.snapshots().map(
        (snapshot) => snapshot.docs.map(TillSession.fromFirestore).toList());
  }

  Stream<List<Transaction>> getSessionTransactions(String sessionId) =>
      _firestore
          .collection('transactions')
          .where('sessionId', isEqualTo: sessionId)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) =>
              snapshot.docs.map(Transaction.fromFirestore).toList());

  Stream<List<Transaction>> getTransactionsInDateRange(String franchiseeId,
      {DateTime? startDate, DateTime? endDate}) {
    Query query = _firestore
        .collection('transactions')
        .where('franchiseeId', isEqualTo: franchiseeId)
        .orderBy('timestamp', descending: true);
    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('timestamp',
          isLessThanOrEqualTo: endDate.add(const Duration(days: 1)));
    }

    return query.snapshots().map(
        (snapshot) => snapshot.docs.map(Transaction.fromFirestore).toList());
  }

  Stream<TillSession?> getActiveSession(String franchiseeId) {
    return _firestore
        .collection('sessions')
        .where('franchiseeId', isEqualTo: franchiseeId)
        .where('isClosed', isEqualTo: false)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty
            ? TillSession.fromFirestore(snapshot.docs.first)
            : null);
  }

  Future<String> openTillSession(
      {required String franchiseeId, required double initialCash}) async {
    final docRef = _firestore.collection('sessions').doc();
    final newSession = TillSession(
        id: docRef.id,
        franchiseeId: franchiseeId,
        openingTime: DateTime.now(),
        initialCash: initialCash);
    await docRef.set(newSession.toMap());
    return docRef.id;
  }

  Future<String?> closeTillSession(
      {required String sessionId, required double finalCash}) async {
    try {
      await _firestore.collection('sessions').doc(sessionId).update({
        'closingTime': DateTime.now(),
        'finalCash': finalCash,
        'isClosed': true
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> recordTransaction(Transaction transaction) async {
    await _firestore
        .collection('transactions')
        .doc(transaction.id)
        .set(transaction.toMap());
  }

  Future<void> savePrinterConfig(
      String franchiseeId, PrinterConfig config) async {
    await _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('config')
        .doc('printer')
        .set(config.toMap());
  }

  Stream<PrinterConfig> getPrinterConfigStream(String franchiseeId) {
    return _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('config')
        .doc('printer')
        .snapshots()
        .map((doc) {
      if (doc.exists && doc.data() != null) {
        return PrinterConfig.fromFirestore(doc.data()!);
      }
      return PrinterConfig();
    });
  }

  Future<void> saveReceiptConfig(
      String franchiseeId, ReceiptConfig config) async {
    await _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('config')
        .doc('receipt')
        .set(config.toMap());
  }

  Stream<ReceiptConfig> getReceiptConfigStream(String franchiseeId) {
    return _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('config')
        .doc('receipt')
        .snapshots()
        .map((doc) {
      if (doc.exists && doc.data() != null) {
        return ReceiptConfig.fromFirestore(doc.data()!);
      }
      return ReceiptConfig();
    });
  }
}
