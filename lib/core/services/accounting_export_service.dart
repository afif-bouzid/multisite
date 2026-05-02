import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;
import '../../models.dart';

class AccountingExportService {
  final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
  final currencyFormatter = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
  static const int kBusinessDayStartHour = 5;

  /// Vérifie si la transaction provient d'une borne
  bool _isBorne(dynamic tx) {
    try {
      final source = tx.source?.toString().toLowerCase() ?? '';
      if (source == 'borne' || source == 'kiosk') return true;
      
      final methods = tx.paymentMethods as Map<String, dynamic>? ?? {};
      if (methods.containsKey('Card_Kiosk')) return true;

      final type = tx.orderType?.toString().toLowerCase() ?? '';
      if (type.contains('borne')) return true;
    } catch (_) {}
    return false;
  }

  /// Calcule la date commerciale (si avant 05h00, jour précédent)
  DateTime _getBusinessDate(DateTime ts) {
    if (ts.hour < kBusinessDayStartHour) {
      return ts.subtract(const Duration(days: 1));
    }
    return ts;
  }

  /// Génère le contenu CSV avec ventilation TVA et journée commerciale
  String generateCSV(List<dynamic> transactions) {
    List<List<dynamic>> rows = [];

    // En-tête enrichi
    rows.add([
      "Date Civile",
      "Date Comptable",
      "Heure",
      "ID Transaction",
      "Type",
      "Total TTC",
      "TVA 5.5%",
      "TVA 10%",
      "TVA 20%",
      "Espèces",
      "CB Borne",
      "CB Comptoir",
      "Ticket Resto",
      "Autres"
    ]);

    for (var tx in transactions) {
      double cash = 0, cbKiosk = 0, cbCounter = 0, ticket = 0, others = 0;
      double v55 = 0, v10 = 0, v20 = 0;

      // 1. Ventilation Paiements
      final isBorne = _isBorne(tx);
      (tx.paymentMethods as Map<String, dynamic>? ?? {}).forEach((method, amount) {
        double val = (amount as num).toDouble();
        if (method == 'Cash') cash += val;
        else if (method == 'Ticket') ticket += val;
        else if (method == 'Card_Kiosk') cbKiosk += val;
        else if (method == 'Card_Counter') cbCounter += val;
        else if (method == 'Card') {
          if (isBorne) cbKiosk += val; else cbCounter += val;
        } else others += val;
      });

      // 2. Ventilation TVA (basée sur les items si disponibles)
      try {
        final items = tx.items as List<dynamic>? ?? [];
        final itemsTtcSum = items.fold<double>(0.0, (acc, item) {
          final p = (item['price'] as num?)?.toDouble() ?? 0.0;
          final q = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          return acc + (p * q);
        });
        
        final discountAmount = (tx.discountAmount as num?)?.toDouble() ?? 0.0;
        final discountRatio = (itemsTtcSum > 0.001 && discountAmount > 0.001)
            ? (1.0 - (discountAmount / itemsTtcSum)).clamp(0.0, 1.0)
            : 1.0;

        for (var item in items) {
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final taxRate = (item['vatRate'] as num?)?.toDouble() ?? 
                         (item['taxRate'] as num?)?.toDouble() ?? 10.0;

          final itemTtc = price * qty * discountRatio;
          final itemTva = itemTtc - (itemTtc / (1 + (taxRate / 100)));

          if ((taxRate - 5.5).abs() < 0.1) v55 += itemTva;
          else if ((taxRate - 20.0).abs() < 0.1) v20 += itemTva;
          else v10 += itemTva;
        }
      } catch (e) {
        // En cas d'erreur de parsing, on laisse la TVA à 0 ou on pourrait logger
      }

      rows.add([
        DateFormat('dd/MM/yyyy').format(tx.timestamp),
        DateFormat('dd/MM/yyyy').format(_getBusinessDate(tx.timestamp)),
        DateFormat('HH:mm').format(tx.timestamp),
        tx.id,
        tx.orderType,
        tx.total,
        v55.toStringAsFixed(2),
        v10.toStringAsFixed(2),
        v20.toStringAsFixed(2),
        cash.toStringAsFixed(2),
        cbKiosk.toStringAsFixed(2),
        cbCounter.toStringAsFixed(2),
        ticket.toStringAsFixed(2),
        others.toStringAsFixed(2),
      ]);
    }
    return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
  }

