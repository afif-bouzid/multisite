import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
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
  Future<void> updateFranchiseeMenuItem({
    required String franchiseeId,
    required String masterProductId,
    required double price,
    required bool isVisible,
    required bool isAvailable,
  }) async {
    await _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('menu')
        .doc(masterProductId)
        .set({
      'masterProductId': masterProductId,
      'price': price,
      'isVisible': isVisible,
      'isAvailable': isAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<FranchiseeMenuItem>> getFranchiseeMenuStream(
      String franchiseeId) {
    return _firestore
        .collection('users')
        .doc(franchiseeId)
        .collection('menu')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FranchiseeMenuItem.fromFirestore(doc.data()))
            .toList());
  }

  Future<void> saveProduct({
    MasterProduct? product,
    required String name,
    required String description,
    required bool isComposite,
    required bool isIngredient,
    required bool isContainer,
    required List<String> containerProductIds,
    required List<String> filterIds,
    required List<String> sectionIds,
    required List<String> ingredientProductIds,
    required List<String> kioskFilterIds,
    XFile? imageFile,
    String? color,
    String? existingPhotoUrl,
    required String photoUrl,
    List<ProductOption>? options,
  }) async {
    final docRef = product != null
        ? _firestore.collection('master_products').doc(product.id)
        : _firestore.collection('master_products').doc();
    final productId = product?.productId ?? const Uuid().v4();
    String? finalPhotoUrl = photoUrl;
    if (imageFile != null) {
      final ref = _storage.ref(
          'product_images/$productId/${DateTime.now().millisecondsSinceEpoch}.png');
      final Uint8List bytes = await imageFile.readAsBytes();
      final metadata = SettableMetadata(
        contentType: 'image/png',
        cacheControl: 'public,max-age=3600',
      );
      await ref.putData(bytes, metadata);
      finalPhotoUrl = await ref.getDownloadURL();
    }
    final optionsMapList = options?.map((o) => o.toMap()).toList() ?? [];
    await docRef.set({
      'productId': productId,
      'name': name,
      'description': description,
      'isComposite': isComposite,
      'isIngredient': isIngredient,
      'isContainer': isContainer,
      'containerProductIds': containerProductIds,
      'filterIds': filterIds,
      'sectionIds': sectionIds,
      'kioskFilterIds': kioskFilterIds,
      'photoUrl': finalPhotoUrl,
      'color': color,
      'options': optionsMapList,
      'createdBy': _currentUserId,
      'updatedAt': FieldValue.serverTimestamp(),
      'ingredientProductIds': ingredientProductIds,
    }, SetOptions(merge: true));
  }

  Stream<List<MasterProduct>> getMasterProductsStream(String franchisorId) {
    return _firestore
        .collection('master_products')
        .where('createdBy', isEqualTo: franchisorId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MasterProduct.fromFirestore(doc.data(), doc.id))
            .toList());
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
        categories.add(KioskCategory(
            id: doc.id,
            name: doc['name'],
            filters: [],
            position: doc['position'] ?? 0,
            imageUrl: doc['imageUrl']));
      }
      return categories;
    });
  }

  Future<List<ProductSection>> getSectionsForProduct(
      String franchisorId, List<String> sectionIds) async {
    if (sectionIds.isEmpty) return [];
    final snapshot = await _firestore
        .collection('product_sections')
        .where('sectionId', whereIn: sectionIds.take(10).toList())
        .get();
    List<ProductSection> sections = [];
    for (var doc in snapshot.docs) {
      sections.add(ProductSection(
          id: doc.id, sectionId: doc['sectionId'], title: doc['title']));
    }
    return sections;
  }
}
