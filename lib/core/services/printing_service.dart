import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

class PrintJobData {
  final String ipAddress;
  final int port;
  final PaperSize paperSize;
  final String header;
  final String identifier;
  final String time;
  final List<String> itemLines;

  PrintJobData({
    required this.ipAddress,
    required this.port,
    required this.paperSize,
    required this.header,
    required this.identifier,
    required this.time,
    required this.itemLines,
  });
}

Future<void> _printInIsolate(PrintJobData data) async {
  final profile = await CapabilityProfile.load();
  final printer = NetworkPrinter(data.paperSize, profile);
  final PosPrintResult res = await printer.connect(data.ipAddress,
      port: data.port, timeout: const Duration(seconds: 5));

  if (res == PosPrintResult.success) {
    printer.text(data.header,
        styles: const PosStyles(
            align: PosAlign.center, height: PosTextSize.size2, bold: true));

    if (data.identifier.contains(' - ')) {
      final parts = data.identifier.split(' - ');
      final source = parts[0];
      final name = parts.length > 1 ? parts[1] : '';

      printer.text(source.toUpperCase(),
          styles: const PosStyles(align: PosAlign.center, bold: true));
      printer.text(name.toUpperCase(),
          styles: const PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size3,
              width: PosTextSize.size3,
              bold: true));
    } else {
      printer.text(data.identifier,
          styles: const PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size3,
              width: PosTextSize.size2,
              bold: true));
    }

    printer.text(data.time, styles: const PosStyles(align: PosAlign.center));
    printer.hr();

    for (final line in data.itemLines) {
      printer.text(line);
    }

    printer.feed(2);
    printer.cut();
    printer.disconnect();
  }
}

class PrintingService {
  Future<void> printKitchenTicketSafe({
    required PrinterConfig printerConfig,
    required List<CartItem> itemsToPrint,
    required String identifier,
    bool isUpdate = false,
    bool isReprint = false,
  }) async {
    String headerText;
    if (isReprint) {
      headerText = '--- RÉIMPRESSION ---';
    } else if (isUpdate) {
      headerText = '--- AJOUT ---';
    } else {
      headerText = '--- NOUVEAU ---';
    }

    final List<String> formattedLines = [];
    for (final item in itemsToPrint) {
      formattedLines.add('1x ${item.product.name}');
      if (item.selectedOptions.isNotEmpty) {
        final optionsText = item.selectedOptions.values
            .expand((x) => x)
            .map((e) => "  + ${e.product.name}")
            .toList();
        formattedLines.addAll(optionsText);
      }
      if (item.removedIngredientNames.isNotEmpty) {
        for (var name in item.removedIngredientNames) {
          formattedLines.add("  - SANS $name");
        }
      }
    }

    final jobData = PrintJobData(
      ipAddress: printerConfig.ipAddress,
      port: 9100,
      paperSize: printerConfig.paperWidth == PaperWidth.mm80
          ? PaperSize.mm80
          : PaperSize.mm58,
      header: headerText,
      identifier: identifier,
      time: DateFormat('HH:mm:ss').format(DateTime.now()),
      itemLines: formattedLines,
    );
    await compute(_printInIsolate, jobData);
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
        port: 9100, timeout: const Duration(seconds: 2));
    if (res != PosPrintResult.success) {
      throw Exception('Impossible de se connecter à l\'imprimante: ${res.msg}');
    }

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

