import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// --- IMPORTS ---
// Vérifiez que ces chemins correspondent bien à votre structure
import '../../../../../core/repository/repository.dart';
import '../../../../models.dart';
import '../../../../../core/services/printing_service.dart';
import '../../../../../core/services/local_config_service.dart';
import '../../../../../core/auth_provider.dart';

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

            // Sécurisation : total ou totalAmount
            final double totalVal = (transaction as dynamic).total ??
                (transaction as dynamic).totalAmount ?? 0.0;

            // Affichage ID court
            final String idShort = transaction.id.length > 4
                ? transaction.id.substring(0, 4)
                : transaction.id;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                leading: _getPaymentIcon(transaction.paymentMethods),
                title: Text("Commande #$idShort à $time"),
                trailing: Text(
                  "${totalVal.toStringAsFixed(2)} €",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                children: transaction.items.map((item) {
                  final name = item is Map ? item['name'] : (item as dynamic).name;
                  final price = item is Map ? (item['price'] ?? 0.0) : (item as dynamic).price;
                  final qty = item is Map ? (item['quantity'] ?? 1) : (item as dynamic).quantity;
                  final double itemTotal = (double.parse(price.toString()) * int.parse(qty.toString()));

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

  /// Fonction utilitaire pour convertir n'importe quel Item (Map ou Objet) en Map propre
  /// Cela évite les erreurs de type "dynamic" dans le service d'impression
  Map<String, dynamic> _safeItemToMap(dynamic item) {
    if (item is Map) {
      return Map<String, dynamic>.from(item);
    }
    // Si c'est un objet (CartItem, Product, etc.), on essaie de le convertir
    try {
      return (item as dynamic).toMap();
    } catch (_) {
      // Fallback manuel si .toMap() n'existe pas
      return {
        'name': (item as dynamic).name,
        'quantity': (item as dynamic).quantity,
        'price': (item as dynamic).price,
        'options': (item as dynamic).selectedOptions, // Ou 'options'
        'removedIngredientNames': (item as dynamic).removedIngredientNames,
      };
    }
  }

  Future<void> _handleReprint(BuildContext context,
      {required bool isKitchen}) async {
    setState(() => _isReprinting = true);
    try {
      final localConfig = await LocalConfigService().getPrinterConfig();

      if (isKitchen) {
        // --- IMPRESSION TICKET CUISINE ---

        // 1. ID Sécurisé (4 caractères)
        final String safeId = widget.transaction.id.length >= 4
            ? widget.transaction.id.substring(0, 4)
            : widget.transaction.id;

        // 2. Conversion PROPRE des articles en Liste de Maps
        // C'est souvent ici que ça bloque : on force la conversion pour être sûr
        final List<Map<String, dynamic>> cleanItems = widget.transaction.items
            .map((item) => _safeItemToMap(item))
            .toList();

        debugPrint("Envoi Cuisine: ${cleanItems.length} articles (ID: $safeId)");

        if (cleanItems.isEmpty) throw Exception("Liste articles vide");

        await PrintingService().printKitchenTicketSafe(
          printerConfig: localConfig,
          itemsToPrint: cleanItems, // On envoie la liste nettoyée
          identifier: safeId,
          isReprint: true,
        );
      } else {
        // --- IMPRESSION TICKET CAISSE ---
        final receiptConfig = await LocalConfigService().getReceiptConfig();

        // A. Récupération Utilisateur (Provider) robuste
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        dynamic user;
        try { user = (authProvider as dynamic).franchiseUser; } catch(_) {}
        if (user == null) try { user = (authProvider as dynamic).user; } catch(_) {}
        if (user == null) try { user = (authProvider as dynamic).currentUser; } catch(_) {}
        if (user == null) try { user = (authProvider as dynamic).franchisee; } catch(_) {}

        // B. Préparation Transaction (Map)
        Map<String, dynamic> transactionMap = {};
        try {
          transactionMap = (widget.transaction as dynamic).toMap();
        } catch (_) {
          // Fallback construction manuelle si toMap manque
          transactionMap = {
            'id': widget.transaction.id,
            'total': (widget.transaction as dynamic).total ?? 0.0,
            'paymentMethods': widget.transaction.paymentMethods,
            'timestamp': widget.transaction.timestamp.toIso8601String(),
            'orderType': (widget.transaction as dynamic).orderType,
            // On utilise aussi les items nettoyés pour la caisse
            'items': widget.transaction.items.map((item) => _safeItemToMap(item)).toList(),
          };
        }

        // C. FIX ID LENGTH : Le service de caisse coupe à 8 char, on s'assure qu'on les a
        if (transactionMap['id'] != null && transactionMap['id'].toString().length < 8) {
          transactionMap['id'] = transactionMap['id'].toString().padRight(8, ' ');
        }

        debugPrint("Envoi Caisse: ID ${transactionMap['id']}");

        await PrintingService().printReceipt(
          printerConfig: localConfig,
          transaction: transactionMap,
          franchisee: user ?? {},
          receiptConfig: receiptConfig,
        );
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
      debugPrint("Erreur impression: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur : ${e.toString().replaceAll('Exception:', '')}"),
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
    const primaryColor = Color(0xFF5E35B1);
    final shortId = widget.transaction.id.length > 6
        ? widget.transaction.id.substring(0, 6)
        : widget.transaction.id;

    final bool isTakeaway = (widget.transaction as dynamic).orderType.toString().toLowerCase().contains('takeaway');
    final orderTypeLabel = isTakeaway ? 'À Emporter' : 'Sur Place';

    final paymentLabel = _getPaymentMethodLabel(widget.transaction.paymentMethods);

    final double totalVal = (widget.transaction as dynamic).total ??
        (widget.transaction as dynamic).totalAmount ?? 0.0;

    final double subTotalVal = (widget.transaction as dynamic).subTotal ?? (totalVal / 1.1);

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

            // CONTENU SCROLLABLE
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
                            .format(widget.transaction.timestamp.toLocal()),
                        Colors.black87),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                        isTakeaway ? Icons.shopping_bag : Icons.restaurant,
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
                      final name = item is Map ? item['name'] : (item as dynamic).name;
                      final quantity = item is Map ? (item['quantity'] ?? 1) : (item as dynamic).quantity;
                      final price = item is Map ? (item['price'] ?? 0.0) : (item as dynamic).price;
                      final double itemTotal = (double.parse(price.toString()) * int.parse(quantity.toString()));

                      List<dynamic> optionsGroups = [];
                      List<dynamic> removedIngredients = [];

                      if (item is Map) {
                        optionsGroups = item['options'] as List<dynamic>? ?? [];
                        removedIngredients = item['removedIngredientNames'] as List<dynamic>? ?? [];
                      } else {
                        try { optionsGroups = (item as dynamic).selectedOptions ?? []; } catch (_) {}
                        try { removedIngredients = (item as dynamic).removedIngredientNames ?? []; } catch (_) {}
                      }

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
                                Text("${itemTotal.toStringAsFixed(2)} €",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
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
                            if (optionsGroups.isNotEmpty)
                              ...optionsGroups.expand((g) {
                                if (g is! Map) return [Container()];
                                final items = g['items'] as List?;
                                if (items == null) return [Container()];
                                return items.map((opt) => Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("• ${opt['name']}",
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                      if ((opt['supplementPrice'] ?? 0) > 0)
                                        Text("+${opt['supplementPrice']} €",
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                    ],
                                  ),
                                ));
                              }),
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
            _buildSummaryRow("Sous-total", subTotalVal, false),

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOTAL PAYÉ",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryColor)),
                Text("${totalVal.toStringAsFixed(2)} €",
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

            // BOUTONS D'ACTION
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