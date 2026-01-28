import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/cart_provider.dart';
import '../../../core/repository/repository.dart';
import '../../../core/services/printing_service.dart';
import '/models.dart';
import 'shared/transaction_dialogs.dart';
import 'stats/accounting_view.dart';
import 'stats/stats_dashboard.dart';

class FranchiseeStatsView extends StatefulWidget {
  const FranchiseeStatsView({super.key});

  @override
  State<FranchiseeStatsView> createState() => _FranchiseeStatsViewState();
}

class _FranchiseeStatsViewState extends State<FranchiseeStatsView> {
  DateTime? _startDate;
  DateTime? _endDate;
  TillSession? _selectedSession;

  // Optimisation : Instance unique du repository
  final FranchiseRepository _repository = FranchiseRepository();

  String get _dateRangeText {
    if (_startDate == null && _endDate == null) return "Toute la période";
    final start = _startDate != null
        ? DateFormat('dd/MM/yy').format(_startDate!)
        : 'Début';
    final end =
        _endDate != null ? DateFormat('dd/MM/yy').format(_endDate!) : 'Fin';
    return "$start - $end";
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      setState(() {
        _startDate = pickedRange.start;
        _endDate = pickedRange.end;
        _selectedSession = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.firebaseUser == null) {
      return const Center(child: Text("Erreur : Utilisateur non trouvé."));
    }

    final bool isManager = authProvider.franchiseUser?.role == 'franchisee';
    final franchiseeId = authProvider.franchiseUser!.effectiveStoreId;
    final int tabCount = isManager ? 3 : 1;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("Gestion & Statistiques"),
          elevation: 0,
          bottom: TabBar(
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            tabs: [
              const Tab(
                  icon: Icon(Icons.point_of_sale), text: "Caisse & Clôture"),
              if (isManager) ...[
                const Tab(icon: Icon(Icons.bar_chart), text: "Analyses Ventes"),
                const Tab(
                    icon: Icon(Icons.calculate_outlined), text: "Comptabilité"),
              ],
            ],
          ),
          actions: [
            if (isManager) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: InkWell(
                  onTap: () => _selectDateRange(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Text(_dateRangeText,
                            style: const TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              if (_startDate != null)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => setState(() {
                    _startDate = null;
                    _endDate = null;
                  }),
                ),
            ]
          ],
        ),
        body: TabBarView(
          children: [
            _buildSessionsTab(franchiseeId, isManager),
            if (isManager) ...[
              StatsDashboard(
                franchiseeId: franchiseeId,
                startDate: _startDate,
                endDate: _endDate,
              ),
              AccountingView(
                franchiseeId: franchiseeId,
                startDate: _startDate,
                endDate: _endDate,
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsTab(String franchiseeId, bool isManager) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                Expanded(
                  child: _buildSessionsList(franchiseeId, isManager),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          flex: 6,
          child: _selectedSession == null
              ? _buildEmptyState()
              : _SessionDetailPanel(
                  key: ValueKey(_selectedSession!.id),
                  session: _selectedSession!,
                  repository: _repository,
                  onSessionClosed: () {
                    setState(() {
                      _selectedSession = null;
                    });
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSessionsList(String franchiseeId, bool isManager) {
    return StreamBuilder<TillSession?>(
      stream: _repository.getActiveSession(franchiseeId),
      builder: (context, activeSnapshot) {
        final activeSession = activeSnapshot.data;
        final Stream<List<TillSession>> historyStream = isManager
            ? _repository.getFranchiseeSessions(franchiseeId,
                startDate: _startDate, endDate: _endDate)
            : Stream.value([]);

        return StreamBuilder<List<TillSession>>(
          stream: historyStream,
          builder: (context, historySnapshot) {
            if (historySnapshot.connectionState == ConnectionState.waiting &&
                isManager) {
              return const Center(child: CircularProgressIndicator());
            }

            final historySessions =
                (historySnapshot.data ?? []).where((s) => s.isClosed).toList();

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                if (activeSession != null) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text("SESSION EN COURS (À CLÔTURER)",
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0)),
                  ),
                  _buildSessionTile(activeSession, isActive: true),
                  const Divider(),
                ],
                if (isManager) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text("HISTORIQUE",
                        style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0)),
                  ),
                  if (historySessions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                          child: Text(
                              "Aucune session clôturée sur cette période",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ...historySessions
                        .map((s) => _buildSessionTile(s, isActive: false)),
                ] else if (activeSession == null) ...[
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                        child: Text(
                            "Aucune session active.\nOuvrez la caisse depuis l'accueil.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey))),
                  )
                ]
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSessionTile(TillSession session, {required bool isActive}) {
    final isSelected = _selectedSession?.id == session.id;
    final dateStr = DateFormat('dd MMM yyyy').format(session.openingTime);
    final timeStr = DateFormat('HH:mm').format(session.openingTime);

    return InkWell(
      onTap: () => setState(() => _selectedSession = session),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.withOpacity(0.05) : Colors.white,
          border: Border(
            left: BorderSide(
              color: isSelected
                  ? (isActive ? Colors.green : Colors.indigo)
                  : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.green.withOpacity(0.1)
                    : Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isActive ? Icons.point_of_sale : Icons.history,
                color: isActive ? Colors.green : Colors.indigo,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? "Session Active" : "Clôture du $dateStr",
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isActive
                        ? "Ouverte à $timeStr"
                        : "Fermée à ${session.closingTime != null ? DateFormat('HH:mm').format(session.closingTime!) : '?'}",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text("Sélectionnez une session\npour voir les détails",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WIDGET OPTIMISÉ : _SessionDetailPanel (Utilisation de Slivers)
// ---------------------------------------------------------------------------
class _SessionDetailPanel extends StatefulWidget {
  final TillSession session;
  final FranchiseRepository repository;
  final VoidCallback onSessionClosed;

  const _SessionDetailPanel({
    super.key,
    required this.session,
    required this.repository,
    required this.onSessionClosed,
  });

  @override
  State<_SessionDetailPanel> createState() => _SessionDetailPanelState();
}

class _SessionDetailPanelState extends State<_SessionDetailPanel> {
  final _finalCashController = TextEditingController();
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _finalCashController.text = widget.session.initialCash.toStringAsFixed(2);
  }

  Future<void> _closeSession() async {
    final finalCash =
        double.tryParse(_finalCashController.text.replaceAll(',', '.'));
    if (finalCash == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Montant invalide"), backgroundColor: Colors.red));
      return;
    }

    try {
      final pendingOrders = await widget.repository
          .getPendingOrdersStream(widget.session.franchiseeId)
          .first;

      if (pendingOrders.isNotEmpty) {
        if (!mounted) return;
        final bool? shouldDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Commandes en attente détectées"),
            content: Text(
                "Il reste ${pendingOrders.length} commande(s) en attente.\n"
                "Vous ne pouvez pas clôturer la caisse tant qu'elles existent.\n\n"
                "Voulez-vous les supprimer définitivement et clôturer ?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Supprimer et Clôturer"),
              ),
            ],
          ),
        );

        if (shouldDelete != true) return;

        for (var order in pendingOrders) {
          await widget.repository.deletePendingOrder(order.id);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur lors de la vérification des commandes : $e"),
            backgroundColor: Colors.red));
      }
      return;
    }

    setState(() => _isClosing = true);

    try {
      await widget.repository.closeTillSession(
        sessionId: widget.session.id,
        finalCash: finalCash,
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isManager = authProvider.franchiseUser?.role == 'franchisee';
      final userName = authProvider.franchiseUser?.companyName ?? "Utilisateur";
      final franchiseeId = authProvider.franchiseUser?.effectiveStoreId ?? "";

      try {
        final printerConfig =
            await widget.repository.getPrinterConfigStream(franchiseeId).first;
        final transactions = await widget.repository
            .getSessionTransactions(widget.session.id)
            .first;

        final printingService = PrintingService();
        await printingService.printZTicket(
          printerConfig: printerConfig,
          session: widget.session,
          transactions: transactions,
          declaredCash: finalCash,
          isManager: isManager,
          userName: userName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Session clôturée et ticket imprimé !"),
              backgroundColor: Colors.green));
        }
      } catch (printError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text("Session fermée mais erreur impression: $printError"),
              backgroundColor: Colors.orange));
        }
      }

      if (mounted) {
        widget.onSessionClosed();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final bool isManager = authProvider.franchiseUser?.role == 'franchisee';
    final bool isActive = !widget.session.isClosed;

    return StreamBuilder<List<Transaction>>(
      stream: widget.repository.getSessionTransactions(widget.session.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data ?? [];
        double totalSales = 0.0;
        double cashSales = 0.0;
        double cardSales = 0.0;
        double ticketSales = 0.0;

        for (var t in transactions) {
          totalSales += t.total;
          cashSales += (t.paymentMethods['Cash'] as num?)?.toDouble() ?? 0.0;
          cardSales += (t.paymentMethods['Card'] as num?)?.toDouble() ?? 0.0;
          ticketSales +=
              (t.paymentMethods['Ticket'] as num?)?.toDouble() ?? 0.0;
        }

        final theoreticalTotal = widget.session.initialCash + cashSales;
        final realTotal = widget.session.finalCash ?? 0.0;
        final discrepancy = isActive ? 0.0 : realTotal - theoreticalTotal;

        return Column(
          children: [
            // HEADER FIXE
            Container(
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isActive ? "SESSION EN COURS" : "SESSION CLÔTURÉE",
                          style: TextStyle(
                            color: isActive ? Colors.green : Colors.indigo,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('EEEE d MMMM yyyy', 'fr_FR')
                              .format(widget.session.openingTime)
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${transactions.length} commande(s)",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (isManager || !isActive)
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Chiffre d'Affaires",
                              style: TextStyle(color: Colors.grey)),
                          Text(
                            "${totalSales.toStringAsFixed(2)} €",
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w900),
                          ),
                        ])
                ],
              ),
            ),
            const Divider(height: 1),

            // CONTENU SCROLLABLE OPTIMISÉ
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Bloc 1 : Résumé et Formulaire
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isManager) ...[
                            _buildSectionTitle("Répartition des Ventes"),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                    child: _buildSummaryCard("Espèces",
                                        cashSales, Icons.money, Colors.teal)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: _buildSummaryCard(
                                        "Carte Bancaire",
                                        cardSales,
                                        Icons.credit_card,
                                        Colors.blue)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: _buildSummaryCard(
                                        "Tickets Resto",
                                        ticketSales,
                                        Icons.receipt_long,
                                        Colors.orange)),
                              ],
                            ),
                            const SizedBox(height: 32),
                          ],
                          if (isActive) ...[
                            _buildSectionTitle("Clôture de Caisse"),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isManager)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildInfoRow(
                                              "Fond de caisse initial",
                                              widget.session.initialCash),
                                        ),
                                        Expanded(
                                          child: _buildInfoRow(
                                              "Espèces encaissées", cashSales),
                                        ),
                                        Expanded(
                                          child: _buildInfoRow(
                                              "Total Théorique",
                                              theoreticalTotal,
                                              isBold: true),
                                        ),
                                      ],
                                    )
                                  else
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 20),
                                      child: Text(
                                        "⚠️ CLÔTURE AVEUGLE : Veuillez compter le contenu exact du tiroir-caisse sans indicatif.",
                                        style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  const Divider(height: 32),
                                  const Text("Comptage du Tiroir Caisse",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _finalCashController,
                                          decoration: const InputDecoration(
                                            labelText:
                                                "Montant réel en caisse (€)",
                                            border: OutlineInputBorder(),
                                            prefixIcon:
                                                Icon(Icons.attach_money),
                                          ),
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}')),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                          child: SizedBox(
                                        height: 56,
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              _isClosing ? null : _closeSession,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                          icon: _isClosing
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white))
                                              : const Icon(Icons.lock),
                                          label: const Text(
                                              "VALIDER LA CLÔTURE",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ))
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ] else ...[
                            _buildSectionTitle("Bilan de Caisse"),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: _buildInfoRow("Fond Final Déclaré",
                                          widget.session.finalCash ?? 0.0,
                                          isBold: true)),
                                  if (isManager) ...[
                                    Container(
                                        width: 1,
                                        height: 40,
                                        color: Colors.grey.shade300),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          const Text("Écart Constaté",
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                          const SizedBox(height: 4),
                                          Text(
                                            "${discrepancy > 0 ? '+' : ''}${discrepancy.toStringAsFixed(2)} €",
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: discrepancy.abs() < 0.05
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          _buildSectionTitle("Détail des Transactions"),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),

                  // Bloc 2 : Liste des transactions (Optimisée avec SliverList)
                  SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final tx = transactions[index];
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey.shade100,
                                child: _getPaymentIcon(tx.paymentMethods,
                                    size: 18, color: Colors.grey.shade700),
                              ),
                              title: Text(
                                  "Ticket #${tx.id.substring(0, 6)} - ${DateFormat('HH:mm').format(tx.timestamp)}"),
                              subtitle: Text("${tx.items.length} articles"),
                              trailing: Text(
                                "${tx.total.toStringAsFixed(2)} €",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              onTap: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    TransactionDetailDialog(transaction: tx),
                              ),
                            ),
                          );
                        },
                        childCount: transactions.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildSummaryCard(
      String label, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          Text("${amount.toStringAsFixed(2)} €",
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, double amount, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          "${amount.toStringAsFixed(2)} €",
          style: TextStyle(
              fontSize: 18,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: Colors.black87),
        ),
      ],
    );
  }

  Icon _getPaymentIcon(Map<String, dynamic> methods,
      {double size = 20, Color? color}) {
    if (methods.keys.length > 1) {
      return Icon(Icons.splitscreen, color: color, size: size);
    }
    if (methods.containsKey('Cash')) {
      return Icon(Icons.money, color: color, size: size);
    }
    if (methods.containsKey('Card')) {
      return Icon(Icons.credit_card, color: color, size: size);
    }
    return Icon(Icons.payment, size: size, color: color);
  }
}

