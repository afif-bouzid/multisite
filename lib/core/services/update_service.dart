import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String repoOwner = 'afif-bouzid';
  static const String repoName = 'pos_android';
  static const platform = MethodChannel("apk_install");

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      // CORRECTION : L'URL était tronquée. Voici l'URL complète de l'API GitHub.
      final response = await http.get(Uri.parse(
          'https://api.github.com/repos/$repoOwner/$repoName/releases/latest'));

      if (response.statusCode != 200) {
        debugPrint("Erreur GitHub API: ${response.statusCode}");
        return null;
      }

      final data = jsonDecode(response.body);
      final tagName = data['tag_name'];
      final assets = data['assets'] as List?;

      if (assets == null || assets.isEmpty) return null;

      // Recherche du fichier .apk dans les assets de la release
      final apkAsset = assets.firstWhere(
        (e) => e['name'].toString().toLowerCase().endsWith('.apk'),
        orElse: () => null,
      );

      if (tagName == null || apkAsset == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      // Nettoyage du tag (ex: "v1.0.1" devient "1.0.1")
      final latestVersion = tagName.toString().replaceAll('v', '');

      if (_isNewer(latestVersion, currentVersion)) {
        return {
          "version": latestVersion,
          "apkUrl": apkAsset["browser_download_url"],
        };
      }
    } catch (e) {
      debugPrint("Erreur check update: $e");
    }
    return null;
  }

  static bool _isNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();
      final maxLen = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;

      for (int i = 0; i < maxLen; i++) {
        final l = (i < latestParts.length) ? latestParts[i] : 0;
        final c = (i < currentParts.length) ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<void> downloadAndInstall(String apkUrl) async {
    try {
      final dir = await getTemporaryDirectory();
      final savePath = "${dir.path}/update.apk";
      final file = File(savePath);

      if (await file.exists()) {
        await file.delete();
      }

      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception("Échec du téléchargement : ${response.statusCode}");
      }

      final sink = file.openWrite();
      await response.stream.pipe(sink);
      await sink.close();

      debugPrint("Téléchargement terminé : $savePath");
      await platform.invokeMethod("installApk", {"path": savePath});
    } catch (e) {
      debugPrint("Erreur lors de la mise à jour : $e");
      rethrow;
    }
  }
}
