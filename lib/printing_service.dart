import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import 'models.dart';

class PrintingService {
  Future<void> printKitchenTicket({
    required PrinterConfig printerConfig,
    required List<CartItem> itemsToPrint,
    required String identifier,
    bool isUpdate = false,
  }) async {
    final PaperSize paper = printerConfig.paperWidth == PaperWidth.mm80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paper, profile);
    final PosPrintResult res = await printer.connect(printerConfig.ipAddress,
        port: 9100, timeout: const Duration(seconds: 5));
    if (res != PosPrintResult.success) {
      throw Exception(
          'Erreur de connexion à l\'imprimante cuisine: ${res.msg}');
    }

// --- Ticket Generation ---
    printer.text(isUpdate ? '--- AJOUT ---' : '--- NOUVEAU ---',
        styles: const PosStyles(
            align: PosAlign.center, height: PosTextSize.size2, bold: true));
    printer.text(identifier,
        styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size3,
            width: PosTextSize.size2,
            bold: true));
    printer.text(DateFormat('HH:mm:ss').format(DateTime.now()),
        styles: const PosStyles(align: PosAlign.center));
    printer.hr();
    for (final item in itemsToPrint) {
      printer.text('1x ${item.product.name}',
          styles: const PosStyles(height: PosTextSize.size2, bold: true));
      if (item.selectedOptions.isNotEmpty) {
        final optionsText = item.selectedOptions.values
            .expand((x) => x)
            .map((e) => "  + ${e.product.name}")
            .join("\n");
        printer.text(optionsText);
      }
    }

    printer.feed(2);
    printer.cut();
    printer.disconnect();
  }

  Future<void> printReceipt({
    required PrinterConfig printerConfig,
    required ReceiptConfig receiptConfig,
    required Transaction transaction,
    required FranchiseUser franchisee,
  }) async {
    final PaperSize paper = printerConfig.paperWidth == PaperWidth.mm80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paper, profile);
    final PosPrintResult res = await printer.connect(printerConfig.ipAddress,
        port: 9100, timeout: const Duration(seconds: 5));
    if (res != PosPrintResult.success) {
      throw Exception('Impossible de se connecter à l\'imprimante: ${res.msg}');
    }

// --- Header ---
    if (franchisee.companyName != null) {
      printer.text(franchisee.companyName!,
          styles: const PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size2,
              width: PosTextSize.size2));
    }
    if (franchisee.address != null) {
      printer.text(franchisee.address!,
          styles: const PosStyles(align: PosAlign.center));
    }
    printer.hr();

// --- Info ---
    printer.row([
      PosColumn(
          text:
              'Date: ${DateFormat('dd/MM/yy HH:mm').format(transaction.timestamp)}',
          width: 6),
      PosColumn(
          text: 'Ticket #${transaction.id.substring(0, 6)}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    printer.hr();

// --- Items ---
    for (final item in transaction.items) {
      printer.text(item['name'] as String? ?? 'Article');
      printer.row([
        PosColumn(
            text: '1 x ${(item['price'] as num).toStringAsFixed(2)}', width: 6),
        PosColumn(
            text: '${(item['total'] as num).toStringAsFixed(2)} EUR',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    printer.hr();

// --- Totals ---
    printer.row([
      PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: const PosStyles(
              height: PosTextSize.size2, width: PosTextSize.size2)),
      PosColumn(
          text: '${transaction.total.toStringAsFixed(2)} EUR',
          width: 6,
          styles: const PosStyles(
              align: PosAlign.right,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
    ]);
    if (receiptConfig.showVatDetails) {
      printer.row([
        PosColumn(text: 'Dont TVA', width: 6),
        PosColumn(
            text: '${transaction.vatTotal.toStringAsFixed(2)} EUR',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    printer.hr();

// --- Footer ---
    printer.text(receiptConfig.footerText,
        styles: const PosStyles(align: PosAlign.center));
    printer.feed(2);
    printer.cut();
    printer.disconnect();
  }

  /// --- NOUVELLE MÉTHODE POUR LE TEST D'IMPRESSION ---
  Future<void> printTestTicket({required PrinterConfig printerConfig}) async {
    final PaperSize paper = printerConfig.paperWidth == PaperWidth.mm80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paper, profile);

    final PosPrintResult res = await printer.connect(
      printerConfig.ipAddress,
      port: 9100,
      timeout: const Duration(seconds: 5),
    );

    if (res != PosPrintResult.success) {
      throw Exception('Erreur de connexion: ${res.msg}');
    }

    printer.text(
      '--- TICKET DE TEST ---',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    printer.feed(1);
    printer.text(
      "L'imprimante fonctionne correctement.",
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.text(
      'Imprimante: ${printerConfig.name}',
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.text(
      'Adresse IP: ${printerConfig.ipAddress}',
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.feed(1);
    printer.text(
      DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()),
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.feed(2);
    printer.cut();
    printer.disconnect();
  }
}