  /// Déclenche le téléchargement ou le partage du fichier
  Future<void> shareCsvFile(String csvData) async {
    final fileName =
        'export_comptable_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

    // Ajout du BOM UTF-8 pour que Excel lise bien les accents et l'euro
    final encodedData = '\uFEFF$csvData';

    if (kIsWeb) {
      final bytes = utf8.encode(encodedData);
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      final bytes = Uint8List.fromList(utf8.encode(encodedData));
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  // ... (Le reste du code pour le PDF reste identique)
  Future<void> generateAccountingPdf(
      TillSession session,
      List<dynamic> transactions,
      Map<String, double> vatBreakdown,
      String operatorName, {
        String? companyName,
        String? companyAddress,
        String? companySiret,
      }) async {
    final pdf = pw.Document();
    double totalCA = transactions.fold(
        0, (sum, item) => sum + (item.total as num).toDouble());
    double totalTVA = vatBreakdown.values.fold(0, (sum, val) => sum + val);
    double totalHT = totalCA - totalTVA;

    // Logique de ventilation pour le PDF
    Map<String, double> payments = {
      'CB Borne': 0.0,
      'CB Comptoir': 0.0,
      'Espèces': 0.0,
      'Ticket Resto': 0.0,
    };

    for (var tx in transactions) {
      (tx.paymentMethods as Map<String, dynamic>).forEach((key, value) {
        double val = (value as num).toDouble();
        if (key == 'Card_Kiosk') payments['CB Borne'] = (payments['CB Borne'] ?? 0) + val;
        else if (key == 'Card_Counter') payments['CB Comptoir'] = (payments['CB Comptoir'] ?? 0) + val;
        else if (key == 'Cash') payments['Espèces'] = (payments['Espèces'] ?? 0) + val;
        else if (key == 'Ticket') payments['Ticket Resto'] = (payments['Ticket Resto'] ?? 0) + val;
        else if (key == 'Card') {
          bool isBorne = false;
          try { if (tx.source?.toString() == 'borne') isBorne = true; } catch (_) {}
          if (isBorne) payments['CB Borne'] = (payments['CB Borne'] ?? 0) + val;
          else payments['CB Comptoir'] = (payments['CB Comptoir'] ?? 0) + val;
        }
      });
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            _buildHeader(session, operatorName, companyName, companyAddress,
                companySiret),
            pw.Divider(),
            _buildSummarySection(totalHT, totalTVA, totalCA),
            pw.SizedBox(height: 20),
            _buildVatTable(vatBreakdown),
            pw.SizedBox(height: 20),
            _buildPaymentTable(payments),
            pw.SizedBox(height: 30),
            _buildFooter(),
          ];
        },
      ),
    );
    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Z_Caisse_${DateFormat('yyyyMMdd').format(session.openingTime)}');
  }

  pw.Widget _buildHeader(TillSession session, String operatorName,
      String? companyName, String? companyAddress, String? companySiret) {
    return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(companyName ?? "Société",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (companyAddress != null && companyAddress.isNotEmpty)
                pw.Text(companyAddress,
                    style: const pw.TextStyle(fontSize: 10)),
              if (companySiret != null && companySiret.isNotEmpty)
                pw.Text("SIRET: $companySiret",
                    style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text("RAPPORT Z",
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text("Date: ${dateFormatter.format(session.openingTime)}"),
              pw.Text("Caissier: $operatorName"),
              pw.Text("Réf: ${session.id.substring(0, 8)}"),
            ],
          ),
        ]);
  }

  pw.Widget _buildSummarySection(double ht, double tva, double ttc) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildKpi("Total HT", ht),
          _buildKpi("Total TVA", tva),
          _buildKpi("TOTAL TTC", ttc, isBold: true),
        ],
      ),
    );
  }

  pw.Widget _buildKpi(String label, double value, {bool isBold = false}) {
    return pw.Column(children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      pw.Text(NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(value),
          style: pw.TextStyle(
              fontSize: 14,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    ]);
  }

  pw.Widget _buildVatTable(Map<String, double> vatBreakdown) {
    final headers = ['Taux', 'Montant TVA'];
    final data = vatBreakdown.entries
        .map((e) => [
      e.key,
      NumberFormat.currency(locale: 'fr_FR', symbol: '€')
          .format(e.value)
    ])
        .toList();
    return pw.Table.fromTextArray(
        headers: headers,
        data: data,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellAlignment: pw.Alignment.centerRight);
  }

  pw.Widget _buildPaymentTable(Map<String, double> payments) {
    final headers = ['Mode', 'Montant'];
    final data = payments.entries
        .map((e) => [
      e.key,
      NumberFormat.currency(locale: 'fr_FR', symbol: '€')
          .format(e.value)
    ])
        .toList();
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("Règlements:",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Table.fromTextArray(
              headers: headers,
              data: data,
              cellAlignment: pw.Alignment.centerRight),
        ]);
  }

  pw.Widget _buildFooter() {
    return pw.Column(children: [
      pw.Divider(),
      pw.Text("Document comptable généré informatiquement.",
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
    ]);
  }
}