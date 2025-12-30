import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../core/models/models.dart';
import '../../core/repository/repository.dart';
import '../../core/services/printing_service.dart';

class SessionDetailsView extends StatefulWidget {
  final TillSession session;

  const SessionDetailsView({super.key, required this.session});

  @override
  State<SessionDetailsView> createState() => _SessionDetailsViewState();
}

class _SessionDetailsViewState extends State<SessionDetailsView> {
  final FranchiseRepository _repository = FranchiseRepository();
  bool _isPrinting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Détail Historique", style: TextStyle(fontSize: 16)),
            Text(
              DateFormat('dd/MM/yyyy HH:mm').format(widget.session.openingTime),
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        // ✅ LE BOUTON EST ICI (EN HAUT À DROITE)
        actions: [
          if (_isPrinting)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: "Réimprimer le Ticket Z",
              onPressed: _handlePrintZ,
            ),
        ],
      ),
      // Le reste du corps reste identique...
      body: StreamBuilder<List<Transaction>>(
        stream: _repository.getSessionTransactions(widget.session.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Aucune transaction."));
          }

          final transactions = snapshot.data!;
          double totalSales = 0;
          for (var t in transactions) totalSales += t.total;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryCard(transactions.length, totalSales),
              const SizedBox(height: 24),
              const Text("Détail des tickets",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...transactions
                  .map((tx) => Card(
                        elevation: 0,
                        color: Colors.grey.shade50,
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          dense: true,
                          title: Text(
                              "Ticket ${tx.id.substring(0, 4).toUpperCase()}"), // ID court
                          trailing: Text("${tx.total.toStringAsFixed(2)} €"),
                        ),
                      ))
                  .toList()
            ],
          );
        },
      ),
    );
  }

  // ... (Garder les méthodes _buildSummaryCard et _handlePrintZ comme avant)

  Widget _buildSummaryCard(int count, double total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade700,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("TOTAL", style: TextStyle(color: Colors.white70)),
              Text("${total.toStringAsFixed(2)} €",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          Text("$count tickets", style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Future<void> _handlePrintZ() async {
    setState(() => _isPrinting = true);
    try {
      // Récupération des services (comme avant)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final printingService = PrintingService();

      final printerConfig = await _repository
          .getPrinterConfigStream(widget.session.franchiseeId)
          .first;

      final transactions =
          await _repository.getSessionTransactions(widget.session.id).first;

      await printingService.printZTicket(
        printerConfig: printerConfig,
        session: widget.session,
        transactions: transactions,
        declaredCash: widget.session.finalCash ?? 0.0,
        isManager: authProvider.franchiseUser?.role == 'franchisee',
        userName: authProvider.franchiseUser?.companyName ?? "Utilisateur",
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Impression lancée !")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }
}
