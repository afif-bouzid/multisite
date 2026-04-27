import 'package:flutter/foundation.dart';
import '../services/update_service.dart';

class UpdateProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _hasUpdate = false;
  String? _latestVersion;
  String? _downloadUrl;
  String? _fileName;
  double _progress = 0.0;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get hasUpdate => _hasUpdate;
  String? get latestVersion => _latestVersion;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;

  UpdateProvider() {
    checkNowForUpdate();
  }

  Future<void> checkNowForUpdate() async {
    if (_isLoading) return;
    _isLoading = true;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();
    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (updateInfo != null) {
        _hasUpdate = true;
        _latestVersion = updateInfo['version'];
        _downloadUrl = updateInfo['url'];
        _fileName = updateInfo['fileName'];
      } else {
        _hasUpdate = false;
      }
    } catch (e) {
      _hasUpdate = false;
      _errorMessage = e.toString();
      debugPrint("Erreur (UpdateProvider): $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> downloadAndInstallUpdate() async {
    if (_downloadUrl == null || _fileName == null || _isLoading) return;
    _isLoading = true;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();
    try {
      await UpdateService.downloadAndInstall(
        _downloadUrl!,
        _fileName!,
        onProgress: (received, total) {
          if (total > 0) {
            _progress = received / total;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      _errorMessage = "Échec de la mise à jour : $e";
      debugPrint("Erreur installation (UpdateProvider): $e");
      _isLoading = false;
      notifyListeners();
    }
  }
}