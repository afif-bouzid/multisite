import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:ouiborne/views/franchisee/session_details_view.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';
import '../../../core/services/printing_service.dart';
import '../../back_office/views/franchisee/shared/transaction_dialogs.dart';
import '../../back_office/views/franchisee/stats/accounting_view.dart';
import '../../back_office/views/franchisee/stats/stats_dashboard.dart';

class FranchiseeStatsView extends StatefulWidget {
  const FranchiseeStatsView({super.key});

  @override
  State<FranchiseeStatsView> createState() => _FranchiseeStatsViewState();
}

class _FranchiseeStatsViewState extends State<FranchiseeStatsView> {
  DateTime? _startDate;
  DateTime? _endDate;
  TillSession? _selectedSession;
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

    // Rôle : 'franchisee' = Manager, 'employee' = Équipier
    final bool isManager = authProvider.franchiseUser?.role == 'franchisee';
    final franchiseeId = authProvider.franchiseUser!.effectiveStoreId;

    // Si employé, accès restreint au premier onglet seulement
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
          physics: const NeverScrollableScrollPhysics(),
          // Évite le swipe accidentel
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
        // LISTE DES SESSIONS (GAUCHE)
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
        // DÉTAIL SESSION (DROITE)
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

        // Seul le manager peut voir l'historique filtré par dates
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
    // Note : On garde la logique visuelle 'isSelected' même si on change de page,
    // ou vous pouvez la retirer si vous ne voulez plus surligner la ligne au retour.
    final isSelected = _selectedSession?.id == session.id;

    // Formatage des dates pour l'affichage
    final dateStr = DateFormat('dd MMM yyyy').format(session.openingTime);
    final timeStr = DateFormat('HH:mm').format(session.openingTime);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SessionDetailsView(
              session: session,
            ),
          ),
        );
      },
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
            // --- Icône à gauche (Caisse ou Historique) ---
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

            // --- Textes (Titre + Date) ---
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

            // --- Flèche à droite ---
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

// --- DÉTAIL DE SESSION & LOGIQUE DE CLÔTURE ---

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

  @override
  void dispose() {
    _finalCashController.dispose();
    super.dispose();
  }

  // --- CORRECTION : Méthode d'arrondi financier ---
  double _round(double val) {
    return (val * 100).roundToDouble() / 100;
  }

  Future<void> _closeSession() async {
    final finalCash =
        double.tryParse(_finalCashController.text.replaceAll(',', '.'));
    if (finalCash == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Montant invalide"), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isClosing = true);
    try {
      // 1. Fermer la session en BDD
      await widget.repository.closeTillSession(
        sessionId: widget.session.id,
        finalCash: finalCash,
      );

      // 2. Préparation Impression
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

        // --- Vérifiez que cette méthode existe bien dans printing_service.dart ---
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

        // --- CALCULS SÉCURISÉS ---
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

        // Arrondi final pour affichage
        totalSales = _round(totalSales);
        cashSales = _round(cashSales);
        cardSales = _round(cardSales);
        ticketSales = _round(ticketSales);

        final theoreticalTotal = _round(widget.session.initialCash + cashSales);
        final realTotal = widget.session.finalCash ?? 0.0;
        // L'écart n'est pertinent que si la session est fermée ou si on compare en temps réel
        final discrepancy =
            isActive ? 0.0 : _round(realTotal - theoreticalTotal);

        return Column(
          children: [
            // HEADER STATS
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
                  // Afficher le CA si manager ou session fermée
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

            // CONTENU PRINCIPAL SCROLLABLE
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // RÉPARTITION DES VENTES (MANAGER)
                    if (isManager) ...[
                      _buildSectionTitle("Répartition des Ventes"),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                              child: _buildSummaryCard("Espèces", cashSales,
                                  Icons.money, Colors.teal)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _buildSummaryCard("Carte Bancaire",
                                  cardSales, Icons.credit_card, Colors.blue)),
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

                    // ZONE DE CLÔTURE
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
                                        "Total Théorique", theoreticalTotal,
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
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _finalCashController,
                                    decoration: const InputDecoration(
                                      labelText: "Montant réel en caisse (€)",
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.attach_money),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
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
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Icon(Icons.lock),
                                    label: const Text("VALIDER LA CLÔTURE",
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
                      // AFFICHAGE RÉSULTAT CLÔTURE
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
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text("Écart Constaté",
                                        style: TextStyle(color: Colors.grey)),
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

                    // LISTE TRANSACTIONS
                    _buildSectionTitle("Détail des Transactions"),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: transactions.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final tx = transactions[index];
                          // Formatage de l'heure
                          final timeStr =
                              DateFormat('HH:mm').format(tx.timestamp);
                          // Identifier ou ID court
                          final displayId = tx.identifier.isNotEmpty
                              ? tx.identifier
                              : "#${tx.id.substring(0, 6)}";

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade100,
                              child: _getPaymentIcon(tx.paymentMethods,
                                  size: 18, color: Colors.grey.shade700),
                            ),
                            title: Text("$displayId - $timeStr"),
                            subtitle: Text("${tx.items.length} articles"),
                            trailing: Text(
                              "${tx.total.toStringAsFixed(2)} €",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  TransactionDetailDialog(transaction: tx),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
    if (methods.containsKey('Ticket')) {
      return Icon(Icons.receipt_long, color: color, size: size);
    }
    return Icon(Icons.payment, size: size, color: color);
  }
}
