import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- CORRECTION CRITIQUE : Import du bon modèle Transaction ---
// On pointe vers le dossier 'core' et non plus vers la racine 'lib/models.dart'
import '../../../../../core/models/models.dart';
import '../../../../../core/repository/repository.dart';

class SessionTransactionsDialog extends StatelessWidget {
  final List<Transaction> transactions;

  const SessionTransactionsDialog({super.key, required this.transactions});

  Icon _getPaymentIcon(Map<String, dynamic> methods) {
    if (methods.keys.length > 1) {
      return const Icon(Icons.splitscreen_outlined, color: Colors.blueGrey);
    }
    if (methods.containsKey('Cash')) {
      return const Icon(Icons.money, color: Colors.blueGrey);
    }
    if (methods.containsKey('Card')) {
      return const Icon(Icons.credit_card, color: Colors.blueGrey);
    }
    return const Icon(Icons.payment, color: Colors.blueGrey);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Transactions de la session (${transactions.length})"),
      content: SizedBox(
        width: 600,
        child: transactions.isEmpty
            ? const Center(
                child: Text("Aucune transaction pour cette session."))
            : ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final transaction = transactions[index];
                  final time = DateFormat('HH:mm')
                      .format(transaction.timestamp.toLocal());
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ExpansionTile(
                      leading: _getPaymentIcon(transaction.paymentMethods),
                      title: Text("Commande à $time"),
                      trailing: Text(
                        "${transaction.total.toStringAsFixed(2)} €",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      children: transaction.items.map((item) {
                        return ListTile(
                          dense: true,
                          title: Text(
                              item['name'] as String? ?? 'Article inconnu'),
                          trailing: Text(
                              '${(item['total'] as num? ?? 0.0).toStringAsFixed(2)} €'),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Fermer"),
        ),
      ],
    );
  }
}

class TransactionDetailDialog extends StatefulWidget {
  final Transaction transaction;

  const TransactionDetailDialog({super.key, required this.transaction});

  @override
  State<TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  bool _isReprinting = false;
  final _repository = FranchiseRepository();

  Future<void> _handleReprint(BuildContext context,
      {required bool isKitchen}) async {
    setState(() => _isReprinting = true);
    try {
      if (isKitchen) {
        await _repository.reprintKitchenTicket(widget.transaction.id);
      } else {
        await _repository.reprintReceipt(widget.transaction.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isKitchen
                ? "Ticket Cuisine envoyé !"
                : "Ticket Caisse envoyé !"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur d'impression : $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReprinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5E35B1); // Indigo/Violet pro
    final shortId = widget.transaction.id.substring(0, 6);

    // Gestion du type de commande (Sur place / Emporter)
    // Utilisation de la chaine de caractère brute pour éviter les soucis d'enum
    final orderTypeLabel = (widget.transaction.orderType == 'takeaway')
        ? 'À Emporter'
        : 'Sur Place';

    final paymentLabel =
        _getPaymentMethodLabel(widget.transaction.paymentMethods);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Détails Commande",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(thickness: 1.5, color: primaryColor),

            // INFO GÉNÉRALES
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.confirmation_number, "Ticket",
                        "#$shortId", Colors.black87),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                        Icons.access_time,
                        "Date",
                        DateFormat('dd/MM/yyyy HH:mm')
                            .format(widget.transaction.timestamp),
                        Colors.black87),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                        (widget.transaction.orderType == 'takeaway')
                            ? Icons.shopping_bag
                            : Icons.restaurant,
                        "Type",
                        orderTypeLabel,
                        Colors.black87),

                    const SizedBox(height: 20),
                    const Text("Articles",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryColor)),
                    const SizedBox(height: 10),

                    // LISTE DES ARTICLES
                    ...widget.transaction.items.map((item) {
                      final name = item['name'] ?? 'Inconnu';
                      final quantity = item['quantity'] ?? 1;
                      final totalItem =
                          (item['total'] as num?)?.toDouble() ?? 0.0;

                      // Récupération des options et ingrédients
                      final optionsGroups =
                          item['options'] as List<dynamic>? ?? [];
                      final removedIngredients =
                          item['removedIngredientNames'] as List<dynamic>? ??
                              [];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(quantity > 1 ? "${quantity}x $name" : name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text("${totalItem.toStringAsFixed(2)} €",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),

                            // Ingrédients retirés
                            if (removedIngredients.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                    "Sans: ${removedIngredients.join(', ')}",
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic)),
                              ),

                            // Options ajoutées
                            if (optionsGroups.isNotEmpty)
                              ...optionsGroups.expand((g) =>
                                  (g['items'] as List).map((opt) => Padding(
                                        padding:
                                            const EdgeInsets.only(left: 10),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text("• ${opt['name']}",
                                                style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 13)),
                                            if ((opt['supplementPrice'] ?? 0) >
                                                0)
                                              Text(
                                                  "+${opt['supplementPrice']} €",
                                                  style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontSize: 13)),
                                          ],
                                        ),
                                      ))),
                            const Divider(color: Color(0xFFEEEEEE)),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // TOTAUX
            _buildSummaryRow("Sous-total", widget.transaction.subTotal, false),
            if (widget.transaction.discountAmount > 0.01)
              _buildSummaryRow(
                  "Remise", -widget.transaction.discountAmount, false,
                  color: Colors.red),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOTAL PAYÉ",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryColor)),
                Text("${widget.transaction.total.toStringAsFixed(2)} €",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryColor)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payment, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text("Payé via $paymentLabel",
                    style: const TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.w600)),
              ],
            ),

            const Divider(thickness: 1.5, height: 30),

            // BOUTONS D'ACTION (RÉIMPRESSION)
            const Text("Actions Rapides",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 10),
            if (_isReprinting)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator()))
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () =>
                          _handleReprint(context, isKitchen: false),
                      icon: const Icon(Icons.receipt),
                      label: const Text("Ticket Caisse"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _handleReprint(context, isKitchen: true),
                      icon:
                          const Icon(Icons.soup_kitchen, color: Colors.orange),
                      label: const Text("Ticket Cuisine"),
                    ),
                  ),
                ],
              )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text("$label: ", style: const TextStyle(color: Colors.grey)),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double value, bool isBold,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: color ?? Colors.black54,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text("${value.toStringAsFixed(2)} €",
              style: TextStyle(
                  color: color ?? Colors.black87,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  String _getPaymentMethodLabel(Map<String, dynamic> methods) {
    if (methods.isEmpty) return 'Inconnu';
    return methods.entries.map((e) {
      final amount = (e.value as num).toDouble().toStringAsFixed(2);
      return '${e.key} ($amount €)';
    }).join(' + ');
  }
}