    if (transaction.discountAmount > 0) {
      printer.row([
        PosColumn(text: 'Sous-Total', width: 6),
        PosColumn(
            text: '${transaction.subTotal.toStringAsFixed(2)} EUR',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      printer.row([
        PosColumn(text: 'Remise', width: 6),
        PosColumn(
            text: '-${transaction.discountAmount.toStringAsFixed(2)} EUR',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      printer.hr(ch: '-');
    }

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

    printer.text(receiptConfig.footerText,
        styles: const PosStyles(align: PosAlign.center));
    printer.feed(2);
    if (transaction.paymentMethods.containsKey('Cash')) {
      printer.drawer(pin: PosDrawer.pin2);
    }

    printer.cut(mode: PosCutMode.partial);
    printer.disconnect();
  }

  Future<void> printTestTicket({required PrinterConfig printerConfig}) async {
    final PaperSize paper = printerConfig.paperWidth == PaperWidth.mm80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paper, profile);
    final PosPrintResult res = await printer.connect(
      printerConfig.ipAddress,
      port: 9100,
      timeout: const Duration(seconds: 15),
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
    printer.cut(mode: PosCutMode.partial);
    printer.disconnect();
  }

  Future<void> printZTicket({
    required PrinterConfig printerConfig,
    required TillSession session,
    required List<Transaction> transactions,
    required double declaredCash,
    required bool isManager,
    required String userName,
  }) async {
    final profile = await CapabilityProfile.load();
    final PaperSize paper = printerConfig.paperWidth == PaperWidth.mm80
        ? PaperSize.mm80
        : PaperSize.mm58;

    final printer = NetworkPrinter(paper, profile);

    final PosPrintResult res = await printer.connect(printerConfig.ipAddress,
        port: 9100, timeout: const Duration(seconds: 15));

    if (res != PosPrintResult.success) {
      throw Exception('Imprimante déconnectée : ${res.msg}');
    }

    double totalSales = 0.0;
    double cashSales = 0.0;
    double cardSales = 0.0;
    double ticketSales = 0.0;

    for (var t in transactions) {
      totalSales += t.total;
      cashSales += (t.paymentMethods['Cash'] as num?)?.toDouble() ?? 0.0;
      cardSales += (t.paymentMethods['Card'] as num?)?.toDouble() ?? 0.0;
      ticketSales += (t.paymentMethods['Ticket'] as num?)?.toDouble() ?? 0.0;
    }

    final double theoreticalTotal = session.initialCash + cashSales;
    final double discrepancy = declaredCash - theoreticalTotal;

    printer.text('CLOTURE DE CAISSE (Z)',
        styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true));
    printer.feed(1);

    printer.text(
        'Date : ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
    printer.text('Fermé par : $userName');
    printer.hr();

    printer.text('FONDS DE CAISSE', styles: const PosStyles(bold: true));
    printer.row([
      PosColumn(text: 'Ouverture :', width: 8),
      PosColumn(
          text: '${session.initialCash.toStringAsFixed(2)} EUR',
          width: 4,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    printer.row([
      PosColumn(
          text: 'DÉCLARÉ (Fermeture) :',
          width: 8,
          styles: const PosStyles(bold: true)),
      PosColumn(
          text: '${declaredCash.toStringAsFixed(2)} EUR',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    printer.hr();

    if (isManager) {
      printer.text('VENTILATION VENTES (Manager)',
          styles: const PosStyles(bold: true, underline: true));
      printer.row([
        PosColumn(text: 'Total Ventes :', width: 8),
        PosColumn(
            text: '${totalSales.toStringAsFixed(2)} EUR',
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      printer.text('Dont Espèces : ${cashSales.toStringAsFixed(2)}');
      printer.text('Dont CB : ${cardSales.toStringAsFixed(2)}');
      printer.text('Dont Tickets : ${ticketSales.toStringAsFixed(2)}');

      printer.hr();

      printer.text('CONTRÔLE ÉCARTS',
          styles: const PosStyles(bold: true, underline: true));
      printer.row([
        PosColumn(text: 'Théorique Espèces :', width: 8),
        PosColumn(
            text: '${theoreticalTotal.toStringAsFixed(2)} EUR',
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);

      printer.feed(1);

      printer.text(
          'ECART CAISSE : ${discrepancy > 0 ? '+' : ''}${discrepancy.toStringAsFixed(2)} EUR',
          styles: const PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size1));
    } else {
      printer.text('*** CLOTURE AVEUGLE ***',
          styles: const PosStyles(align: PosAlign.center));
      printer.text('Montants enregistrés.',
          styles: const PosStyles(align: PosAlign.center));
      printer.text('Validation manager requise.',
          styles: const PosStyles(align: PosAlign.center));
    }

    printer.feed(2);
    printer.text('Signature Responsable :',
        styles: const PosStyles(underline: true));
    printer.feed(3);

    printer.cut();
    printer.disconnect();
  }
}