// ---------------------------------------------------------------------------
// VIEW : PendingOrdersView
// ---------------------------------------------------------------------------
class PendingOrdersView extends StatefulWidget {
  final String franchiseeId;

  const PendingOrdersView({super.key, required this.franchiseeId});

  @override
  State<PendingOrdersView> createState() => _PendingOrdersViewState();
}

class _PendingOrdersViewState extends State<PendingOrdersView> {
  final FranchiseRepository _repository = FranchiseRepository();
  PendingOrder? _selectedOrder;
  bool _isProcessing = false;

  Future<Map<String, MasterProduct>> _fetchAllProductsForOrder(
      PendingOrder order) async {
    final firestore = FirebaseFirestore.instance;
    final Set<String> allProductIds = {};

    for (var itemMap in order.itemsAsMap) {
      if (itemMap['masterProductId'] is String) {
        allProductIds.add(itemMap['masterProductId']);
      }
      if (itemMap['selectedOptions'] is List) {
        for (var optionMap in (itemMap['selectedOptions'] as List)) {
          if (optionMap is Map<String, dynamic> && optionMap['items'] is List) {
            for (var sectionItemMap in (optionMap['items'] as List)) {
              if (sectionItemMap is Map<String, dynamic> &&
                  sectionItemMap['masterProductId'] is String) {
                allProductIds.add(sectionItemMap['masterProductId']);
              }
            }
          }
        }
      }
    }

    if (allProductIds.isEmpty) return {};

    final Map<String, MasterProduct> productMap = {};
    final List<String> idList = allProductIds.toList();

    for (var i = 0; i < idList.length; i += 30) {
      final sublist = idList.skip(i).take(30).toList();
      if (sublist.isNotEmpty) {
        final productsSnapshot = await firestore
            .collection('master_products')
            .where(FieldPath.documentId, whereIn: sublist)
            .get();
        for (var doc in productsSnapshot.docs) {
          productMap[doc.id] = MasterProduct.fromFirestore(doc.data(), doc.id);
        }
      }
    }
    return productMap;
  }

