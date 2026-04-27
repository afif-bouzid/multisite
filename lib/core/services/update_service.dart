import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String repoOwner = 'afif-bouzid';
  static const String repoName = 'pos_android'; // ← ton repo POS

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      String targetExtension = '';
      if (Platform.isWindows) {
        targetExtension = '.msix';
      } else if (Platform.isAndroid) {
        targetExtension = '.apk';
      } else {
        return null;
      }

      final url = Uri.parse(
          'https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final tagName = data['tag_name'];
      final assets = data['assets'] as List?;
      if (assets == null || assets.isEmpty) return null;

      final installerAsset = assets.firstWhere(
            (e) => e['name'].toString().toLowerCase().endsWith(targetExtension),
        orElse: () => null,
      );
      if (installerAsset == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final cleanTag = tagName.toString().replaceAll('v', '');

      if (_isNewerVersion(cleanTag, currentVersion)) {
        return {
          'version': cleanTag,
          'url': installerAsset['browser_download_url'],
          'fileName': installerAsset['name'],
          'notes': data['body'] ?? "Mise à jour disponible.",
        };
      }
    } catch (e) {
      debugPrint("Erreur check update: $e");
    }
    return null;
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      final lParts = latest.split('.').map(int.parse).toList();
      final cParts = current.split('.').map(int.parse).toList();
      final max = lParts.length > cParts.length ? lParts.length : cParts.length;
      for (int i = 0; i < max; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> downloadAndInstall(
      String downloadUrl,
      String fileName, {
        Function(int received, int total)? onProgress,
      }) async {
    try {
      final dir = await getTemporaryDirectory();
      final savePath = "${dir.path}/$fileName";
      final file = File(savePath);
      if (await file.exists()) await file.delete();

      debugPrint("Début téléchargement : $downloadUrl");
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception("Erreur HTTP ${response.statusCode}");
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await response.stream.listen(
            (List<int> chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (onProgress != null && totalBytes > 0) {
            onProgress(receivedBytes, totalBytes);
          }
        },
        onDone: () async => await sink.close(),
        onError: (e) {
          sink.close();
          throw e;
        },
        cancelOnError: true,
      ).asFuture();

      final len = await file.length();
      if (len < 500000) {
        throw Exception("Fichier corrompu (trop petit : ${len}b)");
      }

      debugPrint("Installation de $savePath...");

      if (Platform.isWindows) {
        final windowsPath = savePath.replaceAll('/', '\\');
        debugPrint("Lancement MSIX : $windowsPath");
        await Process.start(
          'explorer.exe',
          [windowsPath],
          mode: ProcessStartMode.detached,
        );
        await Future.delayed(const Duration(seconds: 3));
        exit(0);
      } else if (Platform.isAndroid) {
        final result = await OpenFilex.open(
          savePath,
          type: "application/vnd.android.package-archive",
        );
        if (result.type != ResultType.done) {
          throw Exception("Erreur installation : ${result.message}");
        }
      }
    } catch (e) {
      debugPrint("ERREUR MAJ : $e");
      rethrow;
    }
  }
}