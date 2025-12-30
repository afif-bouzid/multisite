import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PosLocalConfig {
  String franchiseeId;
  String franchisorId;
  String email;
  String receiptPrinterIp;
  String kitchenPrinterIp;
  bool isAutoPrintEnabled;

  PosLocalConfig({
    this.franchiseeId = "",
    this.franchisorId = "",
    this.email = "",
    this.receiptPrinterIp = "",
    this.kitchenPrinterIp = "",
    this.isAutoPrintEnabled = false,
  });

  Map<String, dynamic> toJson() => {
        'franchiseeId': franchiseeId,
        'franchisorId': franchisorId,
        'email': email,
        'receiptPrinterIp': receiptPrinterIp,
        'kitchenPrinterIp': kitchenPrinterIp,
        'isAutoPrintEnabled': isAutoPrintEnabled,
      };

  factory PosLocalConfig.fromJson(Map<String, dynamic> json) {
    return PosLocalConfig(
      franchiseeId: json['franchiseeId'] ?? "",
      franchisorId: json['franchisorId'] ?? "",
      email: json['email'] ?? "",
      receiptPrinterIp: json['receiptPrinterIp'] ?? "",
      kitchenPrinterIp: json['kitchenPrinterIp'] ?? "",
      isAutoPrintEnabled: json['isAutoPrintEnabled'] ?? false,
    );
  }
}

class LocalConfigService {
  static const String _fileName = "pos_config.json";

  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }

  Future<PosLocalConfig> loadConfig() async {
    try {
      final path = await _getFilePath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        return PosLocalConfig.fromJson(jsonDecode(content));
      }
    } catch (e) {}
    return PosLocalConfig();
  }

  Future<void> saveConfig(PosLocalConfig config) async {
    final path = await _getFilePath();
    final file = File(path);
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  Future<void> clearConfig() async {
    try {
      final path = await _getFilePath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {}
  }
}
