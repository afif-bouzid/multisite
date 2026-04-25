import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ouiborne/core/repository/repository.dart';
import 'package:ouiborne/core/auth_provider.dart';
import 'package:ouiborne/models.dart' as model;

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION GLOBALE
// ─────────────────────────────────────────────────────────────────────────────

enum DateFilter { today, yesterday, thisWeek, custom }

const kDarkBg = Color(0xFF0F172A);
const kCardBg = Color(0xFF1E293B);
const kAccentColor = Colors.indigoAccent;
const int kBusinessDayStartHour = 5;

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET PRINCIPAL : MOBILE STATS VIEW
// ─────────────────────────────────────────────────────────────────────────────

class MobileStatsView extends StatefulWidget {
  const MobileStatsView({super.key});

  @override
  State<MobileStatsView> createState() => _MobileStatsViewState();
}

class _MobileStatsViewState extends State<MobileStatsView> with TickerProviderStateMixin {
  final _repository = FranchiseRepository();
  DateFilter _currentFilter = DateFilter.today;
  late DateTimeRange _selectedRange;

  // Futures pour bloquer les coûts Firebase
  Future<List<model.Transaction>>? _historicalFuture;
  Future<List<model.TillSession>>? _historySessionsFuture;

  bool _isLoadingFilter = false;
  bool _isExporting = false;
  String _globalSearchQuery = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
      if (user != null) {
        final storeId = (user.storeId?.isNotEmpty ?? false) ? user.storeId! : user.uid;
        _applyFilter(DateFilter.today, storeId);
      }
    });
  }

  DateTime _getBusinessDate(DateTime date) {
    if (date.hour < kBusinessDayStartHour) {
      return date.subtract(const Duration(days: 1));
    }
    return date;
  }

  void _applyFilter(DateFilter filter, String storeId) async {
    setState(() => _isLoadingFilter = true);
    final now = DateTime.now();
    final businessNow = _getBusinessDate(now);

    DateTime start;
    DateTime end;

    switch (filter) {
      case DateFilter.today:
        start = DateTime(businessNow.year, businessNow.month, businessNow.day, kBusinessDayStartHour, 0, 0);
        end = DateTime(businessNow.year, businessNow.month, businessNow.day + 1, kBusinessDayStartHour - 1, 59, 59);
        break;
      case DateFilter.yesterday:
        final yest = businessNow.subtract(const Duration(days: 1));
        start = DateTime(yest.year, yest.month, yest.day, kBusinessDayStartHour, 0, 0);
        end = DateTime(yest.year, yest.month, yest.day + 1, kBusinessDayStartHour - 1, 59, 59);
        break;
      case DateFilter.thisWeek:
        start = businessNow.subtract(Duration(days: businessNow.weekday - 1));
        start = DateTime(start.year, start.month, start.day, kBusinessDayStartHour, 0, 0);
        end = DateTime(businessNow.year, businessNow.month, businessNow.day + 1, kBusinessDayStartHour - 1, 59, 59);
        break;
      case DateFilter.custom:
        final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: now,
            builder: (context, child) => Theme(data: ThemeData.dark(), child: child!));
        if (picked != null) {
          final diff = picked.end.difference(picked.start).inDays;
          if (diff > 31) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Limité à 31 jours pour protéger vos coûts serveurs."), backgroundColor: Colors.redAccent));
            setState(() => _isLoadingFilter = false);
            return;
          }
          start = DateTime(picked.start.year, picked.start.month, picked.start.day, kBusinessDayStartHour, 0, 0);
          end = DateTime(picked.end.year, picked.end.month, picked.end.day + 1, kBusinessDayStartHour - 1, 59, 59);
        } else {
          setState(() => _isLoadingFilter = false);
          return;
        }
        break;
    }

    setState(() {
      _currentFilter = filter;
      _selectedRange = DateTimeRange(start: start, end: end);
      _globalSearchQuery = "";

      _historicalFuture = _repository.getTransactionsInDateRange(storeId, startDate: start, endDate: end).first;
      // On utilise la méthode du repository (comme sur la caisse) mais en Future (1 seule lecture)
      _historySessionsFuture = _repository.getFranchiseeSessions(storeId, startDate: start, endDate: end).first;

      _isLoadingFilter = false;
    });
  }

  Future<void> _launchPospixel() async {
    final Uri url = Uri.parse('https://pospixel.mespaiements.fr/');
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleSignOut(BuildContext context) async {
    await Provider.of<AuthProvider>(context, listen: false).signOut();
    if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _openSessionDetailModal(model.TillSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kDarkBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => MobileSessionDetailModal(session: session, repository: _repository),
    );
  }

  Future<void> _exportPdf(BuildContext context, model.FranchiseUser user, String storeId) async {
    setState(() => _isExporting = true);
    try {
      final txs = await _historicalFuture ?? [];
      final stats = AdvancedStatsSummary(txs);
      String compName = user.companyName ?? "Société";
      String siret = "", tva = "", address = user.address ?? "", zip = "";
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(storeId).get();
        if (doc.exists && doc.data() != null) {
          final d = doc.data()!;
          siret = d['siret']?.toString() ?? "";
          tva = d['tvaNumber']?.toString() ?? d['vatNumber']?.toString() ?? "";
          address = d['address']?.toString() ?? address;
          zip = "${d['zipCode'] ?? ''} ${d['city'] ?? ''}".trim();
        }
      } catch (_) {}
      await StatsPdfExporter.generateAndSharePdf(stats: stats, companyName: compName, restaurantName: user.restaurantName ?? "Restaurant", address: address, zipCity: zip, phone: user.phone ?? "", siret: siret, tvaNumber: tva, startDate: _selectedRange.start, endDate: _selectedRange.end);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).franchiseUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final storeId = (user.storeId?.isNotEmpty ?? false) ? user.storeId! : user.uid;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: kDarkBg,
        appBar: AppBar(
          backgroundColor: kDarkBg,
          elevation: 0,
          title: Text(user.restaurantName?.toUpperCase() ?? "TABLEAU DE BORD", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          actions: [
            IconButton(icon: const Icon(Icons.language, color: Colors.amber, size: 20), onPressed: _launchPospixel, tooltip: 'Pospixel'),
            IconButton(icon: const Icon(Icons.logout, color: Colors.white54, size: 20), onPressed: () => _handleSignOut(context)),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            isScrollable: true,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
            tabs: [
              Tab(text: "SESSION LIVE"),
              Tab(text: "Z DE CAISSE (STATS)"),
              Tab(text: "SESSIONS D'OUVERTURE / FERMETURE"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLiveTab(storeId),
            _buildHistoricalTab(storeId, user),
            _buildSessionsAndTicketsTab(storeId),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ONGLET 1 : SESSION LIVE (INTACT)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLiveTab(String storeId) {
    return StreamBuilder<model.TillSession?>(
      stream: _repository.getActiveSession(storeId),
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock, size: 48, color: Colors.white24),
                SizedBox(height: 16),
                Text("CAISSE FERMÉE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 18)),
                Text("Ouvrez une session depuis la caisse.", style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          );
        }

        return StreamBuilder<List<model.Transaction>>(
          stream: _repository.getSessionTransactions(session.id),
          builder: (context, txSnap) {
            final txs = txSnap.data ?? [];
            final stats = AdvancedStatsSummary(txs);
            final duration = DateTime.now().difference(session.openingTime);
            final theoretical = session.initialCash + (stats.payments['Espèces'] ?? 0);

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withOpacity(0.3))),
                    child: Row(
                      children: [
                        const PulseDot(color: Colors.greenAccent),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text("SESSION EN COURS", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text("Ouverte depuis ${DateFormat('HH:mm').format(session.openingTime)} (${duration.inHours}h${duration.inMinutes % 60}m)", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ])),
                        ElevatedButton(
                          onPressed: () => _openSessionDetailModal(session),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.2), foregroundColor: Colors.greenAccent, elevation: 0),
                          child: const Text("DÉTAILS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        )
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MetricCard(
                      title: "CHIFFRE D'AFFAIRES SESSION",
                      value: "${stats.caTotal.toStringAsFixed(2)} €",
                      subtitle: "${txs.length} commandes traitées depuis l'ouverture",
                      icon: Icons.point_of_sale,
                      color: Colors.greenAccent,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("RYTHME D'ACTIVITÉ", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
                        const SizedBox(height: 20),
                        HourlyChart(stats: stats),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.only(left: 8, bottom: 12), child: Text("DÉTAIL DES ENCAISSEMENTS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1))),
                        Row(children: [
                          Expanded(child: MetricCard(title: "CB BORNE", value: "${(stats.payments['CB Borne'] ?? 0).toStringAsFixed(2)}€", subtitle: "", icon: Icons.touch_app, color: Colors.tealAccent, small: true)),
                          const SizedBox(width: 12),
                          Expanded(child: MetricCard(title: "CB COMPTOIR", value: "${(stats.payments['CB Comptoir'] ?? 0).toStringAsFixed(2)}€", subtitle: "", icon: Icons.credit_card, color: Colors.indigoAccent, small: true)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: MetricCard(title: "TICKET RESTO", value: "${(stats.payments['Tickets Resto'] ?? 0).toStringAsFixed(2)}€", subtitle: "", icon: Icons.restaurant, color: Colors.orangeAccent, small: true)),
                          const SizedBox(width: 12),
                          Expanded(child: MetricCard(title: "ESPÈCES CASH", value: "${(stats.payments['Espèces'] ?? 0).toStringAsFixed(2)}€", subtitle: "Théorique: ${theoretical.toStringAsFixed(2)}€", icon: Icons.payments, color: Colors.amberAccent, small: true)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ONGLET 2 : Z DE CAISSE HISTORIQUE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHistoricalTab(String storeId, model.FranchiseUser user) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<model.Transaction>>(
        future: _historicalFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _isLoadingFilter) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final allTxs = snapshot.data ?? [];
          final stats = AdvancedStatsSummary(allTxs);

          return RefreshIndicator(
            onRefresh: () async => _applyFilter(_currentFilter, storeId),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildFilterBar(storeId)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]), borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        children: [
                          const Text("CHIFFRE D'AFFAIRES TTC", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          const SizedBox(height: 8),
                          Text("${stats.caTotal.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(height: 6),
                          Text("${stats.count} tickets  ·  Panier moyen ${stats.panierMoyen.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("ORIGINE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                                const SizedBox(height: 12),
                                _statRow("Borne (${stats.borneCount})", stats.borneCA),
                                _statRow("Caisse (${stats.caisseCount})", stats.caisseCA),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("TYPE DE SERVICE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                                const SizedBox(height: 12),
                                _statRow("Sur Place (${stats.surPlaceCount})", stats.surPlaceCA),
                                _statRow("À Emporter (${stats.emporterCount})", stats.emporterCA),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("MÉTHODES D'ENCAISSEMENT", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                                const SizedBox(height: 12),
                                _statRow("CB Borne", stats.payments['CB Borne']),
                                _statRow("CB Comptoir", stats.payments['CB Comptoir']),
                                _statRow("Espèces", stats.payments['Espèces']),
                                _statRow("Ticket Resto", stats.payments['Tickets Resto']),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("TVA COLLECTÉE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                                const SizedBox(height: 12),
                                _statRow("5.5%", stats.tvaBreakdown['5.5%']),
                                _statRow("10%", stats.tvaBreakdown['10%']),
                                _statRow("20%", stats.tvaBreakdown['20%']),
                                const Divider(color: Colors.white12),
                                Text("${stats.tvaTotal.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          collapsedIconColor: Colors.white54,
                          iconColor: Colors.indigoAccent,
                          title: const Text("PRODUITS VENDUS (PALMARÈS)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          children: [
                            if (stats.productQty.isEmpty)
                              const Padding(padding: EdgeInsets.all(16), child: Text("Aucun produit vendu.", style: TextStyle(color: Colors.white38))),
                            ...stats.sortedProductsByQty.take(50).map((e) {
                              final revenue = stats.productCA[e.key] ?? 0.0;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                      child: Text("${e.value}x", style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text("${revenue.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isExporting ? null : () => _exportPdf(context, user, storeId),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        icon: _isExporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Icon(Icons.picture_as_pdf, size: 18),
        label: Text(_isExporting ? "GÉNÉRATION..." : "RAPPORT PDF", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ONGLET 3 : LISTE DES SESSIONS ET TICKETS (REFONTE EXACTE CAISSE)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSessionsAndTicketsTab(String storeId) {
    return FutureBuilder(
      future: Future.wait([
        _historicalFuture ?? Future.value(<model.Transaction>[]),
        _historySessionsFuture ?? Future.value(<model.TillSession>[])
      ]),
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoadingFilter) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final List<model.Transaction> allTxs = snapshot.data?[0] ?? [];
        final List<model.TillSession> historySessions = (snapshot.data?[1] ?? []).where((s) => s.isClosed).toList();

        final filteredTxs = _globalSearchQuery.isEmpty
            ? <model.Transaction>[]
            : allTxs.where((t) =>
        t.id.toLowerCase().contains(_globalSearchQuery.toLowerCase()) ||
            t.identifier.toLowerCase().contains(_globalSearchQuery.toLowerCase())
        ).toList();

        filteredTxs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        return Column(
          children: [
            _buildFilterBar(storeId),

            // BARRE DE RECHERCHE TICKETS GLOBALE
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  hintText: "Rechercher un ticket (Nom client, N°...)",
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.indigoAccent),
                  suffixIcon: _globalSearchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, color: Colors.white54), onPressed: () => setState(() => _globalSearchQuery = ""))
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _globalSearchQuery = val),
              ),
            ),

            Expanded(
                child: _globalSearchQuery.isNotEmpty
                    ? (filteredTxs.isEmpty
                    ? const Center(child: Text("Aucun ticket ne correspond.", style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                  itemCount: filteredTxs.length,
                  itemBuilder: (context, index) => _buildTransactionCard(filteredTxs[index]),
                ))
                    : StreamBuilder<model.TillSession?>(
                  stream: _repository.getActiveSession(storeId),
                  builder: (context, activeSnapshot) {
                    final activeSession = activeSnapshot.data;

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        if (activeSession != null) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Text("SESSION EN COURS (À CLÔTURER)", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
                          ),
                          _buildSessionListTile(activeSession, isActive: true),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(color: Colors.white12)),
                        ],

                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text("HISTORIQUE DES SESSIONS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
                        ),

                        if (historySessions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(child: Text("Aucune session clôturée sur cette période.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38))),
                          )
                        else
                          ...historySessions.map((s) => _buildSessionListTile(s, isActive: false)),
                      ],
                    );
                  },
                )
            ),
          ],
        );
      },
    );
  }

  // TUILE DE SESSION FAÇON CAISSE
  Widget _buildSessionListTile(model.TillSession session, {required bool isActive}) {
    final dateStr = DateFormat('dd MMM yyyy', 'fr_FR').format(session.openingTime);
    final timeStr = DateFormat('HH:mm').format(session.openingTime);

    return InkWell(
      onTap: () => _openSessionDetailModal(session),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.greenAccent.withOpacity(0.05) : kCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? Colors.greenAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive ? Colors.greenAccent.withOpacity(0.1) : Colors.indigoAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isActive ? Icons.point_of_sale : Icons.history, color: isActive ? Colors.greenAccent : Colors.indigoAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? "Session Active" : "Clôture du $dateStr",
                    style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.greenAccent : Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isActive ? "Ouverte à $timeStr" : "Fermée à ${session.closingTime != null ? DateFormat('HH:mm').format(session.closingTime!) : '?'}",
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS UI
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterBar(String storeId) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _filterBtn("Aujourd'hui", DateFilter.today, storeId),
            _filterBtn("Hier", DateFilter.yesterday, storeId),
            _filterBtn("Cette semaine", DateFilter.thisWeek, storeId),
            _filterBtn("Personnalisé...", DateFilter.custom, storeId, icon: Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  Widget _filterBtn(String label, DateFilter filter, String storeId, {IconData? icon}) {
    final active = _currentFilter == filter;
    return GestureDetector(
      onTap: () => _applyFilter(filter, storeId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.white : Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: active ? Colors.black : Colors.white54), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: active ? Colors.black : Colors.white60, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, double? amount) {
    final val = amount ?? 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text("${val.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // TUILE DE TRANSACTION AVEC BADGES
  Widget _buildTransactionCard(model.Transaction tx) {
    final primaryColor = _getPrimaryPaymentColor(tx);
    final shortId = tx.id.length >= 6 ? tx.id.substring(0, 6) : tx.id;
    final mainTitle = tx.identifier.isNotEmpty ? tx.identifier : "Ticket #$shortId";

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.white.withOpacity(0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: primaryColor.withOpacity(0.1),
          child: _getPaymentIcon(tx, size: 20, color: primaryColor),
        ),
        title: Text("$mainTitle - ${DateFormat('HH:mm').format(tx.timestamp)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: _buildPaymentChips(tx),
        ),
        trailing: Text("${tx.total.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
        onTap: () => showDialog(context: context, builder: (_) => TransactionDetailsDialog(transaction: tx)),
      ),
    );
  }

  Color _getPrimaryPaymentColor(model.Transaction t) {
    if (t.paymentMethods.keys.length > 1) return Colors.blueGrey;
    final key = t.paymentMethods.keys.first;
    if (key == 'Cash') return Colors.greenAccent;
    if (key == 'Card_Kiosk') return Colors.tealAccent;
    if (key == 'Ticket') return Colors.orangeAccent;
    bool isBorne = false;
    try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    return isBorne ? Colors.tealAccent : Colors.indigoAccent;
  }

  Icon _getPaymentIcon(model.Transaction t, {double size = 20, Color? color}) {
    if (t.paymentMethods.keys.length > 1) return Icon(Icons.call_split, color: color, size: size);
    final key = t.paymentMethods.keys.first;
    if (key == 'Cash') return Icon(Icons.payments, color: color, size: size);
    if (key == 'Ticket') return Icon(Icons.restaurant, color: color, size: size);
    bool isBorne = false;
    try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    return Icon(isBorne ? Icons.touch_app : Icons.point_of_sale, color: color, size: size);
  }

  Widget _buildPaymentChips(model.Transaction t) {
    final methods = t.paymentMethods.keys.toList();
    final bool isMixte = methods.length > 1;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (isMixte) _chipBadge("MIXTE", Colors.blueGrey),
        ...methods.map((key) {
          String label = key;
          Color c = Colors.grey;
          if (key == 'Cash') { label = 'ESPECES'; c = Colors.greenAccent; }
          else if (key == 'Card_Kiosk') { label = 'CB BORNE'; c = Colors.tealAccent; }
          else if (key == 'Card_Counter') { label = 'CB COMPTOIR'; c = Colors.indigoAccent; }
          else if (key == 'Ticket') { label = 'TICKET RESTO'; c = Colors.orangeAccent; }
          else if (key == 'Card') {
            bool isBorne = false;
            try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
            label = isBorne ? 'CB BORNE' : 'CB COMPTOIR';
            c = isBorne ? Colors.tealAccent : Colors.indigoAccent;
          }
          return _chipBadge(label, c);
        }),
      ],
    );
  }

  Widget _chipBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODALE INTERACTIVE DE DÉTAIL DE SESSION (EXACTEMENT COMME LA CAISSE)
// ─────────────────────────────────────────────────────────────────────────────

class MobileSessionDetailModal extends StatefulWidget {
  final model.TillSession session;
  final FranchiseRepository repository;

  const MobileSessionDetailModal({super.key, required this.session, required this.repository});

  @override
  State<MobileSessionDetailModal> createState() => _MobileSessionDetailModalState();
}

class _MobileSessionDetailModalState extends State<MobileSessionDetailModal> {
  String _activeFilter = 'Toutes';

  bool _matchesFilter(model.Transaction tx) {
    if (_activeFilter == 'Toutes') return true;
    final methods = tx.paymentMethods.keys;
    final bool isMixte = methods.length > 1;

    if (_activeFilter == 'Mixtes') return isMixte;
    if (_activeFilter == 'Bornes') {
      return tx.paymentMethods.containsKey('Card_Kiosk') || (tx.paymentMethods.containsKey('Card') && (tx as dynamic).source == 'borne');
    }
    if (_activeFilter == 'Comptoir') {
      return tx.paymentMethods.containsKey('Card_Counter') || (tx.paymentMethods.containsKey('Card') && (tx as dynamic).source != 'borne');
    }
    if (_activeFilter == 'Cash') return tx.paymentMethods.containsKey('Cash');
    if (_activeFilter == 'TR') return tx.paymentMethods.containsKey('Ticket');

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = !widget.session.isClosed;

    return DraggableScrollableSheet(
      initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<List<model.Transaction>>(
          stream: widget.repository.getSessionTransactions(widget.session.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
            final allTransactions = snapshot.data ?? [];
            final filteredTransactions = allTransactions.where(_matchesFilter).toList();
            filteredTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

            double totalSales = 0.0, cashSales = 0.0, cbKioskSales = 0.0, cbCounterSales = 0.0, ticketSales = 0.0;

            for (var t in allTransactions) {
              totalSales += t.total;
              t.paymentMethods.forEach((method, amount) {
                double val = (amount as num).toDouble();
                if (method == 'Card_Kiosk') cbKioskSales += val;
                else if (method == 'Card_Counter') cbCounterSales += val;
                else if (method == 'Cash') cashSales += val;
                else if (method == 'Ticket') ticketSales += val;
                else if (method == 'Card') {
                  bool isBorne = false;
                  try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
                  if (isBorne) cbKioskSales += val;
                  else cbCounterSales += val;
                }
              });
            }

            final theoreticalTotal = widget.session.initialCash + cashSales;
            final realTotal = widget.session.finalCash ?? 0.0;
            final discrepancy = isActive ? 0.0 : realTotal - theoreticalTotal;

            return CustomScrollView(
              controller: scrollController,
              slivers: [
                // HEADER FIXE
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: kCardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isActive ? "SESSION EN COURS" : "SESSION CLÔTURÉE", style: TextStyle(color: isActive ? Colors.greenAccent : Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 8),
                              Text(DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(widget.session.openingTime).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text("${allTransactions.length} commande(s)", style: const TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("Chiffre d'Affaires", style: TextStyle(color: Colors.white54, fontSize: 11)),
                            Text("${totalSales.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          ],
                        )
                      ],
                    ),
                  ),
                ),

                // SECTION Bilan de Caisse
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("BILAN DE CAISSE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.1)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))),
                          child: Row(
                            children: [
                              Expanded(child: _buildInfoRow("Fond Initial", widget.session.initialCash, Colors.white)),
                              Expanded(child: _buildInfoRow("Théorique", theoreticalTotal, Colors.amberAccent)),
                              Expanded(child: _buildInfoRow("Réel Déclaré", isActive ? 0.0 : realTotal, Colors.white)),
                              if (!isActive) ...[
                                Container(width: 1, height: 40, color: Colors.white12),
                                const SizedBox(width: 16),
                                Expanded(child: _buildInfoRow("Écart", discrepancy, discrepancy.abs() < 0.05 ? Colors.greenAccent : Colors.redAccent)),
                              ]
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text("RÉPARTITION DES VENTES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.1)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildSummaryCard("BORNES", cbKioskSales, Icons.touch_app, Colors.tealAccent)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildSummaryCard("COMPTOIR", cbCounterSales, Icons.point_of_sale, Colors.indigoAccent)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildSummaryCard("ESPECES", cashSales, Icons.payments, Colors.greenAccent)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildSummaryCard("T. RESTO", ticketSales, Icons.restaurant, Colors.orangeAccent)),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("TRANSACTIONS (${filteredTransactions.length})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.1)),
                            const Icon(Icons.filter_list, color: Colors.white54, size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildFilterChips(),
                      ],
                    ),
                  ),
                ),

                // LISTE DES TRANSACTIONS FILTRÉES
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildTransactionCard(filteredTransactions[index]),
                      childCount: filteredTransactions.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, double amount, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 4),
        Text("${amount > 0 && label == 'Écart' ? '+' : ''}${amount.toStringAsFixed(2)} €", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _buildSummaryCard(String label, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3), width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Expanded(child: Text(label, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 9), overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 8),
          FittedBox(child: Text("${amount.toStringAsFixed(2)} €", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color))),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Toutes', 'Bornes', 'Comptoir', 'Cash', 'TR', 'Mixtes'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _activeFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(filter, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.black : Colors.white70)),
              selected: isSelected,
              onSelected: (val) => setState(() => _activeFilter = filter),
              selectedColor: Colors.white,
              backgroundColor: Colors.white.withOpacity(0.05),
              side: BorderSide(color: isSelected ? Colors.white : Colors.transparent),
            ),
          );
        }).toList(),
      ),
    );
  }

  // TUILE DE TRANSACTION AVEC BADGES
  Widget _buildTransactionCard(model.Transaction tx) {
    final primaryColor = _getPrimaryPaymentColor(tx);
    final shortId = tx.id.length >= 6 ? tx.id.substring(0, 6) : tx.id;
    final mainTitle = tx.identifier.isNotEmpty ? tx.identifier : "Ticket #$shortId";

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white.withOpacity(0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: primaryColor.withOpacity(0.1), child: _getPaymentIcon(tx, size: 20, color: primaryColor)),
        title: Text("$mainTitle - ${DateFormat('HH:mm').format(tx.timestamp)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: _buildPaymentChips(tx)),
        trailing: Text("${tx.total.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
        onTap: () => showDialog(context: context, builder: (_) => TransactionDetailsDialog(transaction: tx)),
      ),
    );
  }

  Color _getPrimaryPaymentColor(model.Transaction t) {
    if (t.paymentMethods.keys.length > 1) return Colors.blueGrey;
    final key = t.paymentMethods.keys.first;
    if (key == 'Cash') return Colors.greenAccent;
    if (key == 'Card_Kiosk') return Colors.tealAccent;
    if (key == 'Ticket') return Colors.orangeAccent;
    bool isBorne = false;
    try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    return isBorne ? Colors.tealAccent : Colors.indigoAccent;
  }

  Icon _getPaymentIcon(model.Transaction t, {double size = 20, Color? color}) {
    if (t.paymentMethods.keys.length > 1) return Icon(Icons.call_split, color: color, size: size);
    final key = t.paymentMethods.keys.first;
    if (key == 'Cash') return Icon(Icons.payments, color: color, size: size);
    if (key == 'Ticket') return Icon(Icons.restaurant, color: color, size: size);
    bool isBorne = false;
    try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
    return Icon(isBorne ? Icons.touch_app : Icons.point_of_sale, color: color, size: size);
  }

  Widget _buildPaymentChips(model.Transaction t) {
    final methods = t.paymentMethods.keys.toList();
    final bool isMixte = methods.length > 1;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (isMixte) _chipBadge("MIXTE", Colors.blueGrey),
        ...methods.map((key) {
          String label = key;
          Color c = Colors.grey;
          if (key == 'Cash') { label = 'ESPECES'; c = Colors.greenAccent; }
          else if (key == 'Card_Kiosk') { label = 'CB BORNE'; c = Colors.tealAccent; }
          else if (key == 'Card_Counter') { label = 'CB COMPTOIR'; c = Colors.indigoAccent; }
          else if (key == 'Ticket') { label = 'TICKET RESTO'; c = Colors.orangeAccent; }
          else if (key == 'Card') {
            bool isBorne = false;
            try { if ((t as dynamic).source?.toString() == 'borne') isBorne = true; } catch (_) {}
            label = isBorne ? 'CB BORNE' : 'CB COMPTOIR';
            c = isBorne ? Colors.tealAccent : Colors.indigoAccent;
          }
          return _chipBadge(label, c);
        }),
      ],
    );
  }

  Widget _chipBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS ATOMIQUES
// ─────────────────────────────────────────────────────────────────────────────

class MetricCard extends StatelessWidget {
  final String title, value, subtitle;
  final IconData icon;
  final Color color;
  final bool small;

  const MetricCard({super.key, required this.title, required this.value, required this.subtitle, required this.icon, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(small ? 16 : 20),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color, size: small ? 14 : 16), const SizedBox(width: 8), Expanded(child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, overflow: TextOverflow.ellipsis)))]),
          SizedBox(height: small ? 8 : 12),
          Text(value, style: TextStyle(color: Colors.white, fontSize: small ? 20 : 32, fontWeight: FontWeight.w900)),
          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: small ? 10 : 12)),
        ],
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  final Color color;
  const PulseDot({super.key, required this.color});
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return FadeTransition(opacity: Tween(begin: 0.4, end: 1.0).animate(_c), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: widget.color.withOpacity(0.6), blurRadius: 6)]))); }
}

class HourlyChart extends StatelessWidget {
  final AdvancedStatsSummary stats;
  const HourlyChart({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.caPerHour.isEmpty) return const SizedBox(height: 50, child: Center(child: Text("Pas assez de données pour le moment", style: TextStyle(color: Colors.white38))));
    double maxCa = stats.caPerHour.values.reduce((a, b) => a > b ? a : b);
    List<int> sortedHours = stats.caPerHour.keys.toList()..sort();

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: sortedHours.map((hour) {
          double ca = stats.caPerHour[hour]!;
          double ratio = maxCa > 0 ? ca / maxCa : 0;
          bool isPeak = ca == maxCa;

          return Tooltip(
            message: "${ca.toStringAsFixed(2)} €",
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPeak) const Icon(Icons.local_fire_department, color: Colors.orangeAccent, size: 12),
                Text("${ca.toInt()}€", style: TextStyle(fontSize: 8, color: isPeak ? Colors.orangeAccent : Colors.white38, fontWeight: isPeak ? FontWeight.bold : FontWeight.normal)),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: ratio),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOutQuint,
                    builder: (context, value, child) {
                      return Container(
                        width: 20, height: 70 * value,
                        decoration: BoxDecoration(gradient: LinearGradient(colors: isPeak ? [Colors.orangeAccent, Colors.deepOrange] : [Colors.indigoAccent, Colors.blue.shade700], begin: Alignment.bottomCenter, end: Alignment.topCenter), borderRadius: BorderRadius.circular(4)),
                      );
                    }),
                const SizedBox(height: 4),
                Text("${hour}h", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white54)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class TransactionDetailsDialog extends StatelessWidget {
  final model.Transaction transaction;
  const TransactionDetailsDialog({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Détails du ticket", style: TextStyle(color: Colors.white)),
          IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ID: ${transaction.id}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              const Text("Produits :", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              ...transaction.items.map((item) {
                final qty = item['quantity'] ?? 1;
                final name = item['name'] ?? 'Inconnu';
                final price = item['price'] ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text("${qty}x $name", style: const TextStyle(color: Colors.white70))),
                      Text("${(price * qty).toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                );
              }),
              const Divider(color: Colors.white24, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL PAYÉ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  Text("${transaction.total.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),
              const Text("Méthodes d'encaissement :", style: TextStyle(color: Colors.white54, fontSize: 12)),
              ...transaction.paymentMethods.entries.map((e) => Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key.replaceAll('Card_Kiosk', 'CB Borne').replaceAll('Card_Counter', 'CB Comptoir'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text("${(e.value as num).toDouble().toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ))
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTEUR LOGIQUE STATISTIQUES
// ─────────────────────────────────────────────────────────────────────────────

class AdvancedStatsSummary {
  double caTotal = 0.0;
  double tvaTotal = 0.0;
  int count = 0;

  int surPlaceCount = 0;
  double surPlaceCA = 0.0;
  int emporterCount = 0;
  double emporterCA = 0.0;

  int borneCount = 0;
  double borneCA = 0.0;
  int caisseCount = 0;
  double caisseCA = 0.0;

  Map<int, double> caPerHour = {};
  Map<String, int> productQty = {};
  Map<String, double> productCA = {};

  Map<String, double> payments = {
    'CB Borne': 0.0,
    'CB Comptoir': 0.0,
    'Espèces': 0.0,
    'Tickets Resto': 0.0,
    'Autres': 0.0,
  };

  Map<String, double> tvaBreakdown = {
    '5.5%': 0.0,
    '10%': 0.0,
    '20%': 0.0,
  };

  AdvancedStatsSummary(List<model.Transaction> transactions) {
    count = transactions.length;
    if (count == 0) return;

    for (var t in transactions) {
      final txTotal = t.total.toDouble();
      caTotal += txTotal;
      tvaTotal += (t.vatTotal).toDouble();

      final hour = t.timestamp.hour;
      caPerHour[hour] = (caPerHour[hour] ?? 0.0) + txTotal;

      bool isBorne = false;
      try { if (t.source?.toString().toLowerCase() == 'borne') isBorne = true; } catch (_) {}
      try { final dynamic d = t; if (d.origin?.toString().toLowerCase() == 'kiosk') isBorne = true; } catch (_) {}

      if (isBorne || t.paymentMethods.containsKey('Card_Kiosk') || t.orderType.toString().toLowerCase().contains('borne')) {
        borneCount++;
        borneCA += txTotal;
      } else {
        caisseCount++;
        caisseCA += txTotal;
      }

      final typeStr = t.orderType.toString().toLowerCase();
      final isSurPlace = typeStr.contains('place') || typeStr.contains('dine') || typeStr.contains('site');
      if (isSurPlace) {
        surPlaceCount++;
        surPlaceCA += txTotal;
      } else {
        emporterCount++;
        emporterCA += txTotal;
      }

      t.paymentMethods.forEach((method, val) {
        double amount = (val as num).toDouble();
        if (method == 'Cash') payments['Espèces'] = (payments['Espèces'] ?? 0) + amount;
        else if (method == 'Ticket') payments['Tickets Resto'] = (payments['Tickets Resto'] ?? 0) + amount;
        else if (method == 'Card_Kiosk') payments['CB Borne'] = (payments['CB Borne'] ?? 0) + amount;
        else if (method == 'Card_Counter') payments['CB Comptoir'] = (payments['CB Comptoir'] ?? 0) + amount;
        else if (method == 'Card') {
          if (isBorne) payments['CB Borne'] = (payments['CB Borne'] ?? 0) + amount;
          else payments['CB Comptoir'] = (payments['CB Comptoir'] ?? 0) + amount;
        } else payments['Autres'] = (payments['Autres'] ?? 0) + amount;
      });

      for (var item in t.items) {
        final name = item['name']?.toString() ?? 'Article inconnu';
        final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
        final qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        final taxRate = double.tryParse(item['vatRate']?.toString() ?? item['taxRate']?.toString() ?? '10') ?? 10.0;
        final itemCA = price * qty;
        final itemTva = itemCA - (itemCA / (1 + (taxRate / 100)));

        if (taxRate == 5.5) tvaBreakdown['5.5%'] = (tvaBreakdown['5.5%'] ?? 0) + itemTva;
        else if (taxRate == 20.0) tvaBreakdown['20%'] = (tvaBreakdown['20%'] ?? 0) + itemTva;
        else tvaBreakdown['10%'] = (tvaBreakdown['10%'] ?? 0) + itemTva;

        if (price > 0) {
          productQty[name] = (productQty[name] ?? 0) + qty;
          productCA[name] = (productCA[name] ?? 0.0) + itemCA;
        }
      }
    }
  }

  double get panierMoyen => count > 0 ? caTotal / count : 0.0;
  List<MapEntry<String, int>> get sortedProductsByQty => productQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

class StatsPdfExporter {
  static Future<void> generateAndSharePdf({
    required AdvancedStatsSummary stats,
    required String companyName,
    required String restaurantName,
    required String address,
    required String zipCity,
    required String phone,
    required String siret,
    required String tvaNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold));

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(startDate);
    final endStr = DateFormat('dd/MM/yyyy HH:mm').format(endDate);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(restaurantName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
        pw.SizedBox(height: 20),
        pw.Text("RAPPORT COMPTABLE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.Text("Du $dateStr au $endStr"),
        pw.SizedBox(height: 20),
        pw.Text("CA TTC : ${stats.caTotal.toStringAsFixed(2)} €"),
        pw.Text("Total TVA : ${stats.tvaTotal.toStringAsFixed(2)} €"),
      ],
    ));

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Rapport_${DateFormat('yyyyMMdd').format(startDate)}.pdf');
  }
}