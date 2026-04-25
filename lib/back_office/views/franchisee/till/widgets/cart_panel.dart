import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../../core/cart_provider.dart';
import '/models.dart';
import '../../../../../core/repository/repository.dart';
import '../../../../../core/services/printing_service.dart';
import '../../../../../core/services/local_config_service.dart';
import '../../franchisee_stats_view.dart';
import '../../shared/payment_dialogs.dart';
import '../pos_dialogs.dart';
import 'product_view_content.dart';
class CartPanel extends StatefulWidget {
  final PosData posData;
  final String franchiseeId;
  final String franchisorId;
  final TillSession activeSession;
  final bool isTablet;
  final Function(String, bool) onStockChanged;
  const CartPanel({
    super.key,
    required this.posData,
    required this.franchiseeId,
    required this.franchisorId,
    required this.activeSession,
    required this.isTablet,
    required this.onStockChanged,
  });
  @override
  State<CartPanel> createState() => _CartPanelState();
}
class _CartPanelState extends State<CartPanel> with SingleTickerProviderStateMixin {
  final TextEditingController _identifierController = TextEditingController();
  bool _isProcessing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cart = context.read<CartProvider>();
        _identifierController.text = cart.orderIdentifier ?? '';
        _updateVat();
      }
    });
  }
  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }
  void _toggleOrderType(Set<OrderType> newSelection) {
    context.read<CartProvider>().setOrderType(newSelection.first);
    _updateVat();
  }
  void _updateVat() {
    final cart = context.read<CartProvider>();
    cart.updateVatRates(orderType: cart.orderType, settings: widget.posData.menuSettings);
  }
  Future<void> _showPaidOrdersHistory(BuildContext context, String franchiseeId) async {
    showDialog(
        context: context,
        builder: (_) => PaidOrdersHistoryDialog(franchiseeId: franchiseeId));
  }
  Future<String?> _showIdentifierDialog() {
    final cart = context.read<CartProvider>();
    String currentInput = cart.orderIdentifier ?? "";
    bool showNumpad = false;
    return showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setStateDialog) {
          final size = MediaQuery.of(context).size;
          return AlertDialog(
            contentPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Identification Client / Table",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 26)),
                IconButton(
                  iconSize: 40,
                  onPressed: () => setStateDialog(() => showNumpad = !showNumpad),
                  icon: Icon(showNumpad ? Icons.keyboard : Icons.dialpad, color: Colors.blue),
                )
              ],
            ),
            content: SizedBox(
              width: size.width * 0.9,
              height: size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue.shade300, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      currentInput.isEmpty ? "Saisir le nom..." : currentInput,
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: currentInput.isEmpty ? Colors.blue.withOpacity(0.3) : Colors.blue.shade900),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: showNumpad
                        ? _buildLargeNumpad(
                      onNumber: (n) => setStateDialog(() => currentInput += n),
                      onBackspace: () => setStateDialog(() {
                        if (currentInput.isNotEmpty) {
                          currentInput = currentInput.substring(0, currentInput.length - 1);
                        }
                      }),
                      onClear: () => setStateDialog(() => currentInput = ""),
                    )
                        : _buildComfortableAzerty(
                      onInput: (char) => setStateDialog(() => currentInput += char),
                      onBackspace: () => setStateDialog(() {
                        if (currentInput.isNotEmpty) {
                          currentInput = currentInput.substring(0, currentInput.length - 1);
                        }
                      }),
                      onSpace: () => setStateDialog(() => currentInput += " "),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 10),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ANNULER", style: TextStyle(fontSize: 20, color: Colors.red)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 10),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                  ),
                  onPressed: () {
                    if (currentInput.trim().isNotEmpty) {
                      Navigator.pop(context, currentInput.trim());
                    }
                  },
                  child: const Text("VALIDER", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        }));
  }
  Widget _buildComfortableAzerty({
    required Function(String) onInput,
    required VoidCallback onBackspace,
    required VoidCallback onSpace,
  }) {
    final List<List<String>> rows = [
      ['A', 'Z', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
      ['Q', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M'],
      ['W', 'X', 'C', 'V', 'B', 'N', ',', '.', '!', '?'],
    ];
    return Column(
      children: [
        ...rows.map((row) => Expanded(
          child: Row(
            children: row.map((char) => Expanded(
              child: _keyboardKey(char, () => onInput(char)),
            )).toList(),
          ),
        )),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _keyboardKey("EFFACER", onBackspace, color: Colors.orange.shade100, icon: Icons.backspace),
              ),
              Expanded(
                flex: 5,
                child: _keyboardKey("ESPACE", onSpace, color: Colors.grey.shade200),
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _keyboardKey(String label, VoidCallback onTap, {Color? color, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Material(
        color: color ?? Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: icon != null
                ? Icon(icon, size: 30)
                : Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
  Widget _buildLargeNumpad({
    required Function(String) onNumber,
    required VoidCallback onBackspace,
    required VoidCallback onClear,
  }) {
    return Column(
      children: [
        Expanded(child: Row(children: [1, 2, 3].map((n) => Expanded(child: _keyboardKey("$n", () => onNumber("$n")))).toList())),
        Expanded(child: Row(children: [4, 5, 6].map((n) => Expanded(child: _keyboardKey("$n", () => onNumber("$n")))).toList())),
        Expanded(child: Row(children: [7, 8, 9].map((n) => Expanded(child: _keyboardKey("$n", () => onNumber("$n")))).toList())),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _keyboardKey("C", onClear, color: Colors.red.shade50)),
              Expanded(child: _keyboardKey("0", () => onNumber("0"))),
              Expanded(child: _keyboardKey("⌫", onBackspace, color: Colors.orange.shade50)),
            ],
          ),
        ),
      ],
    );
  }
  void _showDiscountDialog(CartProvider cart) {
    String currentInput = "";
    bool isPercentage = cart.isDiscountPercentage;
    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setStateDialog) => AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              title: const Text("Appliquer une remise"),
              content: SizedBox(
                width: 350,
                height: 400,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.blue, width: 2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text(currentInput.isEmpty ? "0" : currentInput,
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.right)),
                          const SizedBox(width: 12),
                          ToggleButtons(
                            constraints: const BoxConstraints(minWidth: 45, minHeight: 45),
                            isSelected: [!isPercentage, isPercentage],
                            borderRadius: BorderRadius.circular(8),
                            onPressed: (index) => setStateDialog(() => isPercentage = index == 1),
                            children: const [
                              Text("€", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text("%", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Numpad(
                        onNumber: (num) {
                          if (num == '.' && currentInput.contains('.')) return;
                          setStateDialog(() => currentInput += num);
                        },
                        onBackspace: () => setStateDialog(() {
                          if (currentInput.isNotEmpty) {
                            currentInput = currentInput.substring(0, currentInput.length - 1);
                          }
                        }),
                        onClear: () => setStateDialog(() => currentInput = ""),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (cart.discountValue > 0)
                  TextButton(
                      onPressed: () {
                        cart.removeDiscount();
                        Navigator.pop(context);
                      },
                      child: const Text("Supprimer", style: TextStyle(color: Colors.red))),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () {
                    final val = double.tryParse(currentInput) ?? 0;
                    if (val > 0) {
                      cart.applyDiscount(value: val, isPercentage: isPercentage);
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("APPLIQUER", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            )));
  }
  Future<void> _handleSavePendingOrder(CartProvider cart) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      HapticFeedback.lightImpact();
      if (cart.orderIdentifier == null || cart.orderIdentifier!.isEmpty) {
        final identifier = await _showIdentifierDialog();
        if (identifier == null || identifier.isEmpty) return;
        cart.setOrderIdentifier(identifier);
        _identifierController.text = identifier;
      }
      final String currentFranchiseeId = widget.franchiseeId;
      final String currentIdentifier = cart.orderIdentifier!;
      final List<CartItem> itemsToSave = List.from(cart.items);
      final double totalToSave = cart.total;
      final String typeStr = cart.orderType == OrderType.takeaway ? 'takeaway' : 'onSite';
      cart.clearCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Commande mise en attente."),
            backgroundColor: Colors.blueAccent,
            duration: Duration(seconds: 1)));
      }
      await FranchiseRepository().savePendingOrder(
          currentFranchiseeId, currentIdentifier, itemsToSave, totalToSave,
          source: 'pos', orderType: typeStr);
    } catch (e) {
      debugPrint("Erreur sauvegarde : $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  Future<void> _handleSendToKitchen(CartProvider cart) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final printerConfig = widget.posData.printerConfig;
      if (cart.orderIdentifier == null || cart.orderIdentifier!.isEmpty) {
        final identifier = await _showIdentifierDialog();
        if (identifier == null || identifier.isEmpty) return;
        cart.setOrderIdentifier(identifier);
        _identifierController.text = identifier;
      }
      final String kitchenOrderType = cart.orderType == OrderType.takeaway ? "A EMPORTER" : "SUR PLACE";
      final itemsToPrint = cart.items.where((item) => !item.isSentToKitchen).toList();
      final bool allItemsAlreadySent = itemsToPrint.isEmpty && cart.items.isNotEmpty;
      if (allItemsAlreadySent) {
        final bool? confirmReprint = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Attention"),
            content: const Text("Les produits de la commande ont déjà été envoyés. Voulez-vous réimprimer ?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Réimprimer")),
            ],
          ),
        );
        if (confirmReprint != true) return;
        if (printerConfig.isKitchenPrintingEnabled) {
          await PrintingService().printKitchenTicketSafe(
            printerConfig: printerConfig,
            itemsToPrint: cart.items,
            identifier: cart.orderIdentifier!,
            isUpdate: false,
            isReprint: true,
            orderType: kitchenOrderType,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Réimpression envoyée."), backgroundColor: Colors.blue));
          }
        }
        return;
      }
      cart.markUnsentItemsAsSent();
      HapticFeedback.heavyImpact();
      if (printerConfig.isKitchenPrintingEnabled) {
        await PrintingService().printKitchenTicketSafe(
          printerConfig: printerConfig,
          itemsToPrint: itemsToPrint,
          identifier: cart.orderIdentifier!,
          isUpdate: cart.items.length > itemsToPrint.length,
          isReprint: false,
          orderType: kitchenOrderType,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  Future<void> _processPayment(Map<String, dynamic> paymentMethods, CartProvider cart) async {
    if (cart.items.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      if (paymentMethods.containsKey('Card') && (paymentMethods['Card'] as double) > 0) {
        final double amountCb = paymentMethods['Card']!;
        final bool? confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: const [
              Icon(Icons.credit_card, color: Colors.blue, size: 30),
              SizedBox(width: 10),
              Text("Paiement TPE")
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Veuillez encaisser sur le TPE :", style: TextStyle(fontSize: 18)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200)),
                  child: Text("${amountCb.toStringAsFixed(2)} €",
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.blue)),
                ),
                const SizedBox(height: 24),
                const Text("Une fois le ticket sorti, validez ici.",
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text("PAIEMENT VALIDÉ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      HapticFeedback.mediumImpact();
      // --- NEW : capture AVANT clearCart pour auto-envoi cuisine à l'encaissement ---
      // Le flag autoSendKitchenOnPayment est sauvegardé côté Settings dans SharedPreferences
      // (LocalConfigService) alors que le reste de printerConfig vient de Firestore → on relit localement.
      final printerConfigForAutoSend = widget.posData.printerConfig;
      final localPrinterConfig = await LocalConfigService().getPrinterConfig();
      final bool shouldAutoSendKitchen =
          printerConfigForAutoSend.isKitchenPrintingEnabled &&
              localPrinterConfig.autoSendKitchenOnPayment &&
              cart.hasUnsentItems;
      final List<CartItem> unsentItemsSnapshot = shouldAutoSendKitchen
          ? cart.items.where((i) => !i.isSentToKitchen).toList()
          : const [];
      final String autoKitchenOrderType =
      cart.orderType == OrderType.takeaway ? "A EMPORTER" : "SUR PLACE";
      final String autoKitchenIdentifier = cart.orderIdentifier ?? '';
      // --- FIN NEW ---
      final List<Map<String, dynamic>> itemsPayload = cart.items.map((item) {
        final double realUnitPrice = item.quantity > 0 ? (item.total / item.quantity) : item.price;
        final String pId = item.product.productId ?? '';
        return {
          'id': pId,
          'masterProductId': pId,
          'productId': pId,
          'name': item.product.name,
          'quantity': item.quantity,
          'price': realUnitPrice,
          'unitPrice': realUnitPrice,
          'total': item.total,
          'vatRate': item.vatRate,
          'options': item.selectedOptions.entries.map((e) => {
            'sectionId': e.key,
            'items': e.value.map((si) => {
              'masterProductId': si.product.productId,
              'productId': si.product.productId,
              'name': si.product.name,
              'supplementPrice': si.supplementPrice
            }).toList()
          }).toList(),
          'removedIngredientProductIds': item.removedIngredientProductIds,
          'removedIngredientNames': item.removedIngredientNames,
        };
      }).toList();
      final transaction = Transaction(
        id: const Uuid().v4(),
        sessionId: widget.activeSession.id,
        franchiseeId: widget.franchiseeId,
        timestamp: DateTime.now(),
        items: itemsPayload,
        subTotal: cart.subTotal,
        discountAmount: cart.discountAmount,
        total: cart.total,
        vatTotal: cart.totalVat,
        paymentMethods: paymentMethods,
        status: 'completed',
        orderType: cart.orderType.name,
        identifier: cart.orderIdentifier ?? '',
        source: 'caisse',
        customerName: null,
        kioskName: null,
      );
      await FranchiseRepository().recordTransaction(transaction);
      // --- NEW : auto-impression ticket client si activé dans Settings ---
      try {
        final localReceiptConfig = await LocalConfigService().getReceiptConfig();
        if (localReceiptConfig.printReceiptOnPayment) {
          await PrintingService().printReceipt(
            printerConfig: printerConfigForAutoSend,
            transaction: transaction,
            franchisee: {},
            receiptConfig: localReceiptConfig.toMap(),
          );
        }
      } catch (e) {
        debugPrint("Erreur auto-impression ticket client: $e");
      }
      // --- FIN NEW ---
      // --- NEW : auto-envoi cuisine si activé ET rien n'a encore été envoyé ---
      if (shouldAutoSendKitchen && unsentItemsSnapshot.isNotEmpty) {
        try {
          await PrintingService().printKitchenTicketSafe(
            printerConfig: printerConfigForAutoSend,
            itemsToPrint: unsentItemsSnapshot,
            identifier: autoKitchenIdentifier.isNotEmpty ? autoKitchenIdentifier : "CLIENT",
            isUpdate: false,
            isReprint: false,
            orderType: autoKitchenOrderType,
          );
          cart.markUnsentItemsAsSent();
        } catch (e) {
          debugPrint("Erreur auto-envoi cuisine: $e");
          // on laisse le paiement se conclure même si l'impression cuisine échoue
        }
      }
      // --- FIN NEW ---
      cart.clearCart();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          });
          return const PaymentSuccessDialog();
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur d'enregistrement: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  void _showPaymentOptions(CartProvider cart) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Choisir le moyen de paiement",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  _buildPaymentButton(Icons.credit_card, "CARTE", const Color(0xFF1A237E), () {
                    if (_isProcessing) return;
                    Navigator.pop(ctx);
                    _processPayment({'Card': cart.total}, cart);
                  }),
                  _buildPaymentButton(Icons.money, "ESPÈCES", const Color(0xFF27AE60), () async {
                    if (_isProcessing) return;
                    Navigator.pop(ctx);
                    final bool? paid = await showDialog(
                        context: context, builder: (_) => CashPaymentDialog(totalDue: cart.total));
                    if (paid == true) {
                      _processPayment({'Cash': cart.total}, cart);
                    }
                  }),
                  _buildPaymentButton(Icons.receipt_long, "TICKET RESTO", const Color(0xFFF57C00), () async {
                    if (_isProcessing) return;
                    Navigator.pop(ctx);
                    final double? amount = await showDialog(
                        context: context, builder: (_) => TicketPaymentDialog(totalDue: cart.total));
                    if (amount != null) {
                      _processPayment({'Ticket': amount}, cart);
                    }
                  }),
                  _buildPaymentButton(Icons.call_split, "MIXTE", const Color(0xFF546E7A), () async {
                    if (_isProcessing) return;
                    Navigator.pop(ctx);
                    final Map<String, double>? methods = await showDialog(
                        context: context, builder: (_) => MixedPaymentDialog(totalDue: cart.total));
                    if (methods != null) _processPayment(methods, cart);
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _buildPaymentButton(IconData icon, String label, Color color, VoidCallback tap) {
    return SizedBox(
      width: 150,
      height: 130,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16))
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildPendingOrdersButton() {
    return StreamBuilder<List<PendingOrder>>(
      stream: FranchiseRepository().getPendingOrdersStream(widget.franchiseeId),
      builder: (context, snapshot) {
        final orders = snapshot.data?.where((o) => !(o.source == 'borne' && o.isPaid)).toList() ?? [];
        final count = orders.length;
        final bool hasOrders = count > 0;
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            foregroundColor: hasOrders ? Colors.white : Colors.grey.shade700,
            backgroundColor: hasOrders ? Colors.orange.shade800 : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            elevation: hasOrders ? 4 : 0,
            side: hasOrders ? null : BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => _showPendingOrdersSheet(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pause_circle_filled_outlined, size: 24),
              const SizedBox(width: 8),
              const Text("En attente", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (hasOrders) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text(count.toString(),
                      style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                )
              ]
            ],
          ),
        );
      },
    );
  }
  void _showPendingOrdersSheet() {
    final double width = MediaQuery.of(context).size.width * 0.8;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: width),
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (_, __) => PendingOrdersView(franchiseeId: widget.franchiseeId)),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        if (_identifierController.text != cart.orderIdentifier) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _identifierController.text = cart.orderIdentifier ?? '';
            }
          });
        }
        if (!widget.isTablet) {
          if (cart.items.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => _showMobileCartModal(context, cart),
            child: Container(
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF2C3E50),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("${cart.items.length} articles", style: const TextStyle(color: Colors.white)),
                Text("${cart.total.toStringAsFixed(2)} €",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(left: BorderSide(color: Colors.grey.shade300, width: 1.0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final newId = await _showIdentifierDialog();
                              if (newId != null) cart.setOrderIdentifier(newId);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade300)),
                              child: Row(children: [
                                Icon(Icons.edit_note, color: Colors.blue.shade700),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(cart.orderIdentifier ?? "Client / Table",
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: cart.orderIdentifier != null ? Colors.black87 : Colors.grey))),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.inventory_2_outlined, color: Colors.grey),
                          tooltip: "Stocks",
                          onPressed: () => showDialog(
                              context: context,
                              builder: (_) => StockManagementDialog(
                                  franchiseeId: widget.franchiseeId,
                                  franchisorId: widget.franchisorId,
                                  menuSettings: widget.posData.menuSettings,
                                  onStockChanged: widget.onStockChanged)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildPendingOrdersButton()),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.history_toggle_off, size: 28),
                          onPressed: () => _showPaidOrdersHistory(context, widget.franchiseeId),
                          tooltip: "Historique",
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Expanded(
                child: cart.items.isEmpty
                    ? Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.shopping_basket_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text("Panier vide",
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
                    ]))
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return _CartItemCard(item: item, cart: cart, posData: widget.posData);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, -5))
                ]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 45,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(4),
                      child: Row(children: [
                        _buildTypeButton(OrderType.onSite, "SUR PLACE", Icons.table_restaurant, cart),
                        _buildTypeButton(OrderType.takeaway, "EMPORTER", Icons.shopping_bag, cart),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: cart.items.isNotEmpty ? () => _showDiscountDialog(cart) : null,
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Icon(Icons.local_offer_outlined,
                            size: 16, color: cart.discountValue > 0 ? Colors.green : Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                            cart.discountValue > 0
                                ? "- ${cart.discountAmount.toStringAsFixed(2)} €"
                                : "Ajouter remise",
                            style: TextStyle(
                                color: cart.discountValue > 0 ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("${cart.items.length} articles",
                          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                      Text("TVA: ${cart.totalVat.toStringAsFixed(2)} €",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("TOTAL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("${cart.total.toStringAsFixed(2)} €",
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                    ]),
                    const Divider(height: 24),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (cart.items.isNotEmpty && !_isProcessing) ? () => _handleSavePendingOrder(cart) : null,
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: Colors.orange.shade200),
                              foregroundColor: Colors.orange.shade800),
                          child: const Column(children: [
                            Icon(Icons.watch_later_outlined),
                            SizedBox(height: 2),
                            Text("Attente", style: TextStyle(fontSize: 12))
                          ]),
                        ),
                      ),
                      if (widget.posData.printerConfig.isKitchenPrintingEnabled) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (cart.items.isNotEmpty && !_isProcessing) ? () => _handleSendToKitchen(cart) : null,
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: Colors.blue.shade200),
                                foregroundColor: Colors.blue.shade800),
                            child: Column(children: [
                              Icon(!cart.hasUnsentItems && cart.items.isNotEmpty
                                  ? Icons.print
                                  : Icons.soup_kitchen),
                              const SizedBox(height: 2),
                              Text(!cart.hasUnsentItems && cart.items.isNotEmpty ? "Réimp." : "Cuisine",
                                  style: const TextStyle(fontSize: 12))
                            ]),
                          ),
                        ),
                      ]
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 75,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF27AE60),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 4),
                        onPressed: (cart.items.isNotEmpty && !_isProcessing) ? () => _showPaymentOptions(cart) : null,
                        child: Text(_isProcessing ? "TRAITEMENT..." : "ENCAISSER",
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _buildTypeButton(OrderType type, String label, IconData icon, CartProvider cart) {
    final isSelected = cart.orderType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => _toggleOrderType({type}),
        child: Container(
          decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)] : []),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: isSelected ? Colors.black87 : Colors.grey),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.black87 : Colors.grey,
                    fontSize: 13)),
          ]),
        ),
      ),
    );
  }
  void _showMobileCartModal(BuildContext context, CartProvider cart) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        builder: (_, scroll) => Container(
          color: Colors.white,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Panier", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))
              ]),
              const Divider(),
              ...cart.items.map((item) => _CartItemCard(item: item, cart: cart, posData: widget.posData)),
              const Divider(),
              _buildTotalsAndActions(context, cart)
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildTotalsAndActions(BuildContext context, CartProvider cart) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Total"),
        Text("${cart.total} €", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))
      ]),
      const SizedBox(height: 20),
      SizedBox(
          width: double.infinity,
          child: ElevatedButton(
              onPressed: _isProcessing ? null : () => _showPaymentOptions(cart),
              child: Text(_isProcessing ? "Traitement..." : "Payer")))
    ]);
  }
}
class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final CartProvider cart;
  final PosData posData;
  const _CartItemCard({
    required this.item,
    required this.cart,
    required this.posData,
  });
  Future<void> _editItem(BuildContext context) async {
    final sections = posData.allSections.where((s) => item.product.sectionIds.contains(s.sectionId)).toList();
    final CartItem? editedItem = await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => ProductOptionsPage(
          product: item.product,
          basePrice: item.price,
          vatRate: item.vatRate,
          sections: sections,
          initialOptions: item.selectedOptions,
          franchiseeId: '',
          allProductsRef: [],
          initialRemovedIngredientIds: item.removedIngredientProductIds,
        ),
      ),
    );
    if (editedItem != null) {
      cart.removeItem(item);
      cart.addItem(editedItem);
    }
  }
  @override
  Widget build(BuildContext context) {
    final Map<String, List<SectionItem>> groupedOptions = item.selectedOptions;
    final List<String> sortedSectionIds = groupedOptions.keys.toList();
    final bool isEditable = item.product.sectionIds.isNotEmpty || item.product.isComposite;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: item.isSentToKitchen ? Colors.grey.shade50 : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!item.isSentToKitchen && item.quantity > 1)
              InkWell(
                onTap: () => cart.decrementItemQuantity(item),
                child: Container(
                  width: 65,
                  color: Colors.red.shade50,
                  alignment: Alignment.center,
                  child: Icon(Icons.remove, color: Colors.red.shade900, size: 32),
                ),
              ),
            Expanded(
              child: InkWell(
                onTap: item.isSentToKitchen ? null : () => cart.incrementItemQuantity(item),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.white),
                            child: Text("${item.quantity}",
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(item.product.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: item.isSentToKitchen ? Colors.grey : Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text("${item.total.toStringAsFixed(2)} €",
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                      if (groupedOptions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...sortedSectionIds.map((sectionId) {
                          final options = groupedOptions[sectionId]!;
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.only(top: 4, left: 8),
                            decoration: const BoxDecoration(
                                border: Border(top: BorderSide(color: Colors.black12, width: 0.5))),
                            child: Wrap(
                              spacing: 8.0,
                              runSpacing: 2.0,
                              children: options.map((opt) {
                                String displayText = "+ ${opt.product.name}";
                                if (opt.supplementPrice > 0) {
                                  displayText += " (${opt.supplementPrice.toStringAsFixed(2)}€)";
                                }
                                return Text(displayText,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w500));
                              }).toList(),
                            ),
                          );
                        }),
                      ],
                      if (item.removedIngredientNames.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                              item.removedIngredientNames.map((n) => "🚫 Sans $n").join(", "),
                              style: TextStyle(
                                  fontSize: 13, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (!item.isSentToKitchen)
              Column(
                children: [
                  if (isEditable)
                    Expanded(
                      child: InkWell(
                        onTap: () => _editItem(context),
                        child: Container(
                            width: 60,
                            color: Colors.blue.shade50,
                            child: Icon(Icons.edit, color: Colors.blue.shade800, size: 26)),
                      ),
                    ),
                  Expanded(
                    child: InkWell(
                      onTap: () => cart.removeItem(item),
                      child: Container(
                          width: 60,
                          color: Colors.grey.shade100,
                          child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 26)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}