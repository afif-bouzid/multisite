import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../auth_provider.dart';
import '../../../../core/models/models.dart';
import '../../../../core/repository/repository.dart';
import '../../../../core/services/accounting_export_service.dart';

class AccountingView extends StatelessWidget {
  final String franchiseeId;
  final DateTime? startDate;
  final DateTime? endDate;

  const AccountingView({
    super.key,
    required this.franchiseeId,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    final start =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();
    final repository = FranchiseRepository();

    return StreamBuilder<List<Transaction>>(
      stream: repository.getTransactionsInDateRange(
        franchiseeId,
        startDate: start,
        endDate: end,
        limit: 5000,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
              child: Text("Aucune donnée comptable sur cette période."));
        }

        return _buildAccountingReport(context, snapshot.data!);
      },
    );
  }

  Widget _buildAccountingReport(
      BuildContext context, List<Transaction> transactions) {
    // --- 1. CALCULS COMPTABLES ---
    double totalTTC = 0;
    double totalHT = 0;

    // Map: Taux TVA -> { 'baseHT': 0.0, 'amountTVA': 0.0 }
    Map<double, Map<String, double>> vatBreakdown = {};

    // Map: Mode Paiement -> Montant
    Map<String, double> paymentBreakdown = {};

    for (var t in transactions) {
      totalTTC += t.total;

      // Ventilation Paiements
      t.paymentMethods.forEach((method, amount) {
        paymentBreakdown[method] =
            (paymentBreakdown[method] ?? 0) + (amount as num).toDouble();
      });

      // Ventilation TVA (Ligne par ligne pour précision)
      for (var item in t.items) {
        // Prix TTC de la ligne (Base + Options) * Quantité
        // Note: Dans Transaction, 'total' est le prix total de la ligne TTC
        double lineTotalTTC = (item['total'] as num).toDouble();
        double vatRate = (item['vatRate'] as num).toDouble();

        // Formule: HT = TTC / (1 + Taux/100)
        double lineTotalHT = lineTotalTTC / (1 + (vatRate / 100));
        double lineVatAmount = lineTotalTTC - lineTotalHT;

        totalHT += lineTotalHT;

        vatBreakdown.putIfAbsent(
            vatRate, () => {'baseHT': 0.0, 'amountTVA': 0.0});
        vatBreakdown[vatRate]!['baseHT'] =
            vatBreakdown[vatRate]!['baseHT']! + lineTotalHT;
        vatBreakdown[vatRate]!['amountTVA'] =
            vatBreakdown[vatRate]!['amountTVA']! + lineVatAmount;
      }
    }

    final sortedRates = vatBreakdown.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate, size: 32, color: Colors.blueGrey),
              const SizedBox(width: 12),
              Text("Rapport Comptable",
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text("Exporter (Excel/CSV)"),
                onPressed: () async {
                  final exportService = AccountingExportService();

                  // Préparation des données TVA pour le PDF
                  Map<String, double> pdfVatMap = {};
                  vatBreakdown.forEach((rate, data) {
                    pdfVatMap["${rate.toStringAsFixed(1)}%"] =
                        (data['amountTVA'] as num).toDouble();
                  });

                  // Récupération du nom de l'opérateur connecté
                  String operatorName = "Utilisateur";
                  try {
                    final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                    operatorName =
                        authProvider.franchiseUser?.companyName ?? "Utilisateur";
                  } catch (e) {
                    /* on ignore */
                  }

                  // --- MODIFICATION : Récupération des infos société depuis 'users' ---
                  String cName = "Société Inconnue";
                  String cAddress = "";
                  String cSiret = "";

                  try {
                    // On cible la collection 'users' où sont vos données franchisé
                    final docSnap = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(franchiseeId)
                        .get();

                    if (docSnap.exists) {
                      final data = docSnap.data() as Map<String, dynamic>;

                      // Récupération souple des champs (gère différents noms de clés possibles)
                      cName = data['companyName'] ??
                          data['name'] ??
                          data['societe'] ??
                          data['enseigne'] ??
                          operatorName;

                      cSiret = data['siret'] ??
                          data['siren'] ??
                          data['tvaIntra'] ??
                          "SIRET non renseigné";

                      // Construction de l'adresse complète
                      String rue = data['address'] ?? data['rue'] ?? data['street'] ?? data['adresse'] ?? '';
                      String cp = data['zipCode'] ?? data['cp'] ?? data['codePostal'] ?? '';
                      String ville = data['city'] ?? data['ville'] ?? '';

                      List<String> addressParts = [rue, cp, ville];
                      cAddress = addressParts.where((s) => s.isNotEmpty).join(" ");
                    }
                  } catch (e) {
                    debugPrint("Erreur récupération infos franchisé: $e");
                  }

                  // Affichage du choix du format
                  await showModalBottomSheet(
                    context: context,
                    builder: (ctx) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                          title: const Text('Générer le Z de Caisse (PDF)'),
                          subtitle: Text('Société : $cName'),
                          onTap: () async {
                            Navigator.pop(ctx);
                            // Création d'une session fictive pour l'entête du PDF global
                            final dummySession = TillSession(
                              id: "Export_${DateFormat('yyyyMMdd').format(DateTime.now())}",
                              franchiseeId: franchiseeId,
                              openingTime: startDate ?? DateTime.now(),
                              initialCash: 0.0,
                              isClosed: true,
                              closingTime: endDate ?? DateTime.now(),
                              finalCash: 0.0,
                            );

                            await exportService.generateAccountingPdf(
                              dummySession,
                              transactions,
                              pdfVatMap,
                              operatorName,
                              companyName: cName,      // Info récupérée injectée ici
                              companyAddress: cAddress, // Info récupérée injectée ici
                              companySiret: cSiret,     // Info récupérée injectée ici
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.table_chart, color: Colors.green),
                          title: const Text('Fichier Excel (CSV)'),
                          subtitle: const Text("Compatible Excel, Numbers, Google Sheets"),
                          onTap: () async {
                            Navigator.pop(ctx);

                            // 1. Générer les données brutes des transactions
                            final rawCsvData = exportService.generateCSV(transactions);

                            // 2. Créer l'en-tête personnalisé pour l'Excel (NOUVEAU)
                            final String headerInfo =
                                "Rapport Comptable;;;\n"
                                "Société:;$cName;;\n"
                                "Adresse:;$cAddress;;\n"
                                "SIRET:;$cSiret;;\n"
                                "Période:;${startDate != null ? DateFormat('dd/MM/yyyy').format(startDate!) : 'Début'} au ${endDate != null ? DateFormat('dd/MM/yyyy').format(endDate!) : 'Fin'};\n"
                                "Date export:;${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())};;\n"
                                "\n"; // Saut de ligne avant le tableau de données

                            // 3. Concaténer l'en-tête et les données
                            final fullCsvContent = headerInfo + rawCsvData;

                            // 4. Partager le fichier final
                            await exportService.shareCsvFile(fullCsvContent);
                          },
                        ),
                      ],
                    ),
                  );
                },
              )
            ],
          ),
          const SizedBox(height: 24),

          // --- SYNTHÈSE GLOBALE ---
          Row(
            children: [
              _buildSummaryBox("Chiffre d'Affaires TTC", totalTTC, Colors.blue),
              const SizedBox(width: 16),
              _buildSummaryBox("Total HT", totalHT, Colors.indigo),
              const SizedBox(width: 16),
              _buildSummaryBox(
                  "Total TVA Collectée", totalTTC - totalHT, Colors.orange),
            ],
          ),

          const SizedBox(height: 32),

          // --- TABLEAU DE TVA ---
          const Text("Ventilation TVA",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300)),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
              columns: const [
                DataColumn(
                    label: Text("Taux TVA",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text("Base HT",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text("Montant TVA",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text("Total TTC",
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: sortedRates.map((rate) {
                final data = vatBreakdown[rate]!;
                final base = data['baseHT']!;
                final vat = data['amountTVA']!;
                return DataRow(cells: [
                  DataCell(Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text("${rate.toStringAsFixed(1)} %",
                        style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold)),
                  )),
                  DataCell(Text("${base.toStringAsFixed(2)} €")),
                  DataCell(Text("${vat.toStringAsFixed(2)} €")),
                  DataCell(Text("${(base + vat).toStringAsFixed(2)} €",
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                ]);
              }).toList(),
            ),
          ),

          const SizedBox(height: 32),

          // --- TABLEAU ENCAISSEMENTS ---
          const Text("Détail des Encaissements",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300)),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
              columns: const [
                DataColumn(
                    label: Text("Mode de Paiement",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text("Montant",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text("Part (%)",
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: paymentBreakdown.entries.map((entry) {
                final percent =
                    totalTTC > 0 ? (entry.value / totalTTC * 100) : 0.0;
                return DataRow(cells: [
                  DataCell(Row(
                    children: [
                      Icon(_getIconForMethod(entry.key),
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(entry.key),
                    ],
                  )),
                  DataCell(Text("${entry.value.toStringAsFixed(2)} €",
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text("${percent.toStringAsFixed(1)} %")),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBox(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text("${value.toStringAsFixed(2)} €",
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  IconData _getIconForMethod(String method) {
    switch (method) {
      case 'Cash':
        return Icons.money;
      case 'Card':
        return Icons.credit_card;
      case 'Ticket':
        return Icons.receipt;
      default:
        return Icons.payment;
    }
  }
}
