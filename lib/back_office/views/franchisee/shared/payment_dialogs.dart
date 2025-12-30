import 'package:flutter/material.dart';

// --- DIALOGUE PAIEMENT ESPÈCES ---
class CashPaymentDialog extends StatefulWidget {
  final double totalDue;

  const CashPaymentDialog({super.key, required this.totalDue});

  @override
  State<CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<CashPaymentDialog> {
  String _currentInput = "";

  double get _amountReceived {
    if (_currentInput.isEmpty) return 0.0;
    return double.tryParse(_currentInput.replaceAll(',', '.')) ?? 0.0;
  }

  void _onNumber(String num) {
    if (num == '.' && _currentInput.contains('.')) return;
    setState(() => _currentInput += num);
  }

  void _onBackspace() {
    if (_currentInput.isNotEmpty) {
      setState(() =>
          _currentInput = _currentInput.substring(0, _currentInput.length - 1));
    }
  }

  void _onClear() {
    setState(() => _currentInput = "");
  }

  void _addCash(int amount) {
    double current = _amountReceived;
    setState(() {
      _currentInput = (current + amount).toStringAsFixed(2);
      if (_currentInput.endsWith(".00"))
        _currentInput = _currentInput.substring(0, _currentInput.length - 3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final changeDue = _amountReceived - widget.totalDue;
    final bool isEnough = _amountReceived >= widget.totalDue;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Espèces"),
          Text("Payer : ${widget.totalDue.toStringAsFixed(2)} €",
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey)),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 550, // Hauteur ajustée
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Reçu :",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(
                    _currentInput.isEmpty ? "0.00 €" : "$_currentInput €",
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: isEnough ? Colors.orange.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("À rendre :", style: TextStyle(fontSize: 18)),
                  Text(
                    changeDue > 0
                        ? "${changeDue.toStringAsFixed(2)} €"
                        : "0.00 €",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isEnough ? Colors.orange.shade900 : Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [5, 10, 20, 50]
                  .map((val) => ActionChip(
                        label: Text("+${val}€"),
                        padding: const EdgeInsets.all(4),
                        backgroundColor: Colors.blue.shade50,
                        onPressed: () => _addCash(val),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Numpad(
                onNumber: _onNumber,
                onBackspace: _onBackspace,
                onClear: _onClear,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
          child: const Text("Annuler",
              style: TextStyle(fontSize: 18, color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: isEnough ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("VALIDER",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// --- DIALOGUE PAIEMENT TICKET RESTO ---
class TicketPaymentDialog extends StatefulWidget {
  final double totalDue;

  const TicketPaymentDialog({super.key, required this.totalDue});

  @override
  State<TicketPaymentDialog> createState() => _TicketPaymentDialogState();
}

class _TicketPaymentDialogState extends State<TicketPaymentDialog> {
  String _currentInput = "";

  @override
  void initState() {
    super.initState();
    // _currentInput = widget.totalDue.toStringAsFixed(2); // Optionnel : pré-remplir ou non
    _currentInput = "";
  }

  void _onNumber(String num) {
    if (num == '.' && _currentInput.contains('.')) return;
    setState(() => _currentInput += num);
  }

  void _onBackspace() {
    if (_currentInput.isNotEmpty) {
      setState(() =>
          _currentInput = _currentInput.substring(0, _currentInput.length - 1));
    }
  }

  void _onClear() => setState(() => _currentInput = "");

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_currentInput) ?? 0.0;
    final remaining = widget.totalDue - amount;

    final bool isOverPaid = remaining < -0.01; // Tolérance flottante
    final double displayValue = isOverPaid ? (remaining * -1) : remaining;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Ticket Restaurant"),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8)),
            child: Text("Payer : ${widget.totalDue.toStringAsFixed(2)} €",
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
          )
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 500,
        child: Column(
          children: [
            // Info box Reste / Trop perçu
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isOverPaid
                    ? Colors.red.withOpacity(0.1)
                    : Colors.blue.shade50,
                border: Border.all(
                    color: isOverPaid ? Colors.red : Colors.blue.shade800,
                    width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                      isOverPaid
                          ? Icons.warning_amber_rounded
                          : Icons.credit_card,
                      color: isOverPaid ? Colors.red : Colors.blue.shade800,
                      size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(
                          isOverPaid ? "TROP PERÇU (PERDU)" : "RESTE À PAYER",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800))),
                  Text(
                    "${displayValue.toStringAsFixed(2)} €",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isOverPaid ? Colors.red : Colors.blue.shade800),
                  ),
                ],
              ),
            ),

            // Champ Saisie
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.orange, width: 3),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.orange.withOpacity(0.2), blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long,
                      color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text("Montant Ticket",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87))),
                  Text(
                    _currentInput.isEmpty ? "0.00 €" : "$_currentInput €",
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Expanded(
              child: Numpad(
                onNumber: _onNumber,
                onBackspace: _onBackspace,
                onClear: _onClear,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: (amount > 0) ? () => Navigator.pop(context, amount) : null,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
          child: const Text("VALIDER",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// --- DIALOGUE PAIEMENT MIXTE (COMPACT & OPTIMISÉ) ---
class MixedPaymentDialog extends StatefulWidget {
  final double totalDue;

  const MixedPaymentDialog({super.key, required this.totalDue});

  @override
  State<MixedPaymentDialog> createState() => _MixedPaymentDialogState();
}

class _MixedPaymentDialogState extends State<MixedPaymentDialog> {
  String _cashInput = "";
  String _ticketInput = "";
  String _selectedField = "cash";

  double get _cashAmount => double.tryParse(_cashInput) ?? 0.0;

  double get _ticketAmount => double.tryParse(_ticketInput) ?? 0.0;

  double get _cardAmount {
    double remainder = widget.totalDue - (_cashAmount + _ticketAmount);
    return remainder > 0 ? remainder : 0.0;
  }

  double get _changeDue {
    double totalGiven = _cashAmount + _ticketAmount;
    if (totalGiven > widget.totalDue) {
      return totalGiven - widget.totalDue;
    }
    return 0.0;
  }

  void _onNumber(String num) {
    if (num == '.' && _getCurrentInput().contains('.')) return;
    setState(() {
      _updateCurrentInput(_getCurrentInput() + num);
    });
  }

  void _onBackspace() {
    String current = _getCurrentInput();
    if (current.isNotEmpty) {
      setState(() {
        _updateCurrentInput(current.substring(0, current.length - 1));
      });
    }
  }

  void _onClear() {
    setState(() {
      _updateCurrentInput("");
    });
  }

  String _getCurrentInput() {
    if (_selectedField == 'cash') return _cashInput;
    return _ticketInput;
  }

  void _updateCurrentInput(String val) {
    if (_selectedField == 'cash') {
      _cashInput = val;
    } else {
      _ticketInput = val;
    }
  }

  Widget _buildReadOnlyField(
      String label, IconData icon, double value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      // Marge réduite
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      // Padding réduit
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800))),
          Text(
            "${value.toStringAsFixed(2)} €",
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
      String id, String label, IconData icon, String value, Color color) {
    final isSelected = _selectedField == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedField = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        // Marge réduite
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // Padding réduit
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 3 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 4)]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 26),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700))),
            Text(
              value.isEmpty ? "0.00 €" : "$value €",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showChange = _changeDue > 0;
    final double totalEntered = _cashAmount + _ticketAmount + _cardAmount;
    final bool isValid =
        (totalEntered - widget.totalDue).abs() < 0.01 || showChange;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Paiement Mixte"),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8)),
            child: Text("Total : ${widget.totalDue.toStringAsFixed(2)} €",
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
          )
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            if (showChange)
              _buildReadOnlyField(
                  "À RENDRE", Icons.savings, _changeDue, Colors.orange)
            else
              _buildReadOnlyField("RESTE EN CARTE", Icons.credit_card,
                  _cardAmount, Colors.blue.shade800),
            _buildEditableField(
                'cash', 'Espèces', Icons.money, _cashInput, Colors.green),
            _buildEditableField('ticket', 'Tickets Resto', Icons.receipt_long,
                _ticketInput, Colors.orange),
            const SizedBox(height: 4),
            const Divider(),
            const SizedBox(height: 4),
            Expanded(
              child: Numpad(
                onNumber: _onNumber,
                onBackspace: _onBackspace,
                onClear: _onClear,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler",
                style: TextStyle(fontSize: 18, color: Colors.grey))),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: isValid
              ? () {
                  final result = <String, double>{};
                  if (_cardAmount > 0) result['Card'] = _cardAmount;
                  if (_cashAmount > 0) result['Cash'] = _cashAmount;
                  if (_ticketAmount > 0) result['Ticket'] = _ticketAmount;
                  Navigator.pop(context, result);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey.shade800,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("VALIDER",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}

// --- WIDGETS PARTAGÉS (NUMPAD & AZERTY) ---

class Numpad extends StatelessWidget {
  final Function(String) onNumber;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  const Numpad(
      {super.key,
      required this.onNumber,
      required this.onBackspace,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      // Espacement réduit pour compacter
      crossAxisSpacing: 8,
      childAspectRatio: 2.0,
      // Ratio 2.0 = Touches très rectangulaires (moins hautes)
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(4),
      children: [
        _btn("1"),
        _btn("2"),
        _btn("3"),
        _btn("4"),
        _btn("5"),
        _btn("6"),
        _btn("7"),
        _btn("8"),
        _btn("9"),
        _actionBtn("C", Colors.red.shade100, Colors.red, onClear),
        _btn("0"),
        _btn("."),
        // On peut ajouter un bouton Backspace ici si on veut, ou utiliser le layout 3x4 classique
      ],
    );
  }

  Widget _btn(String label) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        onTap: () => onNumber(label),
        borderRadius: BorderRadius.circular(8),
        child: Center(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87))),
      ),
    );
  }

  Widget _actionBtn(String label, Color bg, Color text, VoidCallback tap) {
    return Material(
      color: bg,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: text))),
      ),
    );
  }
}

class AzertyKeyboard extends StatelessWidget {
  final Function(String) onInput;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;

  const AzertyKeyboard(
      {super.key,
      required this.onInput,
      required this.onBackspace,
      required this.onSpace});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"]),
        _row(["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"]),
        _row(["W", "X", "C", "V", "B", "N"], pad: true),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                flex: 4,
                child: _actionBtn("ESPACE",
                    onTap: onSpace, color: Colors.grey.shade200)),
            const SizedBox(width: 12),
            Expanded(
                flex: 2,
                child: _actionBtn("EFFACER",
                    onTap: onBackspace,
                    color: Colors.red.shade100,
                    textColor: Colors.red)),
          ],
        )
      ],
    );
  }

  Widget _row(List<String> keys, {bool pad = false}) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys
            .map((k) => Expanded(
                child: Padding(
                    padding: const EdgeInsets.all(4.0), child: _keyBtn(k))))
            .toList(),
      ),
    );
  }

  Widget _keyBtn(String label) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        onTap: () => onInput(label),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _actionBtn(String label,
      {Color? color, Color? textColor, required VoidCallback onTap}) {
    return Material(
      color: color ?? Colors.grey.shade200,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor ?? Colors.black87))),
      ),
    );
  }
}
