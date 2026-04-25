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

  /// Génère le contenu CSV avec une ventilation détaillée des paiements
  String generateCSV(List<dynamic> transactions) {
    List<List<dynamic>> rows = [];

    // En-tête avec colonnes ventilées
    rows.add([
      "Date",
      "Heure",
      "ID Transaction",
      "Type",
      "Total TTC",
      "Espèces",
      "CB Borne",
      "CB Comptoir",
      "Ticket Resto",
      "Autres"
    ]);

    for (var tx in transactions) {
      double cash = 0, cbKiosk = 0, cbCounter = 0, ticket = 0, others = 0;

      // Ventilation identique au reste du système
      (tx.paymentMethods as Map<String, dynamic>).forEach((method, amount) {
        double val = (amount as num).toDouble();

        if (method == 'Cash') {
          cash += val;
        } else if (method == 'Ticket') {
          ticket += val;
        } else if (method == 'Card_Kiosk') {
          cbKiosk += val;
        } else if (method == 'Card_Counter') {
          cbCounter += val;
        } else if (method == 'Card') {
          // Détection automatique de la borne pour les anciens tickets
          bool isBorne = false;
          try { if (tx.source?.toString() == 'borne') isBorne = true; } catch (_) {}
          try { if (tx.origin?.toString() == 'kiosk') isBorne = true; } catch (_) {}

          if (isBorne) cbKiosk += val; else cbCounter += val;
        } else {
          others += val;
        }
      });

      rows.add([
        DateFormat('dd/MM/yyyy').format(tx.timestamp),
        DateFormat('HH:mm').format(tx.timestamp),
        tx.id,
        tx.orderType,
        tx.total,
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