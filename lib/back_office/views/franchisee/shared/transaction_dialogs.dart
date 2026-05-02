import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../models.dart';
import '../../../../../core/services/printing_service.dart';
import '../../../../../core/services/local_config_service.dart';
import '../../../../../core/auth_provider.dart';

// --- UTILITAIRES DE DESIGN MIS À JOUR POUR LA VENTILATION ---

Color _getPaymentColor(String method, Transaction tx) {
  if (method == 'Cash') return Colors.green;
  if (method == 'Card_Kiosk') return Colors.teal;
  if (method == 'Card_Counter') return Colors.indigo;
  if (method == 'Ticket') return Colors.orange;

  // Logique de secours pour les clés génériques 'Card'
  if (method == 'Card') {
    bool isBorne = false;
    try { if ((tx as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    try { if ((tx as dynamic).origin?.toString() == 'kiosk') isBorne = true; } catch (_) {}
    return isBorne ? Colors.teal : Colors.indigo;
  }
  return Colors.blueGrey;
}

String _getPaymentLabel(String method, Transaction tx) {
  if (method == 'Cash') return 'Espèces';
  if (method == 'Card_Kiosk') return 'CB Borne';
  if (method == 'Card_Counter') return 'CB Comptoir';
  if (method == 'Ticket') return 'Ticket Resto';

  if (method == 'Card') {
    bool isBorne = false;
    try { if ((tx as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    try { if ((tx as dynamic).origin?.toString() == 'kiosk') isBorne = true; } catch (_) {}
    return isBorne ? 'CB Borne' : 'CB Comptoir';
  }
  return method;
}

IconData _getPaymentIconData(String method, Transaction tx) {
  if (method == 'Cash') return Icons.payments;
  if (method == 'Card_Kiosk') return Icons.touch_app;
  if (method == 'Card_Counter') return Icons.point_of_sale;
  if (method == 'Ticket') return Icons.restaurant;

  if (method == 'Card') {
    bool isBorne = false;
    try { if ((tx as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    try { if ((tx as dynamic).origin?.toString() == 'kiosk') isBorne = true; } catch (_) {}
    return isBorne ? Icons.touch_app : Icons.point_of_sale;
  }
  return Icons.credit_card;
}

Color _getPrimaryColor(Transaction tx) {
  final methods = tx.paymentMethods;
  if (methods.keys.length > 1) return Colors.blueGrey;
  if (methods.isNotEmpty) return _getPaymentColor(methods.keys.first, tx);
  return Colors.grey;
}

IconData _getPrimaryIcon(Transaction tx) {
  final methods = tx.paymentMethods;
  if (methods.keys.length > 1) return Icons.splitscreen;
  if (methods.isNotEmpty) return _getPaymentIconData(methods.keys.first, tx);
  return Icons.payment;
}

// Widget partagé pour afficher les pastilles de paiement ventilées
Widget _buildPaymentChips(Transaction tx, {bool showAmount = false}) {
  final methods = tx.paymentMethods;
  if (methods.isEmpty) {
    return const Text("Inconnu", style: TextStyle(color: Colors.grey, fontSize: 12));
  }

  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: methods.entries.map((e) {
      final method = e.key;
      final amount = (e.value as num).toDouble();

      final color = _getPaymentColor(method, tx);
      final label = _getPaymentLabel(method, tx);
      final icon = _getPaymentIconData(method, tx);

      return Container(
        padding: EdgeInsets.symmetric(horizontal: showAmount ? 10 : 8, vertical: showAmount ? 6 : 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: showAmount ? 16 : 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: showAmount ? 13 : 11, color: color, fontWeight: FontWeight.bold)),
            if (showAmount) ...[
              const SizedBox(width: 6),
              Text("${amount.toStringAsFixed(2)} €", style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w900)),
            ]
          ],
        ),
      );
    }).toList(),
  );
}

// ------------------------------------

class SessionTransactionsDialog extends StatelessWidget {
  final List<Transaction> transactions;
  const SessionTransactionsDialog({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Transactions de la session (${transactions.length})"),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        width: MediaQuery.of(context).size.width * 0.9,
        child: transactions.isEmpty
            ? const Center(child: Text("Aucune transaction."))
            : ListView.builder(
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            final time = DateFormat('HH:mm').format(transaction.timestamp.toLocal());
            final double totalVal = (transaction as dynamic).total ?? (transaction as dynamic).totalAmount ?? 0.0;
            final String idShort = transaction.id.length > 4 ? transaction.id.substring(0, 4) : transaction.id;

            final primaryColor = _getPrimaryColor(transaction);
            final primaryIcon = _getPrimaryIcon(transaction);

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200)
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: primaryColor.withValues(alpha: 0.15),
                  child: Icon(primaryIcon, color: primaryColor, size: 20),
                ),
                title: Text("Commande #$idShort à $time", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: _buildPaymentChips(transaction, showAmount: false),
                ),
                trailing: Text(
                  "${totalVal.toStringAsFixed(2)} €",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                children: transaction.items.map((item) {
                  final name = item['name'];
                  final price = (item['price'] ?? 0.0);
                  final qty = (item['quantity'] ?? 1);
                  final double itemTotal = (double.tryParse(price.toString()) ?? 0.0) * (int.tryParse(qty.toString()) ?? 1);

                  return ListTile(
                    dense: true,
                    title: Text("${qty}x $name"),
                    trailing: Text('${itemTotal.toStringAsFixed(2)} €'),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer")),
      ],
    );
  }
}

class TransactionDetailDialog extends StatefulWidget {
  final Transaction transaction;
  const TransactionDetailDialog({super.key, required this.transaction});
  @override
  State<TransactionDetailDialog> createState() => _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  bool _isReprinting = false;

  Map<String, dynamic> _safeItemToMap(dynamic item) {
    if (item is Map) return Map<String, dynamic>.from(item);
    try {
      return (item as dynamic).toMap();
    } catch (_) {
      return {
        'name': _tryGetProperty(item, 'name', 'Article inconnu'),
        'quantity': _tryGetProperty(item, 'quantity', 1),
        'price': _tryGetProperty(item, 'price', 0.0),
        'options': _tryGetProperty(item, 'selectedOptions', []),
        'removedIngredientNames': _tryGetProperty(item, 'removedIngredientNames', []),
      };
    }
  }

  dynamic _tryGetProperty(dynamic item, String propertyName, dynamic defaultValue) {
    try {
      switch (propertyName) {
        case 'name': return item.name;
        case 'quantity': return item.quantity;
        case 'price': return item.price;
        case 'selectedOptions': return item.selectedOptions;
        case 'removedIngredientNames': return item.removedIngredientNames;
        default: return defaultValue;
      }
    } catch (_) {
      return defaultValue;
    }
  }

  Future<void> _handleReprint(BuildContext context, {required bool isKitchen}) async {
    setState(() => _isReprinting = true);
    try {
      final localConfig = await LocalConfigService().getPrinterConfig();
      if (isKitchen) {
        final String safeId = widget.transaction.id.length >= 4 ? widget.transaction.id.substring(0, 4) : widget.transaction.id;
        final List<Map<String, dynamic>> cleanItems = widget.transaction.items.map((item) => _safeItemToMap(item)).toList();

        await PrintingService().printKitchenTicketSafe(
          printerConfig: localConfig,
          itemsToPrint: cleanItems,
          identifier: safeId,
          isReprint: true,
          orderType: (widget.transaction as dynamic).orderType.toString(),
        );
      } else {
        final receiptConfig = await LocalConfigService().getReceiptConfig();
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        dynamic user;
        try { user = (authProvider as dynamic).franchiseUser; } catch (_) {}

        Map<String, dynamic> transactionMap = {};
        try {
          transactionMap = (widget.transaction as dynamic).toMap();
        } catch (_) {
          transactionMap = {
            'id': widget.transaction.id,
            'total': (widget.transaction as dynamic).total ?? 0.0,
            'paymentMethods': widget.transaction.paymentMethods,
            'timestamp': widget.transaction.timestamp.toIso8601String(),
            'orderType': (widget.transaction as dynamic).orderType,
            'items': widget.transaction.items.map((item) => _safeItemToMap(item)).toList(),
          };
        }
        await PrintingService().printReceipt(
          printerConfig: localConfig,
          transaction: transactionMap,
          franchisee: user?.toMap() ?? {},
          receiptConfig: receiptConfig,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impression lancée !"), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isReprinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5E35B1);
    final shortId = widget.transaction.id.length > 6 ? widget.transaction.id.substring(0, 6) : widget.transaction.id;
    final bool isTakeaway = (widget.transaction as dynamic).orderType.toString().toLowerCase().contains('takeaway');
    final orderTypeLabel = isTakeaway ? 'À Emporter' : 'Sur Place';
    final double totalVal = (widget.transaction as dynamic).total ?? (widget.transaction as dynamic).totalAmount ?? 0.0;
    final double subTotalVal = (widget.transaction as dynamic).subTotal ?? (totalVal / 1.1);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Détails Commande", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryColor)),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(thickness: 1.5, color: primaryColor),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.confirmation_number, "Ticket", "#$shortId", Colors.black87),
                    _buildInfoRow(Icons.access_time, "Date", DateFormat('dd/MM/yyyy HH:mm').format(widget.transaction.timestamp.toLocal()), Colors.black87),
                    _buildInfoRow(isTakeaway ? Icons.shopping_bag : Icons.restaurant, "Type", orderTypeLabel, Colors.black87),

                    const SizedBox(height: 20),
                    const Text("Articles", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
                    const SizedBox(height: 10),

                    ...widget.transaction.items.map((item) {
                      final name = item['name'];
                      final quantity = (item['quantity'] ?? 1);
                      final price = (item['price'] ?? 0.0);
                      final double itemTotal = (double.tryParse(price.toString()) ?? 0.0) * (int.tryParse(quantity.toString()) ?? 1);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${quantity}x $name", style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text("${itemTotal.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
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
            _buildSummaryRow("Sous-total", subTotalVal, false),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOTAL PAYÉ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primaryColor)),
                Text("${totalVal.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primaryColor)),
              ],
            ),
            const SizedBox(height: 16),
            const Text("Répartition du paiement :", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // --- UTILISATION DE LA NOUVELLE FONCTION VENTILÉE ---
            _buildPaymentChips(widget.transaction, showAmount: true),

            const Divider(thickness: 1.5, height: 30),
            if (_isReprinting)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
                      onPressed: () => _handleReprint(context, isKitchen: false),
                      icon: const Icon(Icons.receipt),
                      label: const Text("Ticket Caisse"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleReprint(context, isKitchen: true),
                      icon: const Icon(Icons.soup_kitchen, color: Colors.orange),
                      label: const Text("Cuisine"),
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
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double value, bool isBold, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color ?? Colors.black54, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text("${value.toStringAsFixed(2)} €", style: TextStyle(color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}