  CartItem? _reconstructCartItem(
      Map<String, dynamic> itemMap, Map<String, MasterProduct> productMap) {
    final product = productMap[itemMap['masterProductId']];
    if (product == null) return null;

    final Map<String, List<SectionItem>> selectedOptions = {};
    if (itemMap['selectedOptions'] is List) {
      for (var optionMap in (itemMap['selectedOptions'] as List)) {
        if (optionMap is Map<String, dynamic>) {
          final sectionId = optionMap['sectionId'] as String?;
          final sectionItemsList = optionMap['items'] as List?;

          if (sectionId != null && sectionItemsList != null) {
            final List<SectionItem> sectionItems = [];
            for (var sectionItemMap in sectionItemsList) {
              if (sectionItemMap is Map<String, dynamic>) {
                final optionProductId =
                    sectionItemMap['masterProductId'] as String?;
                final optionProduct = productMap[optionProductId];
                if (optionProduct != null) {
                  sectionItems.add(SectionItem(
                    product: optionProduct,
                    supplementPrice: (sectionItemMap['supplementPrice'] as num?)
                            ?.toDouble() ??
                        0.0,
                  ));
                }
              }
            }
            if (sectionItems.isNotEmpty) {
              selectedOptions[sectionId] = sectionItems;
            }
          }
        }
      }
    }

    final cartItem = CartItem(
      product: product,
      price: (itemMap['basePrice'] as num?)?.toDouble() ?? 0.0,
      vatRate: (itemMap['vatRate'] as num?)?.toDouble() ?? 10.0,
      selectedOptions: selectedOptions,
      removedIngredientProductIds:
          List<String>.from(itemMap['removedIngredientProductIds'] ?? []),
      removedIngredientNames:
          List<String>.from(itemMap['removedIngredientNames'] ?? []),
    );
    cartItem.isSentToKitchen = itemMap['isSentToKitchen'] ?? false;
    return cartItem;
  }

