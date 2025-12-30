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
      final response = await http.get(Uri.parse(
          'https://api.github.com/repos/$repoOwner/$repoName/releases/latest'));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final tagName = data['tag_name'];

      final apkAsset = (data['assets'] as List)
          .firstWhere((e) => e['name'].endsWith('.apk'), orElse: () => null);

      if (tagName == null || apkAsset == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final latestVersion = tagName.replaceFirst('v', '');

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
    } catch (_) {}

    return false;
  }

  static Future<void> downloadAndInstall(String apkUrl) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/update.apk");

      final response = await http.get(Uri.parse(apkUrl));
      if (response.statusCode != 200) {
        throw Exception("Échec du téléchargement : ${response.statusCode}");
      }

      await file.writeAsBytes(response.bodyBytes);

      await platform.invokeMethod("installApk", {
        "path": file.path,
      });
    } catch (e) {
      debugPrint("Erreur install APK: $e");
      throw Exception("Impossible d'installer l'APK : $e");
    }
  }
}
