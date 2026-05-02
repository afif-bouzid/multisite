import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/auth_provider.dart';
import '../../../../core/repository/repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '/models.dart';
import 'transaction_dialogs.dart';

class ActiveSessionPaidHistoryView extends StatelessWidget {
  const ActiveSessionPaidHistoryView({super.key});
  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final franchiseeId = Provider.of<AuthProvider>(context).franchiseUser!.uid;
    return StreamBuilder<TillSession?>(
      stream: repository.getActiveSession(franchiseeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(
            child: Text("Aucune session de caisse active trouvée."),
          );
        }
        final activeSession = snapshot.data!;
        return SessionTransactionsDetailView(
          session: activeSession,
          repository: repository,
        );
      },
    );
  }
}

class SessionTransactionsDetailView extends StatelessWidget {
  final TillSession session;
  final FranchiseRepository repository;
  const SessionTransactionsDetailView({
    super.key,
    required this.session,
    required this.repository,
  });
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Transaction>>(
      stream: repository.getSessionTransactions(session.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: Text("Aucune commande payée dans cette session.")));
        }
        final transactions = snapshot.data!;
        double totalSales = transactions.fold(0.0, (sum, t) => sum + t.total);
        int totalOrders = transactions.length;
        String openTime = DateFormat('HH:mm').format(session.openingTime);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Session Active - Ouverte à $openTime",
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total Commandes Payées : $totalOrders",
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        "${totalSales.toStringAsFixed(2)} EUR",
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, thickness: 2),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final transaction = transactions[index];
                  final shortId = transaction.id.substring(0, 6);
                  String mainTitle = transaction.identifier;
                  String subTitle = "Ticket #$shortId";
                  if (mainTitle.isEmpty) {
                    mainTitle = "Ticket #$shortId";
                    subTitle = DateFormat('dd/MM/yy HH:mm')
                        .format(transaction.timestamp);
                  } else {
                    subTitle +=
                        " - ${DateFormat('HH:mm').format(transaction.timestamp)}";
                  }
                  final orderTypeLabel = transaction.orderType ==
                          OrderType.takeaway.toString().split('.').last
                      ? 'À Emporter'
                      : 'Sur Place';
                  final isTakeaway = transaction.orderType ==
                      OrderType.takeaway.toString().split('.').last;
                  final primaryColor =
                      isTakeaway ? AppColors.bkBlue : AppColors.bkGreen;
                  final lightAccentColor = primaryColor.withValues(alpha: 0.12);
                  return Card(
                    elevation: 0,
                    margin:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: lightAccentColor, width: 2)),
                    child: InkWell(
                      onTap: () => showDialog(
                          context: context,
                          builder: (_) => TransactionDetailDialog(
                              transaction: transaction)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 25),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                    isTakeaway
                                        ? Icons.delivery_dining
                                        : Icons.restaurant,
                                    color: primaryColor,
                                    size: 30),
                                const SizedBox(width: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(mainTitle,
                                        style: AppTextStyles.headlineSmall
                                            .copyWith(
                                                color: AppColors.bkBrown,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 22)),
                                    const SizedBox(height: 4),
                                    Text(subTitle,
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                                color: Colors.grey.shade600)),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                    "${transaction.total.toStringAsFixed(2)} €",
                                    style: AppTextStyles.headlineSmall.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.bkBrown)),
                                const SizedBox(height: 4),
                                Text(orderTypeLabel,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                        color: primaryColor,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        );
      },
    );
  }
}

class TillCloseForm extends StatefulWidget {
  final TillSession session;
  const TillCloseForm({super.key, required this.session});
  @override
  State<TillCloseForm> createState() => _TillCloseFormState();
}

class _TillCloseFormState extends State<TillCloseForm> {
  final _formKey = GlobalKey<FormState>();
  final _finalCashController = TextEditingController();
  bool _isLoading = false;
  @override
  void initState() {
    super.initState();
    _finalCashController.text = widget.session.initialCash.toStringAsFixed(2);
  }

  Future<void> _closeTill() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    final finalCash =
        double.tryParse(_finalCashController.text.replaceAll(',', '.')) ?? 0.0;
    final error = await repository.closeTillSession(
        sessionId: widget.session.id, finalCash: finalCash);
    if (mounted) {
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Session de caisse clôturée avec succès."),
            backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur: $error"), backgroundColor: Colors.red));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open_outlined,
                  size: 40, color: Colors.green.shade600),
              const SizedBox(height: 16),
              Text(
                "Clôturer la session de caisse",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                  "Ouverte le ${DateFormat('dd/MM/yyyy HH:mm').format(widget.session.openingTime)}"),
              const SizedBox(height: 24),
              TextFormField(
                controller: _finalCashController,
                decoration: const InputDecoration(
                    labelText: "Fonds de caisse final (€)",
                    prefixIcon: Icon(Icons.money)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (v) => v!.isEmpty ||
                        (double.tryParse(v.replaceAll(',', '.')) == null)
                    ? "Montant valide requis"
                    : null,
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.lock_outline),
                      label: const Text("Clôturer la Caisse"),
                      onPressed: _closeTill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
