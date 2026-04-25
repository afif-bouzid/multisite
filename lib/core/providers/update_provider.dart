import 'package:flutter/foundation.dart';
import '../services/update_service.dart';

class UpdateProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _hasUpdate = false;
  String? _latestVersion;
  String? _apkUrl;
  bool get isLoading => _isLoading;
  bool get hasUpdate => _hasUpdate;
  String? get latestVersion => _latestVersion;
  String? get apkUrl => _apkUrl;
  UpdateProvider() {
    checkNowForUpdate();
  }
  Future<void> checkNowForUpdate() async {
    _isLoading = true;
    _hasUpdate = false;
    notifyListeners();
    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (updateInfo != null) {
        _hasUpdate = true;
        _latestVersion = updateInfo['version'];
        _apkUrl = updateInfo['apkUrl'];
      }
    } catch (e) {
      _hasUpdate = false;
      debugPrint("Erreur (UpdateProvider): $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> downloadAndInstallUpdate() async {
    if (_apkUrl == null || _isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      await UpdateService.downloadAndInstall(_apkUrl!);
    } catch (e) {
      debugPrint("Erreur installation (UpdateProvider): $e");
      _isLoading = false;
      notifyListeners();
    }
  }
}
