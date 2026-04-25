import 'package:flutter/material.dart';

class CashPaymentDialog extends StatefulWidget {
  final double totalDue;
  const CashPaymentDialog({super.key, required this.totalDue});
  @override
  State<CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<CashPaymentDialog> {
  final _amountController = TextEditingController();
  double _amountReceived = 0.0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_calculateChange);
  }

  @override
  void dispose() {
    _amountController.removeListener(_calculateChange);
    _amountController.dispose();
    super.dispose();
  }

  void _calculateChange() => setState(() => _amountReceived =
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0);

  @override
  Widget build(BuildContext context) {
    final changeDue = _amountReceived - widget.totalDue;
    return AlertDialog(
      title: const Text("Paiement en Espèces"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Total à payer : ${widget.totalDue.toStringAsFixed(2)} €",
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        TextField(
            controller: _amountController,
            autofocus: true,
            decoration:
            const InputDecoration(labelText: "Montant reçu du client (€)"),
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 20),
        Text("Rendu monnaie :", style: Theme.of(context).textTheme.titleMedium),
        Text(changeDue < 0 ? "0.00 €" : "${changeDue.toStringAsFixed(2)} €",
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: Colors.green, fontWeight: FontWeight.bold))
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler")),
        ElevatedButton(
            onPressed: _amountReceived >= widget.totalDue - 0.01
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text("Valider le paiement")),
      ],
    );
  }
}

class TicketPaymentDialog extends StatefulWidget {
  final double totalDue;
  const TicketPaymentDialog({super.key, required this.totalDue});
  @override
  State<TicketPaymentDialog> createState() => _TicketPaymentDialogState();
}

class _TicketPaymentDialogState extends State<TicketPaymentDialog> {
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.totalDue.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Paiement par Ticket Restaurant"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Total à payer : ${widget.totalDue.toStringAsFixed(2)} €",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextField(
              controller: _amountController,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: "Montant payé en tickets (€)"),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: () {
            final amount =
            double.tryParse(_amountController.text.replaceAll(',', '.'));
            if (amount != null && (amount - widget.totalDue).abs() < 0.01) {
              Navigator.pop(context, amount);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                  Text("Le montant doit correspondre au total à payer.")));
            }
          },
          child: const Text("Valider le paiement"),
        ),
      ],
    );
  }
}

class MixedPaymentDialog extends StatefulWidget {
  final double totalDue;

  // NOUVEAU : Ajout d'un paramètre pour savoir d'où vient la commande
  // Par défaut sur "false" car cette interface est pensée pour un caissier (Comptoir)
  final bool isKiosk;

  const MixedPaymentDialog({
    super.key,
    required this.totalDue,
    this.isKiosk = false,
  });

  @override
  State<MixedPaymentDialog> createState() => _MixedPaymentDialogState();
}

class _MixedPaymentDialogState extends State<MixedPaymentDialog> {
  final _cashController = TextEditingController();
  final _cardController = TextEditingController();
  final _ticketController = TextEditingController();

  final FocusNode _cashFocus = FocusNode();
  final FocusNode _cardFocus = FocusNode();
  final FocusNode _ticketFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _cardController.text = widget.totalDue.toStringAsFixed(2);
    _cashController.text = '0.00';
    _ticketController.text = '0.00';

    _cashController.addListener(_recalculate);
    _cardController.addListener(_recalculate);
    _ticketController.addListener(_recalculate);
  }

  void _recalculate() {
    if (!mounted) return;
    setState(
            () {}); // Rafraîchit l'interface pour recalculer le rendu de monnaie en temps réel
  }

  @override
  void dispose() {
    _cashController.dispose();
    _cardController.dispose();
    _ticketController.dispose();
    _cashFocus.dispose();
    _cardFocus.dispose();
    _ticketFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. On récupère ce que le caissier a tapé
    final cashReceived =
        double.tryParse(_cashController.text.replaceAll(',', '.')) ?? 0.0;
    final cardAmount =
        double.tryParse(_cardController.text.replaceAll(',', '.')) ?? 0.0;
    final ticketAmount =
        double.tryParse(_ticketController.text.replaceAll(',', '.')) ?? 0.0;

    // 2. On calcule la somme totale donnée et le rendu monnaie (qui ne s'applique que sur les espèces)
    final sumReceived = cashReceived + cardAmount + ticketAmount;
    final changeDue = sumReceived - widget.totalDue;

    // 3. Le paiement est valide si on a atteint ou dépassé le montant dû
    final isValid = changeDue >= -0.01;

    return AlertDialog(
      title: const Text('Paiement Mixte'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total à payer: ${widget.totalDue.toStringAsFixed(2)} €',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            TextField(
              controller: _cardController,
              focusNode: _cardFocus,
              decoration: const InputDecoration(
                  labelText: 'Montant par Carte (€)',
                  prefixIcon: Icon(Icons.credit_card)),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ticketController,
              focusNode: _ticketFocus,
              decoration: const InputDecoration(
                  labelText: 'Montant en Tickets (€)',
                  prefixIcon: Icon(Icons.receipt_long)),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cashController,
              focusNode: _cashFocus,
              decoration: const InputDecoration(
                  labelText:
                  'Montant reçu en Espèces (€)', // Précision pour le caissier
                  prefixIcon: Icon(Icons.money)),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
            ),

            // Affichage conditionnel du rendu de monnaie
            if (changeDue > 0.01) ...[
              const Divider(height: 30, thickness: 2),
              Text("Rendu monnaie (Espèces) :",
                  style: Theme.of(context).textTheme.titleMedium),
              Text("${changeDue.toStringAsFixed(2)} €",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: isValid
              ? () {
            final result = <String, double>{};

            // On calcule la portion d'espèces qui sert réellement à payer l'addition
            // Si on doit rendre de la monnaie, on la déduit des espèces reçues.
            final cashApplied =
                cashReceived - (changeDue > 0 ? changeDue : 0);

            // --- NOUVELLE LOGIQUE DE VENTILATION DES CB ---
            if (cardAmount > 0) {
              if (widget.isKiosk) {
                result['Card_Kiosk'] = cardAmount;
              } else {
                result['Card_Counter'] = cardAmount;
              }
            }

            if (cashApplied > 0) {
              result['Cash'] =
                  cashApplied; // On enregistre le montant exact, pas le billet !
            }
            if (ticketAmount > 0) result['Ticket'] = ticketAmount;

            Navigator.pop(context, result);
          }
              : null,
          child: const Text('Valider le paiement'),
        )
      ],
    );
  }
}