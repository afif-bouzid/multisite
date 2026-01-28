import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart';
import '../../models.dart'; // Assurez-vous d'importer votre modèle MasterProduct

class ImageSyncService {
  /// Télécharge et met en cache toutes les images des produits fournis
  Future<void> preCacheProductImages(List<MasterProduct> products, {Function(int, int)? onProgress}) async {
    int total = products.where((p) => p.photoUrl != null && p.photoUrl!.isNotEmpty).length;
    int current = 0;

    for (var product in products) {
      if (product.photoUrl != null && product.photoUrl!.isNotEmpty) {
        try {
          // Vérifie si le fichier est déjà en cache valide
          final fileInfo = await DefaultCacheManager().getFileFromCache(product.photoUrl!);

          if (fileInfo == null) {
            // Si pas en cache, on le télécharge explicitement
            await DefaultCacheManager().downloadFile(product.photoUrl!);
          }

          current++;
          if (onProgress != null) onProgress(current, total);

        } catch (e) {
          if (kDebugMode) print("Erreur pré-chargement image ${product.name}: $e");
        }
      }
    }
  }
}