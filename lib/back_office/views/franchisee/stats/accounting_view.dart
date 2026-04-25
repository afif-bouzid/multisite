import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/auth_provider.dart';
import '/models.dart';
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
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
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
              child: Text("Aucune donnée comptable sur cette période.",
                  style: TextStyle(color: Colors.grey, fontSize: 16)));
        }

        final transactions = snapshot.data!;

        double totalRevenue = 0;
        Map<String, double> methodTotals = {
          'CB Bornes': 0.0,
          'CB Comptoir': 0.0,
          'Espèces': 0.0,
          'Ticket Resto': 0.0,
        };

        for (var tx in transactions) {
          tx.paymentMethods.forEach((method, amount) {
            double val = (amount as num).toDouble();
            totalRevenue += val;

            if (method == 'Card_Kiosk') {
              methodTotals['CB Bornes'] = methodTotals['CB Bornes']! + val;
            } else if (method == 'Card_Counter') {
              methodTotals['CB Comptoir'] = methodTotals['CB Comptoir']! + val;
            } else if (method == 'Cash') {
              methodTotals['Espèces'] = methodTotals['Espèces']! + val;
            } else if (method == 'Ticket') {
              methodTotals['Ticket Resto'] = methodTotals['Ticket Resto']! + val;
            } else if (method == 'Card') {
              // LOGIQUE INFAILLIBLE
              bool isBorne = false;
              try { if ((tx as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
              try { if ((tx as dynamic).origin?.toString() == 'kiosk') isBorne = true; } catch (_) {}

              if (isBorne) {
                methodTotals['CB Bornes'] = methodTotals['CB Bornes']! + val;
              } else {
                methodTotals['CB Comptoir'] = methodTotals['CB Comptoir']! + val;
              }
            } else {
              methodTotals[method] = (methodTotals[method] ?? 0) + val;
            }
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Bilan Comptable Détaillé", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text("Période du ${DateFormat('dd/MM/yyyy').format(start)} au ${DateFormat('dd/MM/yyyy').format(end)}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final exportService = AccountingExportService();

                      // 1. On génère d'abord le texte du CSV
                      final csvData = exportService.generateCSV(transactions);

                      // 2. On demande au service de le partager/télécharger
                      await exportService.shareCsvFile(csvData);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text("Exporter CSV"),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                  )                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  _buildSummaryBox("CB Bornes", methodTotals['CB Bornes']!, Colors.teal, Icons.touch_app),
                  const SizedBox(width: 16),
                  _buildSummaryBox("CB Comptoir", methodTotals['CB Comptoir']!, Colors.indigo, Icons.point_of_sale),
                  const SizedBox(width: 16),
                  _buildSummaryBox("Espèces", methodTotals['Espèces']!, Colors.green, Icons.payments),
                  const SizedBox(width: 16),
                  _buildSummaryBox("Ticket Resto", methodTotals['Ticket Resto']!, Colors.orange, Icons.restaurant),
                ],
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("Détail par mode de paiement", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const Divider(height: 1),
                    DataTable(
                      columnSpacing: 40,
                      columns: const [
                        DataColumn(label: Text("Méthode", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Montant TTC", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Part (%)", style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: [
                        ...methodTotals.entries.where((e) => e.value > 0).map((e) {
                          final percent = totalRevenue > 0 ? (e.value / totalRevenue) * 100 : 0.0;
                          return DataRow(cells: [
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getIconForMethod(e.key), size: 18, color: _getColorForMethod(e.key)),
                                const SizedBox(width: 12),
                                Text(e.key),
                              ],
                            )),
                            DataCell(Text("${e.value.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataCell(Text("${percent.toStringAsFixed(1)} %")),
                          ]);
                        }),
                        DataRow(
                          color: WidgetStateProperty.all(Colors.grey.shade50),
                          cells: [
                            const DataCell(Text("TOTAL GLOBAL", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataCell(Text("${totalRevenue.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo))),
                            const DataCell(Text("100.0 %", style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryBox(String label, double value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text("${value.toStringAsFixed(2)} €", style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForMethod(String method) {
    switch (method) {
      case 'Espèces': return Icons.payments;
      case 'CB Bornes': return Icons.touch_app;
      case 'CB Comptoir': return Icons.point_of_sale;
      case 'Ticket Resto': return Icons.restaurant;
      default: return Icons.credit_card;
    }
  }

  Color _getColorForMethod(String method) {
    switch (method) {
      case 'Espèces': return Colors.green;
      case 'CB Bornes': return Colors.teal;
      case 'CB Comptoir': return Colors.indigo;
      case 'Ticket Resto': return Colors.orange;
      default: return Colors.blueGrey;
    }
  }
}