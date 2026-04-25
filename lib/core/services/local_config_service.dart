import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models.dart';

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
  static const String _printerConfigKey = 'printer_config';
  static const String _receiptConfigKey = 'receipt_config';

  Future<PrinterConfig> getPrinterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_printerConfigKey);
    if (jsonString != null) {
      try {
        return PrinterConfig.fromFirestore(json.decode(jsonString));
      } catch (e) {
        return PrinterConfig();
      }
    }
    return PrinterConfig();
  }

  Future<void> savePrinterConfig(PrinterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    String jsonString = json.encode(config.toMap());
    await prefs.setString(_printerConfigKey, jsonString);
  }

  Future<ReceiptConfig> getReceiptConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_receiptConfigKey);
    if (jsonString != null) {
      try {
        return ReceiptConfig.fromMap(json.decode(jsonString));
      } catch (e) {
        return ReceiptConfig(
            headerText: '',
            footerText: '',
            showVatDetails: true,
            printReceiptOnPayment: true);
      }
    }
    return ReceiptConfig(
        headerText: '',
        footerText: '',
        showVatDetails: true,
        printReceiptOnPayment: true);
  }

  Future<void> saveReceiptConfig(ReceiptConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    String jsonString = json.encode(config.toMap());
    await prefs.setString(_receiptConfigKey, jsonString);
  }
}