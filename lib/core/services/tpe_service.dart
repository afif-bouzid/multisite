import 'dart:async';
import 'package:flutter/foundation.dart';
class TpeResult {
  final bool success;
  final String message;
  final String code;
  final String? ticketClient;
  final String? authNumber;
  TpeResult({
    required this.success,
    required this.message,
    this.code = "",
    this.ticketClient,
    this.authNumber,
  });
}
class TpeService {
  bool get _isSimulationMode {
    return kDebugMode;
  }
  Future<TpeResult> sendPaymentRequest({
    required String ipAddress,
    required double amount,
  }) async {
    if (_isSimulationMode) {
      debugPrint("--- ⚠️ TPE EN MODE SIMULATION (DEBUG) ---");
      await Future.delayed(const Duration(seconds: 2));
      return TpeResult(
          success: true,
          message: "Paiement accepté (SIMULATION)",
          code: "00",
          authNumber: "987654");
    }
    return TpeResult(
        success: false,
        message: "Erreur : Module TPE réel non configuré ou connexion échouée.",
        code: "ERR_PROD");
  }
}
