import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../models.dart';

class FranchiseRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  static final FranchiseRepository _instance = FranchiseRepository._internal();

  factory FranchiseRepository() => _instance;

  FranchiseRepository._internal();

  Future<void> saveFilter({
    required String franchisorId,
    required String id,
    required String name,
    String? color,
  }) async {
    try {
      final docRef =
      FirebaseFirestore.instance.collection('product_filters').doc(id);

      await docRef.set({
        'id': id,
        'createdBy': franchisorId,
        'name': name,
        'color': color,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteFilter(String filterId) async {
    await FirebaseFirestore.instance
        .collection('product_filters')
        .doc(filterId)
        .delete();
  }

  Future<void> addProductFilter(String uid, String name) async {
    final id = const Uuid().v4();
    await _firestore.collection('product_filters').doc(id).set({
      'id': id,
      'name': name,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateKioskFiltersOrder(
      String categoryId, List<KioskFilter> filters) async {
    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < filters.length; i++) {
      final docRef = FirebaseFirestore.instance
          .collection('kiosk_categories')
          .doc(categoryId)
          .collection('filters')
          .doc(filters[i].id);

      batch.update(docRef, {'position': i});
    }
    await batch.commit();
  }

  Future<String> uploadUniversalFile(XFile file, String path) async {
    final ref = _storage.ref().child(path);
    final Uint8List data = await file.readAsBytes();
    final metadata = SettableMetadata(contentType: 'image/jpeg');

    await ref.putData(data, metadata);
    return await ref.getDownloadURL();
  }

  Future<String?> uploadImage(XFile imageFile, String path) async {
    try {
      final ref = _storage.ref(path);
      UploadTask uploadTask;

      if (kIsWeb) {
        final data = await imageFile.readAsBytes();
        uploadTask = ref.putData(data);
      } else {
        uploadTask = ref.putFile(File(imageFile.path));
      }

      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateKioskScreensaver(
      String franchiseeId, List<String> urls) async {
    try {
      await _firestore.collection('users').doc(franchiseeId).update({
        'screensaverUrls': urls,
        'screensaverUrl': urls.isNotEmpty ? urls.first : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateGlobalButtonImages(
      String franchisorId, String? dineInUrl, String? takeawayUrl) async {
    await _firestore.collection('users').doc(franchisorId).update({
      'dineInImageUrl': dineInUrl,
      'takeawayImageUrl': takeawayUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addMasterMedia({
    required String name,
    required String type,
    required XFile file,
    XFile? thumbnailFile,
  }) async {
    try {
      final String mediaId = const Uuid().v4();

      final String ext = type == 'video' ? 'mp4' : 'jpg';
      final String path = 'franchisor_assets/$_currentUserId/$mediaId.$ext';

      final String? url = await uploadImage(file, path);

      if (url == null) throw Exception("Impossible d'uploader le fichier.");

      String? thumbUrl;
      if (thumbnailFile != null) {
        final thumbPath =
            'franchisor_assets/$_currentUserId/${mediaId}_thumb.jpg';
        thumbUrl = await uploadImage(thumbnailFile, thumbPath);
      }

      await _firestore.collection('kiosk_medias').doc(mediaId).set({
        'franchisorId': _currentUserId,
        'name': name,
        'type': type,
        'url': url,
        'thumbnailUrl': thumbUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMasterMedia(String mediaId) async {
    try {
      await _firestore.collection('kiosk_medias').doc(mediaId).delete();
    } catch (e) {
      rethrow;
    }
  }

  Stream<List<KioskMedia>> getAvailableKioskMedias(String franchisorId) {
    return _firestore
        .collection('kiosk_medias')
        .where('franchisorId', isEqualTo: franchisorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => KioskMedia.fromFirestore(doc)).toList());
  }

  Future<void> setKioskActiveMedia(
      String franchiseeId, KioskMedia media) async {
    await _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('config')
        .doc('kiosk_customization')
        .set({
      'activeMediaId': media.id,
      'mediaType': media.type,
      'mediaUrl': media.url,
      'mediaName': media.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('users').doc(franchiseeId).update({
      'screensaverUrl': media.url,
    });
  }

  Future<void> saveKioskWelcomeConfig({
    required String mediaType,
    required String mediaUrl,
    bool showLogo = true,
  }) async {
    await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('config')
        .doc('kiosk_customization')
        .set({
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'showLogo': showLogo,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

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
    final String currentFranchisorId = _currentUserId;
    if (currentFranchisorId.isEmpty) {
      return "Erreur : Impossible d'identifier le franchiseur. Veuillez vous reconnecter.";
    }

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      User? newUser = userCredential.user;

      if (newUser != null) {
        await _firestore.collection('users').doc(newUser.uid).set({
          'email': email,
          'role': 'franchisee',
          'franchisorId': currentFranchisorId,
          'companyName': companyName,
          'contactName': contactName,
          'phone': phone,
          'address': address,
          'createdAt': FieldValue.serverTimestamp(),
          'enabledModules': enabledModules,
        });

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
      if (e.code == 'email-already-in-use') {
        return 'Cette adresse email est déjà utilisée.';
      }
      return e.message;
    } catch (e) {
      return 'Une erreur est survenue: $e';
    }
  }

  Future<String?> createEmployee({
    required String managerId,
    required String email,
    required String password,
    required String name,
  }) async {
    FirebaseApp? secondaryApp;
    try {
      final managerDoc =
      await _firestore.collection('users').doc(managerId).get();

      if (!managerDoc.exists) return "Erreur : Compte manager introuvable.";

      final String franchisorId = managerDoc.get('franchisorId');
      final Map<String, dynamic> enabledModules =
          managerDoc.data()?['enabledModules'] ?? {};

      secondaryApp = await Firebase.initializeApp(
        name: 'EmployeeCreation',
        options: Firebase.app().options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      UserCredential userCredential =
      await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String newUserId = userCredential.user!.uid;

      await _firestore.collection('users').doc(newUserId).set({
        'email': email,
        'role': 'employee',
        'storeId': managerId,
        'franchisorId': franchisorId,
        'companyName': name,
        'createdAt': FieldValue.serverTimestamp(),
        'enabledModules': enabledModules,
      });

      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') return 'Le mot de passe est trop faible.';
      if (e.code == 'email-already-in-use') {
        return 'Cet email est déjà utilisé.';
      }
      return e.message;
    } catch (e) {
      return 'Une erreur est survenue: $e';
    } finally {
      await secondaryApp?.delete();
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
      return 'Une erreur est survenue lors de la mise à jour: $e';
    }
  }

  Stream<List<FranchiseUser>> getFranchiseesForFranchisor(String franchisorId) {
    return _firestore
        .collection('users')
        .where('franchisorId', isEqualTo: franchisorId)
        .where('role', isEqualTo: 'franchisee')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => FranchiseUser.fromFirestore(doc.data(), doc.id))
        .toList());
  }

  Stream<List<FranchiseUser>> getFranchiseesStream(String franchisorId) {
    return _firestore
        .collection('users')
        .where('franchisorId', isEqualTo: franchisorId)
        .where('role', isEqualTo: 'franchisee')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => FranchiseUser.fromFirestore(doc.data(), doc.id))
        .toList());
  }

  Stream<List<FranchiseUser>> getStoreEmployeesStream(String storeId) {
    return _firestore
        .collection('users')
        .where('storeId', isEqualTo: storeId)
        .where('role', isEqualTo: 'employee')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => FranchiseUser.fromFirestore(doc.data(), doc.id))
        .toList());
  }

  Future<void> deleteEmployee(String employeeId) async {
    await _firestore.collection('users').doc(employeeId).delete();
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

  Future<void> saveKioskCategory({
    String? id,
    required String name,
    required int position,
    XFile? imageFile,
    String? existingImageUrl,
  }) async {
    final docRef = id != null
        ? _firestore.collection('kiosk_categories').doc(id)
        : _firestore.collection('kiosk_categories').doc();

    String? finalImageUrl = existingImageUrl;
    if (imageFile != null) {
      final path = 'category_images/${docRef.id}/${imageFile.name}';
      finalImageUrl = await uploadImage(imageFile, path);
    }

    await docRef.set({
      'name': name,
      'position': position,
      'imageUrl': finalImageUrl,
      'createdBy': _currentUserId
    }, SetOptions(merge: true));
  }

  Future<void> addKioskCategory(String uid, String name) async {
    final id = const Uuid().v4();
    await _firestore.collection('kiosk_categories').doc(id).set({
      'id': id,
      'name': name,
      'createdBy': uid,
      'position': 99,
      'filters': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateKioskCategoriesOrder(
      List<KioskCategory> sortedCategories) async {
    final batch = _firestore.batch();
    for (int i = 0; i < sortedCategories.length; i++) {
      final docRef =
      _firestore.collection('kiosk_categories').doc(sortedCategories[i].id);
      batch.update(docRef, {'position': i});
    }
    await batch.commit();
  }

  Future<void> deleteKioskCategory(String categoryId) async =>
      await _firestore.collection('kiosk_categories').doc(categoryId).delete();
// DANS repository.dart

  Future<void> saveKioskFilter({
    required String categoryId,
    String? filterId,
    required String name,
    required int position,
    XFile? imageFile,
    String? existingImageUrl,
    String? color,
  }) async {
    // ... (votre code d'upload image existant) ...
    String? imageUrl = existingImageUrl;
    if (imageFile != null) {
      final path = 'kiosk_filters/$categoryId/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      imageUrl = await uploadUniversalFile(imageFile, path);
    }

    final id = filterId ?? const Uuid().v4();

    await _firestore
        .collection('kiosk_categories')
        .doc(categoryId)
        .collection('filters')
        .doc(id)
        .set({
      'id': id,
      'name': name,
      'position': position,
      'imageUrl': imageUrl,
      'color': color,
    }, SetOptions(merge: true));

    // --- LIGNE CRUCIALE A AJOUTER POUR LE RAFRAICHISSEMENT ---
    await _firestore.collection('kiosk_categories').doc(categoryId).update({'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> deleteKioskFilter({required String categoryId, required String filterId}) async {
    await _firestore
        .collection('kiosk_categories')
        .doc(categoryId)
        .collection('filters')
        .doc(filterId)
        .delete();

    await _firestore.collection('kiosk_categories').doc(categoryId).update({'updatedAt': FieldValue.serverTimestamp()});
  }


  Stream<List<ProductFilter>> getFiltersStream(String franchisorId) {
    return _firestore
        .collection('product_filters')
        .where('createdBy', isEqualTo: franchisorId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map(ProductFilter.fromFirestore).toList());
  }

  Future<void> addFilter(String name, String? color) async =>
      await _firestore.collection('product_filters').add({
        'name': name,
        'createdBy': _currentUserId,
        'color': color,
      });

  Stream<List<ProductSection>> getSectionsStream(String franchisorId,
      {List<String> filterIds = const []}) {
    Query query = _firestore
        .collection('product_sections')
        .where('createdBy', isEqualTo: franchisorId);

    if (filterIds.isNotEmpty) {
      query = query.where('filterIds', arrayContainsAny: filterIds);
    }

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

    if (filterIds.isNotEmpty) {
      query = query.where('filterIds', arrayContainsAny: filterIds);
    }

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

    if (filterIds.isNotEmpty) {
      query = query.where('filterIds', arrayContainsAny: filterIds);
    }

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
    required List<ProductOption> options,
    required List<String> ingredientProductIds,
    required List<String> kioskFilterIds,
    XFile? imageFile,
    String? color,
    String? existingPhotoUrl,
    required String photoUrl,
  }) async {
    final docRef = product != null
        ? _firestore.collection('master_products').doc(product.id)
        : _firestore.collection('master_products').doc();

    final productId = product?.productId ?? const Uuid().v4();

    String? finalPhotoUrl = existingPhotoUrl;
    if (imageFile != null) {
      final path = 'product_images/$productId/${imageFile.name}';
      finalPhotoUrl = await uploadUniversalFile(imageFile, path);
    }

    await docRef.set({
      'productId': productId,
      'name': name,
      'description': description,
      'photoUrl': finalPhotoUrl,
      'createdBy': _currentUserId,
      'isComposite': isComposite,
      'isIngredient': isIngredient,
      'filterIds': filterIds,
      'sectionIds': isComposite ? sectionIds : [],
      'options': isComposite ? options.map((o) => o.toMap()).toList() : [],
      'ingredientProductIds': ingredientProductIds,
      'kioskFilterIds': kioskFilterIds,
      'color': color,
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
      List<CartItem> items, double total,
      {String source = 'pos', String orderType = 'onSite'}) async {
    final itemsAsMap = items
        .map((item) => {
      'masterProductId': item.product.id,
      'name': item.product.name,
      'quantity': item.quantity,
      'basePrice': item.price,
      'vatRate': item.vatRate,
      'isSentToKitchen': item.isSentToKitchen,
      'selectedOptions': item.selectedOptions.entries
          .map((entry) => {
        'sectionId': entry.key,
        'items': entry.value
            .map((sectionItem) => {
          'masterProductId': sectionItem.product.id,
          'name': sectionItem.product.name,
          'supplementPrice':
          sectionItem.supplementPrice,
        })
            .toList(),
      })
          .toList(),
      'removedIngredientProductIds': item.removedIngredientProductIds,
      'removedIngredientNames': item.removedIngredientNames,
    })
        .toList();

    await _firestore.collection('pending_orders').add({
      'franchiseeId': franchiseeId,
      'identifier': identifier,
      'items': itemsAsMap,
      'total': total,
      'timestamp': FieldValue.serverTimestamp(),
      'source': source,
      'orderType': orderType,
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

    if (startDate != null) {
      query = query.where('openingTime', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('openingTime',
          isLessThanOrEqualTo: endDate.add(const Duration(days: 1)));
    }

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
      {DateTime? startDate, DateTime? endDate, int limit = 100}) {
    Query query = _firestore
        .collection('transactions')
        .where('franchiseeId', isEqualTo: franchiseeId);

    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('timestamp',
          isLessThanOrEqualTo: endDate.add(const Duration(days: 1)));
    }

    query = query.orderBy('timestamp', descending: true);
    query = query.limit(limit);

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
    final activeSessionQuery = await _firestore
        .collection('sessions')
        .where('franchiseeId', isEqualTo: franchiseeId)
        .where('isClosed', isEqualTo: false)
        .limit(1)
        .get();

    if (activeSessionQuery.docs.isNotEmpty) {
      throw Exception(
          "Une caisse est déjà ouverte pour ce magasin ! Veuillez la fermer ou la rejoindre.");
    }

    final docRef = _firestore.collection('sessions').doc();
    final newSession = TillSession(
      id: docRef.id,
      franchiseeId: franchiseeId,
      openingTime: DateTime.now(),
      initialCash: initialCash,
    );

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

      final sessionDoc =
      await _firestore.collection('sessions').doc(sessionId).get();
      final franchiseeId = sessionDoc.data()?['franchiseeId'];

      if (franchiseeId != null) {
        await _firestore
            .collection('users')
            .doc(franchiseeId)
            .collection('config')
            .doc('session_order_counter')
            .set({'count': 0}, SetOptions(merge: true));
      }

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String> generateNextGlobalOrderNumber(String franchiseeId) async {
    final counterRef = _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('config')
        .doc('session_order_counter');

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);
      int nextNumber = 1;
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final currentCount = data['count'] as int? ?? 0;
        nextNumber = currentCount + 1;
      }

      transaction.set(
          counterRef,
          {'count': nextNumber, 'last_update': FieldValue.serverTimestamp()},
          SetOptions(merge: true));

      return nextNumber.toString().padLeft(3, '0');
    });
  }

  Future<void> recordTransaction(Transaction transaction) async {
    await _firestore
        .collection('transactions')
        .doc(transaction.id)
        .set(transaction.toMap());
  }

  Future<void> reprintReceipt(String transactionId) async {
    try {
      final callable =
      FirebaseFunctions.instance.httpsCallable('reprintReceipt');
      await callable.call({'transactionId': transactionId});
    } catch (e) {
      if (kDebugMode) {
        print('Erreur lors de la réimpression : $e');
      }
      rethrow;
    }
  }

  Future<void> deleteGlobalButtonImage(
      String franchisorId, String typeKey) async {
    final String fieldName =
    (typeKey == 'dineIn') ? 'dineInImageUrl' : 'takeawayImageUrl';

    await _firestore.collection('users').doc(franchisorId).update({
      fieldName: FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reprintKitchenTicket(String transactionId) async {
    try {
      final callable =
      FirebaseFunctions.instance.httpsCallable('reprintKitchenTicket');
      await callable.call({'transactionId': transactionId});
    } catch (e) {
      if (kDebugMode) {
        print('Erreur réimpression cuisine : $e');
      }
      rethrow;
    }
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

  Stream<List<FranchiseUser>> getTeamMembersStream(String storeId) {
    return _firestore
        .collection('users')
        .where(Filter.or(
      Filter('uid', isEqualTo: storeId),
      Filter('storeId', isEqualTo: storeId),
    ))
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => FranchiseUser.fromFirestore(doc.data(), doc.id))
        .toList());
  }
}