  Future<void> _handleResumeOrder(PendingOrder order) async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (cart.items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Le panier n'est pas vide"),
          content: const Text("Voulez-vous écraser le panier actuel ?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Non")),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Oui")),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isProcessing = true);
    try {
      final productMap = await _fetchAllProductsForOrder(order);
      final List<CartItem> reconstructedItems = [];

      for (var itemMap in order.itemsAsMap) {
        final cItem = _reconstructCartItem(itemMap, productMap);
        if (cItem != null) reconstructedItems.add(cItem);
      }

      OrderType typeToSet = OrderType.onSite;
      final String t = order.orderType.toLowerCase();
      if (t.contains('take') ||
          t.contains('away') ||
          t.contains('emporter')) {
        typeToSet = OrderType.takeaway;
      }

      cart.loadCart(reconstructedItems, order.identifier,
          type: typeToSet, source: order.source);

      await _repository.deletePendingOrder(order.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Commande chargée !"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDeleteOrder(PendingOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: const Text("Cette action est irréversible."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Non")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Oui", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        await _repository.deletePendingOrder(order.id);
        if (_selectedOrder?.id == order.id) {
          setState(() => _selectedOrder = null);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Erreur: $e")));
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFF5F7FA);
    final activeColor = Colors.orange.shade800;

    return Dialog(
      backgroundColor: bgColor,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.90,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.pause_circle_filled,
                          color: activeColor, size: 32),
                      const SizedBox(width: 12),
                      const Text("Commandes en Attente",
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(
                      icon: const Icon(Icons.close, size: 32),
                      onPressed: () => Navigator.pop(context))
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<PendingOrder>>(
                stream: _repository.getPendingOrdersStream(widget.franchiseeId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final orders = snapshot.data ?? [];
                  if (orders.isEmpty) {
                    return Center(
                        child: Text("Aucune commande en attente",
                            style: TextStyle(
                                fontSize: 20, color: Colors.grey.shade500)));
                  }

                  if (_selectedOrder == null && orders.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _selectedOrder = orders.first);
                      }
                    });
                  } else if (_selectedOrder != null &&
                      !orders.any((o) => o.id == _selectedOrder!.id)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedOrder = null);
                    });
                  }

                  return Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Container(
                          color: Colors.white,
                          child: ListView.builder(
                            itemCount: orders.length,
                            itemBuilder: (context, index) {
                              final order = orders[index];
                              return _buildListTile(order,
                                  _selectedOrder?.id == order.id, activeColor);
                            },
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(
                        flex: 6,
                        child: _selectedOrder == null
                            ? const Center(
                                child: Text("Sélectionnez une commande"))
                            : _buildDetailPanel(_selectedOrder!, activeColor),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(
      PendingOrder order, bool isSelected, Color activeColor) {
    final diff = DateTime.now().difference(order.timestamp);
    String timeAgo =
        diff.inMinutes < 60 ? "${diff.inMinutes} min" : "${diff.inHours} h";
    IconData sourceIcon = Icons.point_of_sale;
    if (order.source == 'borne') sourceIcon = Icons.touch_app;

    return InkWell(
      onTap: () => setState(() => _selectedOrder = order),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.08) : Colors.white,
          border: Border(
              left: BorderSide(
                  color: isSelected ? activeColor : Colors.transparent,
                  width: 6),
              bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.identifier,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? activeColor : Colors.black87)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(sourceIcon, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(timeAgo,
                        style: TextStyle(
                            color: isSelected ? activeColor : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ],
                )
              ],
            ),
            Text("${order.total.toStringAsFixed(2)} €",
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(Map<String, dynamic> itemMap) {
    final name = itemMap['name'] ?? 'Produit inconnu';
    final quantity = itemMap['quantity'] ?? 1;
    final basePrice = (itemMap['basePrice'] as num?)?.toDouble() ?? 0.0;
    final optionsGroups = itemMap['selectedOptions'] as List<dynamic>? ?? [];
    final removedIngredients = List<String>.from(itemMap['removedIngredientNames'] ?? []);

    double unitPrice = basePrice;
    if (optionsGroups.isNotEmpty) {
      for (var group in optionsGroups) {
        if (group['items'] is List) {
          for (var opt in (group['items'] as List)) {
            unitPrice += (opt['supplementPrice'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    }
    final totalItem = unitPrice * quantity;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- LIGNE PRINCIPALE (Comme dans CartPanel) ---
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("${quantity}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Text("${totalItem.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),

          // --- OPTIONS REGROUPÉES (Style POS Wrap) ---
          if (optionsGroups.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...optionsGroups.map((group) {
              final items = (group['items'] as List<dynamic>? ?? []);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 4, left: 8),
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.black12, width: 0.5))
                ),
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 2.0,
                  children: items.map((opt) {
                    final optName = opt['name'] ?? 'Option';
                    final optPrice = (opt['supplementPrice'] as num?)?.toDouble() ?? 0.0;

                    // Construction du texte identique au CartPanel
                    String displayText = "+ $optName";
                    if (optPrice > 0) {
                      displayText += " (${optPrice.toStringAsFixed(2)}€)";
                    }

                    return Text(
                        displayText,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500
                        )
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ],

          // --- SANS (Style POS) ---
          if (removedIngredients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0, left: 8),
              child: Text(
                removedIngredients.map((n) => "🚫 Sans $n").join(", "),
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold
                ),
              ),
            ),
        ],
      ),
    );
  }
  Widget _buildDetailPanel(PendingOrder order, Color activeColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Total en attente",
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text("${order.total.toStringAsFixed(2)} €",
                      style: TextStyle(
                          color: activeColor,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(DateFormat('HH:mm').format(order.timestamp),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 20)),
                  Text(DateFormat('dd/MM/yyyy').format(order.timestamp),
                      style: const TextStyle(color: Colors.grey)),
                ],
              )
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: const Color(0xFFF9FAFB),
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: order.itemsAsMap.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = order.itemsAsMap[index];
                return _buildDetailItem(item);
              },
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5))
          ]),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 60,
                  child: OutlinedButton(
                    onPressed:
                        _isProcessing ? null : () => _handleDeleteOrder(order),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side:
                            const BorderSide(color: Colors.redAccent, width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Icon(Icons.delete_outline, size: 28),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isProcessing ? null : () => _handleResumeOrder(order),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.play_arrow, size: 28),
                    label: Text(_isProcessing ? "CHARGEMENT..." : "REPRENDRE",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}
