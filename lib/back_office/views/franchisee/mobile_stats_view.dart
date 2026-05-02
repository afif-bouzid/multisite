import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ouiborne/core/repository/repository.dart';
import 'package:ouiborne/core/auth_provider.dart';
import 'package:ouiborne/models.dart' as model;

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION GLOBALE
// ─────────────────────────────────────────────────────────────────────────────

enum DateFilter { today, yesterday, thisWeek, thisMonth, custom }

const kDarkBg = Color(0xFF0F172A);
const kCardBg = Color(0xFF1E293B);
const kCardBgLight = Color(0xFF273449);
const kAccentColor = Colors.indigoAccent;
const int kBusinessDayStartHour = 5;

// ✅ helper isBorne centralisé — utilisé partout de façon cohérente
bool _isBorneTx(model.Transaction t) =>
    t.source.toLowerCase() == 'borne' ||
        t.paymentMethods.containsKey('Card_Kiosk') ||
        t.orderType.toString().toLowerCase().contains('borne');

// ✅ helper isSurPlace avec matching exact (évite false positive "website", "offsite")
bool _isSurPlaceTx(model.Transaction t) {
  final s = t.orderType.toString().toLowerCase();
  return s == 'onsite' || s == 'dine_in' || s == 'dinein' ||
      s.contains('place') || s.contains('dine');
}

// Helper : formatage monétaire cohérent (€ en suffixe, 2 décimales, virgule FR)
String _money(num? value) {
  final v = value ?? 0;
  return "${v.toStringAsFixed(2).replaceAll('.', ',')} €";
}

String _pct(double value, double total) {
  if (total <= 0) return "0 %";
  final p = (value / total) * 100.0;
  return "${p.toStringAsFixed(1).replaceAll('.', ',')} %";
}

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
  // ✅ FIX — initialisé pour éviter le crash "late" avant le premier applyFilter
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(hours: 19)),
    end: DateTime.now(),
  );

  Future<List<model.Transaction>>? _historicalFuture;
  Future<List<model.TillSession>>? _historySessionsFuture;

  bool _isLoadingFilter = false;
  bool _isExportingPdf = false;
  bool _isExportingCsv = false;
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
    if (mounted) setState(() => _isLoadingFilter = true);
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
      case DateFilter.thisMonth:
        start = DateTime(businessNow.year, businessNow.month, 1, kBusinessDayStartHour, 0, 0);
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
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("La période est limitée à 31 jours. Pour des exports plus longs, utilisez l'export mensuel."),
                  backgroundColor: Colors.redAccent));
              setState(() => _isLoadingFilter = false);
            }
            return;
          }
          start = DateTime(picked.start.year, picked.start.month, picked.start.day, kBusinessDayStartHour, 0, 0);
          end = DateTime(picked.end.year, picked.end.month, picked.end.day + 1, kBusinessDayStartHour - 1, 59, 59);
        } else {
          if (mounted) setState(() => _isLoadingFilter = false);
          return;
        }
        break;
    }

    if (mounted) {
      setState(() {
        _currentFilter = filter;
        _selectedRange = DateTimeRange(start: start, end: end);
        _globalSearchQuery = "";

        _historicalFuture = _repository.getTransactionsInDateRange(storeId, startDate: start, endDate: end).first;

        // ✅ FIX sessions cross-midnight — large fenêtre côté repository :
        //   - 7 jours en arrière : couvre les sessions exceptionnellement longues
        //     (ex: oubli de fermeture pendant un week-end)
        //   - +24h après end : sessions qui dépassent minuit en fin de période
        // Le filtrage précis du chevauchement se fait ensuite côté UI.
        _historySessionsFuture = _repository.getFranchiseeSessions(
          storeId,
          startDate: start.subtract(const Duration(days: 7)),
          endDate: end.add(const Duration(hours: 24)),
        ).first;

        _isLoadingFilter = false;
      });
    }
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

  // ───────────────────────── EXPORTS ─────────────────────────

  Future<({String siret, String tva, String address, String zipCity})> _fetchCompanyData(String storeId, model.FranchiseUser user) async {
    String siret = "", tva = "", address = user.address ?? "", zipCity = "";
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(storeId).get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        siret = d['siret']?.toString() ?? "";
        tva = d['tvaNumber']?.toString() ?? d['vatNumber']?.toString() ?? "";
        address = d['address']?.toString() ?? address;
        zipCity = "${d['zipCode'] ?? ''} ${d['city'] ?? ''}".trim();
      }
    } catch (_) {}
    return (siret: siret, tva: tva, address: address, zipCity: zipCity);
  }

  Future<void> _exportPdf(BuildContext context, model.FranchiseUser user, String storeId) async {
    setState(() => _isExportingPdf = true);
    try {
      final txs = await _historicalFuture ?? <model.Transaction>[];
      final sessions = await _historySessionsFuture ?? <model.TillSession>[];
      final stats = AdvancedStatsSummary(txs);
      final company = await _fetchCompanyData(storeId, user);

      await StatsPdfExporter.generateAndSharePdf(
        stats: stats,
        sessions: sessions,
        companyName: user.companyName ?? "Société",
        restaurantName: user.restaurantName ?? "Restaurant",
        address: company.address,
        zipCity: company.zipCity,
        phone: user.phone ?? "",
        siret: company.siret,
        tvaNumber: company.tva,
        startDate: _selectedRange.start,
        endDate: _selectedRange.end,
        filterLabel: _filterLabel(_currentFilter),
      );
    } catch (e) {
      if (!mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur génération PDF : $e"), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _exportCsv(BuildContext context, model.FranchiseUser user, String storeId) async {
    setState(() => _isExportingCsv = true);
    try {
      final txs = await _historicalFuture ?? <model.Transaction>[];
      final stats = AdvancedStatsSummary(txs);
      final company = await _fetchCompanyData(storeId, user);

      await StatsCsvExporter.generateAndShareCsv(
        transactions: txs,
        stats: stats,
        companyName: user.companyName ?? "Société",
        restaurantName: user.restaurantName ?? "Restaurant",
        address: company.address,
        zipCity: company.zipCity,
        siret: company.siret,
        tvaNumber: company.tva,
        startDate: _selectedRange.start,
        endDate: _selectedRange.end,
      );
    } catch (e) {
      if (!mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur génération CSV : $e"), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  String _filterLabel(DateFilter f) {
    switch (f) {
      case DateFilter.today: return "Aujourd'hui";
      case DateFilter.yesterday: return "Hier";
      case DateFilter.thisWeek: return "Cette semaine";
      case DateFilter.thisMonth: return "Ce mois-ci";
      case DateFilter.custom: return "Période personnalisée";
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
          centerTitle: true,
          // ✅ Logo Ouiborne (prestataire) à gauche
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset(
              'assets/web-app-manifest-192x192.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text(
                  "",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
          leadingWidth: 56,
          // ✅ Nom du client centré, en blanc
          title: Text(
            user.restaurantName?.toUpperCase() ?? "TABLEAU DE BORD",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 0.8,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
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
  // ONGLET 1 : SESSION LIVE
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
            final txs = txSnap.data ?? <model.Transaction>[];
            final stats = AdvancedStatsSummary(txs);
            final duration = DateTime.now().difference(session.openingTime);
            final theoretical = session.initialCash + (stats.payments['Espèces'] ?? 0);

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
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
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withValues(alpha: 0.2), foregroundColor: Colors.greenAccent, elevation: 0),
                          child: const Text("DÉTAILS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        )
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MetricCard(
                      title: "CHIFFRE D'AFFAIRES SESSION",
                      value: _money(stats.caTotal),
                      subtitle: "${txs.length} commandes traitées depuis l'ouverture",
                      icon: Icons.point_of_sale,
                      color: Colors.greenAccent,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
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
                          Expanded(child: MetricCard(title: "CB BORNE", value: _money(stats.payments['CB Borne']), subtitle: "", icon: Icons.touch_app, color: Colors.tealAccent, small: true)),
                          const SizedBox(width: 12),
                          Expanded(child: MetricCard(title: "CB COMPTOIR", value: _money(stats.payments['CB Comptoir']), subtitle: "", icon: Icons.credit_card, color: Colors.indigoAccent, small: true)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: MetricCard(title: "TICKET RESTO", value: _money(stats.payments['Tickets Resto']), subtitle: "", icon: Icons.restaurant, color: Colors.orangeAccent, small: true)),
                          const SizedBox(width: 12),
                          Expanded(child: MetricCard(title: "ESPÈCES CASH", value: _money(stats.payments['Espèces']), subtitle: "Théorique: ${_money(theoretical)}", icon: Icons.payments, color: Colors.amberAccent, small: true)),
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
  // ONGLET 2 : Z DE CAISSE (STATS) — REFONTE COMPLÈTE
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
          final allTxs = snapshot.data ?? <model.Transaction>[];
          final stats = AdvancedStatsSummary(allTxs);
          final rangeDays = _selectedRange.end.difference(_selectedRange.start).inDays + 1;
          final isMultiDay = rangeDays > 1;

          return RefreshIndicator(
            onRefresh: () async => _applyFilter(_currentFilter, storeId),
            child: CustomScrollView(
              slivers: [
                // ── Filtres dates
                SliverToBoxAdapter(child: _buildFilterBar(storeId)),

                // ── Si aucune donnée, on affiche un état vide élégant
                if (stats.count == 0)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else ...[
                  // ── 1. HERO CARD : CA TTC
                  SliverToBoxAdapter(child: _buildHeroCard(stats)),

                  // ── 2. BOUTONS EXPORT (PDF + CSV)
                  SliverToBoxAdapter(child: _buildExportButtons(user, storeId)),

                  // ── 2.bis. ✅ NOUVEAU — KPIs FAST-FOOD (cadence, articles/ticket, rush, taux borne)
                  SliverToBoxAdapter(child: _buildFastFoodKpis(stats, allTxs)),

                  // ── 2.ter. ✅ NOUVEAU — GRAPHIQUES PRO (donut paiements, line CA, pie service)
                  SliverToBoxAdapter(child: _buildChartsSection(stats, isMultiDay)),

                  // ── 3. KPIs COMPTABLES CLÉS
                  SliverToBoxAdapter(child: _buildAccountingKpis(stats)),

                  // ── 4. GRAPHIQUE RYTHME HORAIRE
                  SliverToBoxAdapter(child: _buildHourlySection(stats)),

                  // ── 5. BLOC TVA LÉGAL (OBLIGATOIRE POUR LA COMPTABILITÉ)
                  SliverToBoxAdapter(child: _buildLegalVatSection(stats)),

                  // ── 6. RÉPARTITION ENCAISSEMENTS (avec %)
                  SliverToBoxAdapter(child: _buildPaymentBreakdownSection(stats)),

                  // ── 7. CANAL & SERVICE
                  SliverToBoxAdapter(child: _buildChannelAndServiceSection(stats)),

                  // ── 8. STATS EXTRÊMES (ticket max, min, jour record)
                  SliverToBoxAdapter(child: _buildExtremesSection(stats, isMultiDay)),

                  // ── 9. CA PAR JOUR si plage > 1 jour
                  if (isMultiDay) SliverToBoxAdapter(child: _buildDailySection(stats)),

                  // ── 10. TOP PRODUITS
                  SliverToBoxAdapter(child: _buildTopProductsSection(stats)),

                  // ── 10.bis. ✅ NOUVEAU — TOP SUPPLÉMENTS PAYANTS (avec CA)
                  if (stats.topPaidOptions.isNotEmpty)
                    SliverToBoxAdapter(child: _buildTopPaidOptionsSection(stats)),

                  // ── 10.ter. ✅ NOUVEAU — TOP CHOIX GRATUITS (sauces, options incluses)
                  if (stats.topFreeOptions.isNotEmpty)
                    SliverToBoxAdapter(child: _buildTopFreeOptionsSection(stats)),

                  // ── 11. FLOP PRODUITS
                  SliverToBoxAdapter(child: _buildFlopProductsSection(stats)),

                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ──────────────── SECTIONS DE L'ONGLET Z DE CAISSE ────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insights_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 20),
            const Text("AUCUNE DONNÉE", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Text("Aucune transaction sur la période\n${_filterLabel(_currentFilter)}.",
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(AdvancedStatsSummary stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 14),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "CHIFFRE D'AFFAIRES TTC · ${_filterLabel(_currentFilter).toUpperCase()}",
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(child: Text(_money(stats.caTotal), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white))),
            const SizedBox(height: 8),
            Text("${stats.count} ticket${stats.count > 1 ? 's' : ''}  ·  Panier moyen ${_money(stats.panierMoyen)}",
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text("Du ${DateFormat('dd/MM HH:mm').format(_selectedRange.start)} au ${DateFormat('dd/MM HH:mm').format(_selectedRange.end)}",
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButtons(model.FranchiseUser user, String storeId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isExportingPdf ? null : () => _exportPdf(context, user, storeId),
              icon: _isExportingPdf
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf, size: 16),
              label: Text(_isExportingPdf ? "GÉNÉRATION..." : "EXPORT PDF", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                foregroundColor: Colors.redAccent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isExportingCsv ? null : () => _exportCsv(context, user, storeId),
              icon: _isExportingCsv
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.table_chart, size: 16),
              label: Text(_isExportingCsv ? "GÉNÉRATION..." : "EXPORT CSV", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.withValues(alpha: 0.15),
                foregroundColor: Colors.greenAccent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountingKpis(AdvancedStatsSummary stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text("INDICATEURS COMPTABLES", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
          ),
          Row(children: [
            Expanded(child: MetricCard(title: "CA HT", value: _money(stats.caHt), subtitle: "Hors taxes", icon: Icons.euro, color: Colors.cyanAccent, small: true)),
            const SizedBox(width: 8),
            Expanded(child: MetricCard(title: "TVA TOTALE", value: _money(stats.tvaTotal), subtitle: "Collectée", icon: Icons.receipt_long, color: Colors.amberAccent, small: true)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: MetricCard(title: "REMISES", value: _money(stats.totalDiscounts), subtitle: stats.discountsCount > 0 ? "${stats.discountsCount} ticket${stats.discountsCount > 1 ? 's' : ''}" : "Aucune", icon: Icons.local_offer_outlined, color: Colors.pinkAccent, small: true)),
            const SizedBox(width: 8),
            Expanded(child: MetricCard(title: "PANIER MOYEN", value: _money(stats.panierMoyen), subtitle: "Par ticket", icon: Icons.shopping_cart_outlined, color: Colors.lightBlueAccent, small: true)),
          ]),
        ],
      ),
    );
  }

  Widget _buildHourlySection(AdvancedStatsSummary stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("RYTHME D'ACTIVITÉ", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
                if (stats.peakHour != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      const Icon(Icons.local_fire_department, size: 12, color: Colors.orangeAccent),
                      const SizedBox(width: 4),
                      Text("Pic à ${stats.peakHour}h", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            HourlyChart(stats: stats),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalVatSection(AdvancedStatsSummary stats) {
    final rows = <Widget>[];
    // On affiche TOUS les taux, même ceux à 0, si au moins un est > 0, pour un Z légal complet
    final hasAny = stats.vatByRate.values.any((v) => v.baseHt > 0.0001 || v.tva > 0.0001);

    for (final entry in stats.vatByRate.entries) {
      final data = entry.value;
      if (!hasAny || data.baseHt > 0.0001 || data.tva > 0.0001) {
        rows.add(_buildVatRow(entry.key, data));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.gavel, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 6),
              const Text("TVA LÉGALE PAR TAUX", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: const Text("COMPTABILITÉ", style: TextStyle(color: Colors.amberAccent, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ),
            ]),
            const SizedBox(height: 14),
            // En-têtes colonnes
            Row(children: const [
              Expanded(flex: 2, child: Text("TAUX", style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text("BASE HT", textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text("TVA", textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text("TOTAL TTC", textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold))),
            ]),
            const Divider(color: Colors.white12, height: 16),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("Aucune TVA sur la période.", style: TextStyle(color: Colors.white38, fontSize: 12)),
              )
            else
              ...rows,
            const Divider(color: Colors.white24, height: 20),
            // Totaux
            Row(children: [
              const Expanded(flex: 2, child: Text("TOTAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
              Expanded(flex: 3, child: Text(_money(stats.caHt), textAlign: TextAlign.right, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 3, child: Text(_money(stats.tvaTotal), textAlign: TextAlign.right, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 3, child: Text(_money(stats.caTotal), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildVatRow(String label, VatBreakdownEntry data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(flex: 2, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
        )),
        Expanded(flex: 3, child: Text(_money(data.baseHt), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
        Expanded(flex: 3, child: Text(_money(data.tva), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
        Expanded(flex: 3, child: Text(_money(data.baseHt + data.tva), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _buildPaymentBreakdownSection(AdvancedStatsSummary stats) {
    final total = stats.payments.values.fold<double>(0.0, (a, b) => a + b);
    final items = [
      ('CB Borne', Icons.touch_app, Colors.tealAccent),
      ('CB Comptoir', Icons.credit_card, Colors.indigoAccent),
      ('Espèces', Icons.payments, Colors.greenAccent),
      ('Tickets Resto', Icons.restaurant, Colors.orangeAccent),
      ('Autres', Icons.more_horiz, Colors.blueGrey),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("RÉPARTITION DES ENCAISSEMENTS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
            const SizedBox(height: 14),
            ...items.where((e) => (stats.payments[e.$1] ?? 0) > 0.01).map((e) {
              final amount = stats.payments[e.$1] ?? 0.0;
              final ratio = total > 0 ? amount / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(e.$2, size: 12, color: e.$3),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.$1, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))),
                      Text(_money(amount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(_pct(amount, total), textAlign: TextAlign.right, style: TextStyle(color: e.$3, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(e.$3),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelAndServiceSection(AdvancedStatsSummary stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CANAL", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  _canalServiceRow("Borne", stats.borneCount, stats.borneCA, stats.caTotal, Colors.tealAccent),
                  const SizedBox(height: 10),
                  _canalServiceRow("Caisse", stats.caisseCount, stats.caisseCA, stats.caTotal, Colors.indigoAccent),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TYPE DE SERVICE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  _canalServiceRow("Sur place", stats.surPlaceCount, stats.surPlaceCA, stats.caTotal, Colors.purpleAccent),
                  const SizedBox(height: 10),
                  _canalServiceRow("À emporter", stats.emporterCount, stats.emporterCA, stats.caTotal, Colors.lightBlueAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canalServiceRow(String label, int count, double ca, double total, Color color) {
    final ratio = total > 0 ? ca / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text("$label ($count)", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
          Text(_pct(ca, total), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 4),
        Text(_money(ca), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _buildExtremesSection(AdvancedStatsSummary stats, bool isMultiDay) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text("EXTRÊMES", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
          ),
          Row(children: [
            Expanded(child: MetricCard(
              title: "TICKET MAX",
              value: _money(stats.maxTicket),
              subtitle: stats.maxTicketLabel,
              icon: Icons.trending_up,
              color: Colors.greenAccent,
              small: true,
            )),
            const SizedBox(width: 8),
            Expanded(child: MetricCard(
              title: "TICKET MIN",
              value: _money(stats.minTicket),
              subtitle: stats.minTicketLabel,
              icon: Icons.trending_down,
              color: Colors.redAccent,
              small: true,
            )),
          ]),
          if (isMultiDay) ...[
            const SizedBox(height: 8),
            MetricCard(
              title: "MEILLEUR JOUR",
              value: _money(stats.bestDayCA),
              subtitle: stats.bestDayLabel,
              icon: Icons.emoji_events_outlined,
              color: Colors.amberAccent,
              small: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailySection(AdvancedStatsSummary stats) {
    final entries = stats.caPerDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const SizedBox.shrink();
    final maxCa = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("CA PAR JOUR", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
            const SizedBox(height: 14),
            ...entries.map((e) {
              final ratio = maxCa > 0 ? e.value / maxCa : 0.0;
              final isBest = e.value == maxCa;
              final date = DateFormat('yyyy-MM-dd').parse(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(DateFormat('EEE dd MMM', 'fr_FR').format(date), style: TextStyle(color: isBest ? Colors.amberAccent : Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
                      Text(_money(e.value), style: TextStyle(color: isBest ? Colors.amberAccent : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(isBest ? Colors.amberAccent : Colors.indigoAccent),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsSection(AdvancedStatsSummary stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            collapsedIconColor: Colors.white54,
            iconColor: Colors.greenAccent,
            title: Row(children: const [
              Icon(Icons.star, size: 14, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text("TOP PRODUITS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
            ]),
            children: [
              if (stats.productQty.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text("Aucun produit vendu.", style: TextStyle(color: Colors.white38)))
              else
                ...stats.sortedProductsByQty.take(15).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final e = entry.value;
                  final revenue = stats.productCA[e.key] ?? 0.0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
                    child: Row(
                      children: [
                        Container(
                          width: 22, height: 22, alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: index < 3 ? Colors.amberAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text("${index + 1}", style: TextStyle(color: index < 3 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                          child: Text("${e.value}x", style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(_money(revenue), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NOUVEAU — KPIs spécifiques pour fast-food (cadence, articles, rush, taux borne)
  Widget _buildFastFoodKpis(AdvancedStatsSummary stats, List<model.Transaction> txs) {
    final periodHours = _selectedRange.end.difference(_selectedRange.start).inMinutes / 60.0;
    final cadence = periodHours > 0 ? stats.count / periodHours : 0.0;
    final borneRatio = stats.caTotal > 0 ? stats.borneCA / stats.caTotal : 0.0;

    double avgItems = 0.0;
    if (txs.isNotEmpty) {
      final totalItems = txs.fold<int>(0, (acc, t) =>
      acc + t.items.fold<int>(0, (a, item) => a + ((item['quantity'] as num?)?.toInt() ?? 1)));
      avgItems = totalItems / txs.length;
    }

    String rushLabel = "-";
    String rushSubtitle = "Pas de données";
    if (stats.peakHour != null) {
      rushLabel = "${stats.peakHour}h-${(stats.peakHour! + 1) % 24}h";
      rushSubtitle = _money(stats.caPerHour[stats.peakHour] ?? 0);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text("PERFORMANCE FAST-FOOD", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
          ),
          Row(children: [
            Expanded(child: MetricCard(
              title: "CADENCE",
              value: "${cadence.toStringAsFixed(1)}/h",
              subtitle: "Commandes par heure",
              icon: Icons.speed,
              color: cadence >= 15 ? Colors.greenAccent : cadence >= 8 ? Colors.amberAccent : Colors.redAccent,
              small: true,
            )),
            const SizedBox(width: 8),
            Expanded(child: MetricCard(
              title: "ARTICLES/TICKET",
              value: avgItems.toStringAsFixed(1),
              subtitle: "Moy. produits par cmd",
              icon: Icons.shopping_bag_outlined,
              color: Colors.purpleAccent,
              small: true,
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: MetricCard(
              title: "HEURE DE RUSH",
              value: rushLabel,
              subtitle: rushSubtitle,
              icon: Icons.local_fire_department,
              color: Colors.orangeAccent,
              small: true,
            )),
            const SizedBox(width: 8),
            Expanded(child: MetricCard(
              title: "AUTONOMIE BORNE",
              value: "${(borneRatio * 100).toStringAsFixed(0)}%",
              subtitle: "${stats.borneCount} cmd · ${_money(stats.borneCA)}",
              icon: Icons.touch_app,
              color: Colors.tealAccent,
              small: true,
            )),
          ]),
        ],
      ),
    );
  }

  // ✅ NOUVEAU — Section graphiques pro (donut paiements + line CA + pie service)
  Widget _buildChartsSection(AdvancedStatsSummary stats, bool isMultiDay) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text("VISUALISATIONS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
          ),

          // ── Donut chart : Répartition paiements
          _buildPaymentsDonutChart(stats),
          const SizedBox(height: 12),

          // ── Pie chart : Sur place vs À emporter
          if (stats.surPlaceCount > 0 || stats.emporterCount > 0)
            _buildServicePieChart(stats),

          // ── Line chart : Évolution CA cumulé
          if (isMultiDay && stats.caPerDay.length > 1) ...[
            const SizedBox(height: 12),
            _buildDailyLineChart(stats),
          ],
        ],
      ),
    );
  }

  // Donut paiements
  Widget _buildPaymentsDonutChart(AdvancedStatsSummary stats) {
    final entries = [
      ('CB Borne', stats.payments['CB Borne'] ?? 0.0, Colors.tealAccent),
      ('CB Comptoir', stats.payments['CB Comptoir'] ?? 0.0, Colors.indigoAccent),
      ('Espèces', stats.payments['Espèces'] ?? 0.0, Colors.greenAccent),
      ('Tickets Resto', stats.payments['Tickets Resto'] ?? 0.0, Colors.orangeAccent),
      ('Autres', stats.payments['Autres'] ?? 0.0, Colors.blueGrey),
    ].where((e) => e.$2 > 0.01).toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    final total = entries.fold<double>(0, (acc, e) => acc + e.$2);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("RÉPARTITION DES PAIEMENTS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.tealAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(_money(total), style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Donut centré + total au milieu (Stack)
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 55,
                    startDegreeOffset: -90,
                    sections: entries.map((e) {
                      final pct = (e.$2 / total) * 100;
                      return PieChartSectionData(
                        value: e.$2,
                        // Affichage du % uniquement si la part est >= 7% (sinon illisible sur mobile)
                        title: pct >= 7 ? "${pct.toStringAsFixed(0)}%" : "",
                        color: e.$3,
                        radius: 35,
                        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black87),
                      );
                    }).toList(),
                  ),
                ),
                // Total au centre du donut
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("TOTAL", style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text(_money(total), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text("${entries.length} mode${entries.length > 1 ? 's' : ''}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Légende en cartes empilées (1 par ligne, optimisé portrait mobile)
          ...entries.map((e) {
            final pct = (e.$2 / total) * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(color: e.$3, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.$1, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    Text(_money(e.$2), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: e.$3.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        "${pct.toStringAsFixed(0)}%",
                        style: TextStyle(color: e.$3, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation(e.$3),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Pie service
  Widget _buildServicePieChart(AdvancedStatsSummary stats) {
    final total = stats.surPlaceCA + stats.emporterCA;
    if (total < 0.01) return const SizedBox.shrink();

    final entries = [
      ('Sur place', stats.surPlaceCA, stats.surPlaceCount, Colors.purpleAccent),
      ('À emporter', stats.emporterCA, stats.emporterCount, Colors.lightBlueAccent),
    ].where((e) => e.$2 > 0.01).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TYPE DE SERVICE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(_money(total), style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 55,
                    sections: entries.map((e) {
                      final pct = (e.$2 / total) * 100;
                      return PieChartSectionData(
                        value: e.$2,
                        title: pct >= 10 ? "${pct.toStringAsFixed(0)}%" : "",
                        color: e.$4,
                        radius: 35,
                        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      );
                    }).toList(),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("TOTAL", style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    Text(_money(total), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          ...entries.map((e) {
            final pct = (e.$2 / total) * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: e.$4, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text("${e.$1} (${e.$3} cmd)", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))),
                    Text(_money(e.$2), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: e.$4.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        "${pct.toStringAsFixed(0)}%",
                        style: TextStyle(color: e.$4, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation(e.$4),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Line chart CA cumulé sur la période
  Widget _buildDailyLineChart(AdvancedStatsSummary stats) {
    final entries = stats.caPerDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    double cumul = 0;
    for (int i = 0; i < entries.length; i++) {
      cumul += entries[i].value;
      spots.add(FlSpot(i.toDouble(), cumul));
    }
    final maxY = spots.last.y * 1.15;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("ÉVOLUTION DU CA CUMULÉ", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(_money(cumul), style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withValues(alpha: 0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: maxY > 0 ? maxY / 4 : 1,
                      getTitlesWidget: (value, meta) => Text(
                        "${value.toInt()}€",
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < 0 || value.toInt() >= entries.length) return const SizedBox();
                        if (entries.length > 7 && value.toInt() % 2 != 0) return const SizedBox();
                        try {
                          final date = DateFormat('yyyy-MM-dd').parse(entries[value.toInt()].key);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('dd/MM').format(date),
                              style: const TextStyle(color: Colors.white38, fontSize: 9),
                            ),
                          );
                        } catch (_) {
                          return const SizedBox();
                        }
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0, maxX: (entries.length - 1).toDouble(),
                minY: 0, maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: Colors.greenAccent,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: Colors.greenAccent,
                        strokeWidth: 2,
                        strokeColor: kDarkBg,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [Colors.greenAccent.withValues(alpha: 0.3), Colors.greenAccent.withValues(alpha: 0.0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Colors.black87,
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      final idx = spot.x.toInt();
                      String dateLabel = "";
                      try {
                        if (idx >= 0 && idx < entries.length) {
                          dateLabel = DateFormat('dd/MM/yyyy').format(DateFormat('yyyy-MM-dd').parse(entries[idx].key));
                        }
                      } catch (_) {}
                      return LineTooltipItem(
                        "$dateLabel\n${_money(spot.y)}",
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NOUVEAU — Top suppléments PAYANTS (avec CA généré)
  Widget _buildTopPaidOptionsSection(AdvancedStatsSummary stats) {
    final totalCA = stats.paidOptionsTotalCA;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            collapsedIconColor: Colors.white54,
            iconColor: Colors.amberAccent,
            title: Row(children: [
              const Icon(Icons.euro, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("SUPPLÉMENTS PAYANTS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
              ),
              if (totalCA > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text("+${_money(totalCA)}", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900, fontSize: 11)),
                ),
            ]),
            children: [
              ...stats.topPaidOptions.take(10).toList().asMap().entries.map((entry) {
                final index = entry.key;
                final e = entry.value;
                final ca = stats.paidOptionCA[e.key] ?? 0.0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
                  child: Row(children: [
                    Container(
                      width: 22, height: 22, alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index < 3 ? Colors.amberAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text("${index + 1}", style: TextStyle(color: index < 3 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text("${e.value}x", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(_money(ca), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                );
              }),
              // Footer total
              if (stats.topPaidOptions.length > 10) Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                child: Text("+ ${stats.topPaidOptions.length - 10} autres suppléments...",
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NOUVEAU — Top choix GRATUITS (sauces, options incluses)
  Widget _buildTopFreeOptionsSection(AdvancedStatsSummary stats) {
    final total = stats.topFreeOptions.fold<int>(0, (a, b) => a + b.value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            collapsedIconColor: Colors.white54,
            iconColor: Colors.cyanAccent,
            title: Row(children: [
              const Icon(Icons.local_dining, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("CHOIX GRATUITS / SAUCES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text("$total demandes", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ]),
            children: [
              ...stats.topFreeOptions.take(15).toList().asMap().entries.map((entry) {
                final index = entry.key;
                final e = entry.value;
                final ratio = total > 0 ? e.value / total : 0.0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 22, height: 22, alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: index < 3 ? Colors.cyan.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text("${index + 1}", style: TextStyle(color: index < 3 ? Colors.cyanAccent : Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text("${e.value}x", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text("${(ratio * 100).toStringAsFixed(0)}%",
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (stats.topFreeOptions.length > 15) Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                child: Text("+ ${stats.topFreeOptions.length - 15} autres choix...",
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlopProductsSection(AdvancedStatsSummary stats) {
    // Les flops ne sont intéressants que s'il y a au moins quelques produits
    if (stats.productQty.length < 5) return const SizedBox.shrink();
    final flops = stats.productQty.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            collapsedIconColor: Colors.white54,
            iconColor: Colors.redAccent,
            title: Row(children: const [
              Icon(Icons.trending_down, size: 14, color: Colors.redAccent),
              SizedBox(width: 8),
              Text("PRODUITS LES MOINS VENDUS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
            ]),
            children: [
              ...flops.take(10).map((e) {
                final revenue = stats.productCA[e.key] ?? 0.0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text("${e.value}x", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(_money(revenue), style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ONGLET 3 : LISTE DES SESSIONS ET TICKETS
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

        final List<model.Transaction> allTxs = (snapshot.data?[0] as List<model.Transaction>?) ?? <model.Transaction>[];
        final List<model.TillSession> rawSessions = (snapshot.data?[1] as List<model.TillSession>?) ?? <model.TillSession>[];
        // ✅ FIX sessions complet — logique de CHEVAUCHEMENT
        // Une session "touche" la période si elle ne se finit pas avant le début
        // ET ne commence pas après la fin. Couvre tous les cas :
        //   - Session entièrement dans la période ✓
        //   - Session ouverte avant, fermée pendant ✓
        //   - Session ouverte pendant, fermée après ✓
        //   - Session ouverte avant, fermée après (chevauche entièrement) ✓
        //   - Session encore ouverte qui a commencé avant la fin de la période ✓
        final start = _selectedRange.start;
        final end = _selectedRange.end;
        final List<model.TillSession> historySessions = rawSessions.where((s) {
          // On ne montre que les sessions clôturées (l'active est gérée séparément)
          if (s.isClosed != true) return false;
          final close = s.closingTime;
          if (close == null) return false;
          // Chevauchement = pas de gap des deux côtés
          final endsAfterStart = !close.isBefore(start);   // fermée à >= start
          final startsBeforeEnd = !s.openingTime.isAfter(end); // ouverte à <= end
          return endsAfterStart && startsBeforeEnd;
        }).toList()
          ..sort((a, b) {
            final at = a.closingTime ?? a.openingTime;
            final bt = b.closingTime ?? b.openingTime;
            return bt.compareTo(at);
          });

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

            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
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
                          _buildDetailedSessionCard(activeSession, isActive: true),
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
                          ...historySessions.map((s) => _buildDetailedSessionCard(s, isActive: false)),
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

  Widget _buildDetailedSessionCard(model.TillSession session, {required bool isActive}) {
    final dateStr = DateFormat('dd/MM/yyyy').format(session.openingTime);
    final openTime = DateFormat('HH:mm').format(session.openingTime);
    final closeTime = session.closingTime != null ? DateFormat('HH:mm').format(session.closingTime!) : '--:--';
    // ✅ FIX — détecte si la session a traversé minuit (ouvert un jour, fermé un autre)
    final isCrossMidnight = session.closingTime != null &&
        DateFormat('yyyy-MM-dd').format(session.closingTime!) !=
            DateFormat('yyyy-MM-dd').format(session.openingTime);
    final closeDate = session.closingTime != null
        ? DateFormat('dd/MM').format(session.closingTime!) : '';

    final initialCash = session.initialCash;
    final finalCash = session.finalCash;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: kCardBg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isActive ? Colors.greenAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05))
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openSessionDetailModal(session),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.greenAccent.withValues(alpha: 0.1) : Colors.indigoAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(isActive ? Icons.point_of_sale : Icons.history, color: isActive ? Colors.greenAccent : Colors.indigoAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isActive ? "SESSION EN COURS" : "SESSION DU $dateStr",
                          style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.greenAccent : Colors.white, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                            children: [
                              const Icon(Icons.lock_open, color: Colors.greenAccent, size: 12),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text("Ouverture : $openTime",
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]
                        ),
                        const SizedBox(height: 2),
                        Row(
                            children: [
                              Icon(session.closingTime != null ? Icons.lock : Icons.lock_clock, color: session.closingTime != null ? Colors.redAccent : Colors.amberAccent, size: 12),
                              const SizedBox(width: 6),
                              // ✅ FIX — affiche la date si cross-midnight (ex: ouvert 1er, fermé 2)
                              Flexible(
                                child: Text(
                                  isCrossMidnight ? "Fermeture : $closeDate à $closeTime" : "Fermeture : $closeTime",
                                  style: TextStyle(color: session.closingTime != null ? Colors.redAccent : Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCrossMidnight) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                  child: const Text("NUIT", style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ]
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white12, height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Fond initial", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      Text(_money(initialCash), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  if (finalCash != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Espèces déclarées", style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Text(_money(finalCash), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    )
                  else if (isActive)
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Statut", style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Text("En cours de vente", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openSessionDetailModal(session),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text("VOIR LE DÉTAIL & COMMANDES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.indigoAccent.withValues(alpha: 0.15),
                      foregroundColor: isActive ? Colors.greenAccent : Colors.indigoAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS UI COMMUNS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterBar(String storeId) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _filterBtn("Aujourd'hui", DateFilter.today, storeId),
            _filterBtn("Hier", DateFilter.yesterday, storeId),
            _filterBtn("Cette semaine", DateFilter.thisWeek, storeId),
            _filterBtn("Ce mois", DateFilter.thisMonth, storeId),
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
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.white : Colors.white.withValues(alpha: 0.15)),
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

  Widget _buildTransactionCard(model.Transaction tx) {
    final primaryColor = _getPrimaryPaymentColor(tx);
    final shortId = tx.id.length >= 6 ? tx.id.substring(0, 6) : tx.id;
    final mainTitle = tx.identifier.isNotEmpty ? tx.identifier : "Ticket #$shortId";

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      color: Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: primaryColor.withValues(alpha: 0.1), child: _getPaymentIcon(tx, size: 20, color: primaryColor)),
        title: Text("$mainTitle - ${DateFormat('HH:mm').format(tx.timestamp)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: _buildPaymentChips(tx)),
        trailing: Text(_money(tx.total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
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
    final isBorne = _isBorneTx(t);
    return isBorne ? Colors.tealAccent : Colors.indigoAccent;
  }

  Icon _getPaymentIcon(model.Transaction t, {double size = 20, Color? color}) {
    if (t.paymentMethods.keys.length > 1) return Icon(Icons.call_split, color: color, size: size);
    final key = t.paymentMethods.keys.first;
    if (key == 'Cash') return Icon(Icons.payments, color: color, size: size);
    if (key == 'Ticket') return Icon(Icons.restaurant, color: color, size: size);
    final isBorne = _isBorneTx(t);
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
            final isBorne = _isBorneTx(t);
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODALE INTERACTIVE DE DÉTAIL DE SESSION (STYLE CAISSE)
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
      return tx.paymentMethods.containsKey('Card_Kiosk') || (tx.paymentMethods.containsKey('Card') && tx.source.toLowerCase() == 'borne');
    }
    if (_activeFilter == 'Comptoir') {
      return tx.paymentMethods.containsKey('Card_Counter') || (tx.paymentMethods.containsKey('Card') && tx.source.toLowerCase() != 'borne');
    }
    if (_activeFilter == 'Cash') return tx.paymentMethods.containsKey('Cash');
    if (_activeFilter == 'TR') return tx.paymentMethods.containsKey('Ticket');

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = !widget.session.isClosed;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    return DraggableScrollableSheet(
      initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<List<model.Transaction>>(
          stream: widget.repository.getSessionTransactions(widget.session.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
            final allTransactions = snapshot.data ?? <model.Transaction>[];
            final filteredTransactions = allTransactions.where(_matchesFilter).toList();
            filteredTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

            double totalSales = 0.0, cashSales = 0.0, cbKioskSales = 0.0, cbCounterSales = 0.0, ticketSales = 0.0;

            for (var t in allTransactions) {
              totalSales += t.total;
              t.paymentMethods.forEach((method, amount) {
                double val = (amount as num).toDouble();
                if (method == 'Card_Kiosk') {
                  cbKioskSales += val;
                } else if (method == 'Card_Counter') {
                  cbCounterSales += val;
                } else if (method == 'Cash') {
                  cashSales += val;
                } else if (method == 'Ticket') {
                  ticketSales += val;
                } else if (method == 'Card') {
                  final isBorne = _isBorneTx(t);
                  if (isBorne) {
                    cbKioskSales += val;
                  } else {
                    cbCounterSales += val;
                  }
                }
              });
            }

            final theoreticalTotal = widget.session.initialCash + cashSales;
            final realTotal = widget.session.finalCash ?? 0.0;
            final discrepancy = isActive ? 0.0 : realTotal - theoreticalTotal;

            return CustomScrollView(
              controller: scrollController,
              slivers: [
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
                            Text(_money(totalSales), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          ],
                        )
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("BILAN DE CAISSE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.1)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                          child: isSmallScreen
                              ? Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildInfoRow("Fond Initial", widget.session.initialCash, Colors.white)),
                                  Expanded(child: _buildInfoRow("Théorique", theoreticalTotal, Colors.amberAccent)),
                                ],
                              ),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white10)),
                              Row(
                                children: [
                                  Expanded(child: _buildInfoRow("Réel Déclaré", isActive ? 0.0 : realTotal, Colors.white)),
                                  if (!isActive) Expanded(child: _buildInfoRow("Écart", discrepancy, discrepancy.abs() < 0.05 ? Colors.greenAccent : Colors.redAccent)),
                                  if (isActive) const Spacer(),
                                ],
                              ),
                            ],
                          )
                              : Row(
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
                        isSmallScreen
                            ? Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildSummaryCard("BORNES", cbKioskSales, Icons.touch_app, Colors.tealAccent)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildSummaryCard("COMPTOIR", cbCounterSales, Icons.point_of_sale, Colors.indigoAccent)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildSummaryCard("ESPECES", cashSales, Icons.payments, Colors.greenAccent)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildSummaryCard("T. RESTO", ticketSales, Icons.restaurant, Colors.orangeAccent)),
                              ],
                            ),
                          ],
                        )
                            : Row(
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
        Text("${amount > 0 && label == 'Écart' ? '+' : ''}${_money(amount)}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _buildSummaryCard(String label, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 9), overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 8),
          FittedBox(child: Text(_money(amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color))),
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
              showCheckmark: false,
              label: Text(filter),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: Colors.black,
              ),
              selected: isSelected,
              onSelected: (val) => setState(() => _activeFilter = filter),
              selectedColor: Colors.greenAccent,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? Colors.greenAccent : Colors.transparent,
                width: 1,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransactionCard(model.Transaction tx) {
    final primaryColor = _getPrimaryPaymentColor(tx);
    final shortId = tx.id.length >= 6 ? tx.id.substring(0, 6) : tx.id;
    final mainTitle = tx.identifier.isNotEmpty ? tx.identifier : "Ticket #$shortId";

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: primaryColor.withValues(alpha: 0.1), child: _getPaymentIcon(tx, size: 20, color: primaryColor)),
        title: Text("$mainTitle - ${DateFormat('HH:mm').format(tx.timestamp)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6.0), child: _buildPaymentChips(tx)),
        trailing: Text(_money(tx.total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
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
    final isBorne = _isBorneTx(t);
    return isBorne ? Colors.tealAccent : Colors.indigoAccent;
  }

  Icon _getPaymentIcon(model.Transaction t, {double size = 20, Color? color}) {
    if (t.paymentMethods.keys.length > 1) return Icon(Icons.call_split, color: color, size: size);
    final key = t.paymentMethods.keys.first;
    if (key == 'Cash') return Icon(Icons.payments, color: color, size: size);
    if (key == 'Ticket') return Icon(Icons.restaurant, color: color, size: size);
    final isBorne = _isBorneTx(t);
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
            final isBorne = _isBorneTx(t);
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.3))),
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
      padding: EdgeInsets.all(small ? 14 : 20),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color, size: small ? 14 : 16), const SizedBox(width: 8), Expanded(child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, overflow: TextOverflow.ellipsis)))]),
          SizedBox(height: small ? 8 : 12),
          FittedBox(child: Text(value, style: TextStyle(color: Colors.white, fontSize: small ? 18 : 32, fontWeight: FontWeight.w900))),
          if (subtitle.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: small ? 10 : 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
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
  Widget build(BuildContext context) { return FadeTransition(opacity: Tween(begin: 0.4, end: 1.0).animate(_c), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 6)]))); }
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: sortedHours.map((hour) {
            double ca = stats.caPerHour[hour]!;
            double ratio = maxCa > 0 ? ca / maxCa : 0;
            bool isPeak = ca == maxCa;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tooltip(
                message: _money(ca),
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
              ),
            );
          }).toList(),
        ),
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
              if (transaction.identifier.isNotEmpty) Text("Réf: ${transaction.identifier}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text("Date: ${DateFormat('dd/MM/yyyy HH:mm').format(transaction.timestamp)}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              const Text("Produits :", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              ...transaction.items.map((item) {
                final qty = item['quantity'] ?? 1;
                final name = item['name'] ?? 'Inconnu';
                final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text("${qty}x $name", style: const TextStyle(color: Colors.white70))),
                      Text(_money(price * (qty as num).toDouble()), style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                );
              }),
              if (transaction.discountAmount > 0.001) ...[
                const Divider(color: Colors.white12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Remise", style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w600)),
                    Text("- ${_money(transaction.discountAmount)}", style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
              const Divider(color: Colors.white24, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL PAYÉ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  Text(_money(transaction.total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("dont TVA", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(_money(transaction.vatTotal), style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                    Text(_money((e.value as num).toDouble()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
// MOTEUR LOGIQUE STATISTIQUES (REFONDU, RICHI)
// ─────────────────────────────────────────────────────────────────────────────

/// Une ligne de ventilation TVA pour un taux donné.
class VatBreakdownEntry {
  double baseHt;
  double tva;
  VatBreakdownEntry({this.baseHt = 0.0, this.tva = 0.0});
}

class AdvancedStatsSummary {
  // Totaux principaux
  double caTotal = 0.0;        // CA TTC
  double tvaTotal = 0.0;       // TVA collectée (somme des vatTotal officiels)
  double caHt = 0.0;           // CA HT = caTotal - tvaTotal
  double totalDiscounts = 0.0; // Somme des remises appliquées
  int discountsCount = 0;      // Nombre de tickets avec remise
  int count = 0;               // Nombre de tickets

  // Service
  int surPlaceCount = 0;
  double surPlaceCA = 0.0;
  int emporterCount = 0;
  double emporterCA = 0.0;

  // Canal
  int borneCount = 0;
  double borneCA = 0.0;
  int caisseCount = 0;
  double caisseCA = 0.0;

  // Temporel
  Map<int, double> caPerHour = {};
  Map<String, double> caPerDay = {}; // clé: 'yyyy-MM-dd'
  int? peakHour;

  // Produits
  Map<String, int> productQty = {};
  Map<String, double> productCA = {};
  // ✅ NOUVEAU — top suppléments/options séparés gratuits / payants
  Map<String, int> freeOptionQty = {};       // Sauces, choix sans coût
  Map<String, int> paidOptionQty = {};       // Extras payants (qty)
  Map<String, double> paidOptionCA = {};     // Extras payants (CA généré)

  // Paiements
  Map<String, double> payments = {
    'CB Borne': 0.0,
    'CB Comptoir': 0.0,
    'Espèces': 0.0,
    'Tickets Resto': 0.0,
    'Autres': 0.0,
  };

  // TVA ventilée par taux (pour Z légal) — ordre préservé : 5.5%, 10%, 20%
  final Map<String, VatBreakdownEntry> vatByRate = {
    '5.5%': VatBreakdownEntry(),
    '10%': VatBreakdownEntry(),
    '20%': VatBreakdownEntry(),
  };

  // Extrêmes
  double maxTicket = 0.0;
  String maxTicketLabel = "-";
  // ✅ FIX — initialisé à double.maxFinite pour que la comparaison fonctionne
  double minTicket = double.maxFinite;
  String minTicketLabel = "-";
  double bestDayCA = 0.0;
  String bestDayLabel = "-";

  AdvancedStatsSummary(List<model.Transaction> transactions) {
    count = transactions.length;
    if (count == 0) { minTicket = 0.0; return; }

    for (var t in transactions) {
      final txTotal = t.total.toDouble();
      caTotal += txTotal;
      // ✅ NOTE — tvaTotal sera recalculé depuis vatByRate à la fin (sync avec l'affichage légal)

      // Remises
      if (t.discountAmount > 0.001) {
        totalDiscounts += t.discountAmount;
        discountsCount++;
      }

      // Extrêmes ticket
      if (txTotal > maxTicket) {
        maxTicket = txTotal;
        maxTicketLabel = DateFormat('dd/MM HH:mm').format(t.timestamp);
      }
      // ✅ FIX — minTicket comparé correctement
      if (txTotal < minTicket && txTotal > 0) {
        minTicket = txTotal;
        minTicketLabel = DateFormat('dd/MM HH:mm').format(t.timestamp);
      }

      // Distribution horaire (heure réelle pour le graphique)
      final hour = t.timestamp.hour;
      caPerHour[hour] = (caPerHour[hour] ?? 0.0) + txTotal;

      // ✅ FIX — journée commerciale pour caPerDay (vente à 02h = jour précédent)
      final businessTs = t.timestamp.hour < kBusinessDayStartHour
          ? t.timestamp.subtract(const Duration(days: 1))
          : t.timestamp;
      final dayKey = DateFormat('yyyy-MM-dd').format(businessTs);
      caPerDay[dayKey] = (caPerDay[dayKey] ?? 0.0) + txTotal;

      // Canal — ✅ FIX helper centralisé
      bool isBorne = _isBorneTx(t);
      if (isBorne) {
        borneCount++;
        borneCA += txTotal;
      } else {
        caisseCount++;
        caisseCA += txTotal;
      }

      // Service — ✅ FIX helper centralisé
      if (_isSurPlaceTx(t)) {
        surPlaceCount++;
        surPlaceCA += txTotal;
      } else {
        emporterCount++;
        emporterCA += txTotal;
      }

      // Paiements — ✅ FIX cast sécurisé (supporte String et num)
      t.paymentMethods.forEach((method, val) {
        double amount = 0.0;
        if (val is num) {
          amount = val.toDouble();
        } else if (val is String) {
          amount = double.tryParse(val) ?? 0.0;
        }
        if (method == 'Cash') {
          payments['Espèces'] = (payments['Espèces'] ?? 0) + amount;
        } else if (method == 'Ticket') {
          payments['Tickets Resto'] = (payments['Tickets Resto'] ?? 0) + amount;
        } else if (method == 'Card_Kiosk') {
          payments['CB Borne'] = (payments['CB Borne'] ?? 0) + amount;
        } else if (method == 'Card_Counter') {
          payments['CB Comptoir'] = (payments['CB Comptoir'] ?? 0) + amount;
        } else if (method == 'Card') {
          if (isBorne) {
            payments['CB Borne'] = (payments['CB Borne'] ?? 0) + amount;
          } else {
            payments['CB Comptoir'] = (payments['CB Comptoir'] ?? 0) + amount;
          }
        } else {
          payments['Autres'] = (payments['Autres'] ?? 0) + amount;
        }
      });

      // Ventilation TVA par taux (depuis les items)
      final itemsTtcSum = t.items.fold<double>(0.0, (acc, item) {
        final p = (item['price'] as num?)?.toDouble() ?? 0.0;
        final q = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        return acc + (p * q);
      });
      final discountRatio = (itemsTtcSum > 0.001 && t.discountAmount > 0.001)
          ? (1.0 - (t.discountAmount / itemsTtcSum)).clamp(0.0, 1.0)
          : 1.0;

      for (var item in t.items) {
        final name = item['name']?.toString() ?? 'Article inconnu';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final taxRate = (item['vatRate'] as num?)?.toDouble() ?? (item['taxRate'] as num?)?.toDouble() ?? 10.0;

        final itemCaTtc = price * qty * discountRatio;
        final itemHt = itemCaTtc / (1 + (taxRate / 100));
        final itemTva = itemCaTtc - itemHt;

        String rateKey;
        if ((taxRate - 5.5).abs() < 0.001) {
          rateKey = '5.5%';
        } else if ((taxRate - 20.0).abs() < 0.001) {
          rateKey = '20%';
        } else {
          rateKey = '10%';
        }

        final entry = vatByRate[rateKey]!;
        entry.baseHt += itemHt;
        entry.tva += itemTva;

        if (price > 0) {
          productQty[name] = (productQty[name] ?? 0) + qty;
          // ✅ FIX — productCA avec discount appliqué (cohérent avec caTotal)
          productCA[name] = (productCA[name] ?? 0.0) + (price * qty * discountRatio);
        }

        // ✅ NOUVEAU — collecter les suppléments/options en séparant gratuits et payants
        final options = item['options'] as List? ?? [];
        for (var section in options) {
          if (section is Map) {
            final sectionItems = section['items'] as List? ?? [];
            for (var opt in sectionItems) {
              if (opt is Map) {
                final optName = opt['name']?.toString() ?? '';
                if (optName.isEmpty) continue;
                // Lecture du prix du supplément (clés possibles : price, supplementPrice)
                final optPrice = (opt['supplementPrice'] as num?)?.toDouble()
                    ?? (opt['price'] as num?)?.toDouble()
                    ?? 0.0;
                if (optPrice > 0.001) {
                  // Supplément payant
                  paidOptionQty[optName] = (paidOptionQty[optName] ?? 0) + qty;
                  paidOptionCA[optName] = (paidOptionCA[optName] ?? 0.0) + (optPrice * qty * discountRatio);
                } else {
                  // Choix gratuit / option incluse
                  freeOptionQty[optName] = (freeOptionQty[optName] ?? 0) + qty;
                }
              }
            }
          }
        }
      }
    }

    // ✅ FIX — tvaTotal recalculé depuis vatByRate pour être synchro avec l'affichage légal
    tvaTotal = vatByRate.values.fold(0.0, (acc, e) => acc + e.tva);
    caHt = caTotal - tvaTotal;

    // ✅ FIX — minTicket à 0 si aucune transaction valide
    if (minTicket == double.maxFinite) minTicket = 0.0;

    if (caPerHour.isNotEmpty) {
      peakHour = caPerHour.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    if (caPerDay.isNotEmpty) {
      final best = caPerDay.entries.reduce((a, b) => a.value > b.value ? a : b);
      bestDayCA = best.value;
      try {
        bestDayLabel = DateFormat('EEEE dd MMM', 'fr_FR').format(DateFormat('yyyy-MM-dd').parse(best.key));
      } catch (_) {
        bestDayLabel = best.key;
      }
    }
  }

  double get panierMoyen => count > 0 ? caTotal / count : 0.0;
  List<MapEntry<String, int>> get sortedProductsByQty => productQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  List<MapEntry<String, double>> get sortedProductsByRevenue => productCA.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  // ✅ NOUVEAU — top options séparés
  List<MapEntry<String, int>> get topFreeOptions =>
      freeOptionQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  List<MapEntry<String, int>> get topPaidOptions =>
      paidOptionQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  // ✅ Garder l'ancien getter pour rétro-compatibilité (combinaison des deux)
  List<MapEntry<String, int>> get topOptions {
    final combined = <String, int>{};
    freeOptionQty.forEach((k, v) => combined[k] = (combined[k] ?? 0) + v);
    paidOptionQty.forEach((k, v) => combined[k] = (combined[k] ?? 0) + v);
    return combined.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
  // CA total généré par les suppléments payants
  double get paidOptionsTotalCA => paidOptionCA.values.fold(0.0, (a, b) => a + b);
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT PDF COMPLET (Z DE CAISSE PROFESSIONNEL)
// ─────────────────────────────────────────────────────────────────────────────

class StatsPdfExporter {
  static Future<void> generateAndSharePdf({
    required AdvancedStatsSummary stats,
    required List<model.TillSession> sessions,
    required String companyName,
    required String restaurantName,
    required String address,
    required String zipCity,
    required String phone,
    required String siret,
    required String tvaNumber,
    required DateTime startDate,
    required DateTime endDate,
    required String filterLabel,
  }) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold));

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(startDate);
    final endStr = DateFormat('dd/MM/yyyy HH:mm').format(endDate);
    final genDate = DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.now());

    // Helpers PDF
    pw.Widget sectionTitle(String t) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
    );

    pw.Widget kvRow(String k, String v, {bool bold = false, PdfColor? color}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.black)),
        ],
      ),
    );

    String fmt(num v) => "${v.toStringAsFixed(2).replaceAll('.', ',')} €";
    String pctStr(double v, double t) => t > 0 ? "${((v / t) * 100).toStringAsFixed(1).replaceAll('.', ',')}%" : "0%";

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(restaurantName, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.Text("Z de caisse $dateStr - $endStr", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("Généré le $genDate", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text("Page ${ctx.pageNumber}/${ctx.pagesCount}", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ),
      build: (ctx) => [
        // ─── EN-TÊTE ───
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(restaurantName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  if (companyName.isNotEmpty && companyName != restaurantName)
                    pw.Text(companyName, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  if (address.isNotEmpty) pw.Text(address, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  if (zipCity.isNotEmpty) pw.Text(zipCity, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  if (phone.isNotEmpty) pw.Text("Tél : $phone", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  if (siret.isNotEmpty) pw.Text("SIRET : $siret", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  if (tvaNumber.isNotEmpty) pw.Text("N° TVA : $tvaNumber", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.black, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("Z DE CAISSE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.white)),
                  pw.SizedBox(height: 2),
                  pw.Text(filterLabel.toUpperCase(), style: pw.TextStyle(fontSize: 9, color: PdfColors.white)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Période : du $dateStr", style: pw.TextStyle(fontSize: 10)),
              pw.Text("au $endStr", style: pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        // ─── SECTION 1 : RÉCAP COMPTABLE ───
        sectionTitle("1. RÉCAPITULATIF COMPTABLE"),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
          child: pw.Column(
            children: [
              kvRow("Nombre de tickets", "${stats.count}", bold: true),
              kvRow("Panier moyen", fmt(stats.panierMoyen)),
              kvRow("Ticket maximum", fmt(stats.maxTicket)),
              kvRow("Ticket minimum", fmt(stats.minTicket)),
              pw.Divider(color: PdfColors.grey300, height: 12),
              kvRow("CA HT", fmt(stats.caHt), bold: true, color: PdfColors.blue800),
              kvRow("TVA totale collectée", fmt(stats.tvaTotal), bold: true, color: PdfColors.orange800),
              kvRow("Remises accordées", fmt(stats.totalDiscounts), color: PdfColors.pink800),
              pw.Divider(color: PdfColors.grey700, height: 12),
              kvRow("CHIFFRE D'AFFAIRES TTC", fmt(stats.caTotal), bold: true, color: PdfColors.green800),
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        // ─── SECTION 2 : TVA LÉGALE ───
        sectionTitle("2. TVA LÉGALE - VENTILATION PAR TAUX"),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pdfCell("TAUX", bold: true, align: pw.TextAlign.center),
                _pdfCell("BASE HT", bold: true, align: pw.TextAlign.right),
                _pdfCell("TVA", bold: true, align: pw.TextAlign.right),
                _pdfCell("TOTAL TTC", bold: true, align: pw.TextAlign.right),
              ],
            ),
            ...stats.vatByRate.entries.map((e) => pw.TableRow(
              children: [
                _pdfCell(e.key, align: pw.TextAlign.center),
                _pdfCell(fmt(e.value.baseHt), align: pw.TextAlign.right),
                _pdfCell(fmt(e.value.tva), align: pw.TextAlign.right),
                _pdfCell(fmt(e.value.baseHt + e.value.tva), align: pw.TextAlign.right),
              ],
            )),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _pdfCell("TOTAL", bold: true, align: pw.TextAlign.center),
                _pdfCell(fmt(stats.caHt), bold: true, align: pw.TextAlign.right),
                _pdfCell(fmt(stats.tvaTotal), bold: true, align: pw.TextAlign.right),
                _pdfCell(fmt(stats.caTotal), bold: true, align: pw.TextAlign.right),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),

        // ─── SECTION 3 : MODES DE PAIEMENT ───
        sectionTitle("3. RÉPARTITION DES ENCAISSEMENTS"),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pdfCell("MODE", bold: true),
                _pdfCell("MONTANT", bold: true, align: pw.TextAlign.right),
                _pdfCell("%", bold: true, align: pw.TextAlign.right),
              ],
            ),
            ...stats.payments.entries.where((e) => e.value > 0.001).map((e) {
              final total = stats.payments.values.fold<double>(0, (a, b) => a + b);
              return pw.TableRow(
                children: [
                  _pdfCell(e.key),
                  _pdfCell(fmt(e.value), align: pw.TextAlign.right),
                  _pdfCell(pctStr(e.value, total), align: pw.TextAlign.right),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 16),

        // ─── SECTION 4 : CANAL & SERVICE ───
        sectionTitle("4. CANAL DE VENTE & TYPE DE SERVICE"),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.Expanded(child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Canal", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 6),
                  kvRow("Borne (${stats.borneCount})", "${fmt(stats.borneCA)} (${pctStr(stats.borneCA, stats.caTotal)})"),
                  kvRow("Caisse (${stats.caisseCount})", "${fmt(stats.caisseCA)} (${pctStr(stats.caisseCA, stats.caTotal)})"),
                ],
              ),
            )),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Service", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 6),
                  kvRow("Sur place (${stats.surPlaceCount})", "${fmt(stats.surPlaceCA)} (${pctStr(stats.surPlaceCA, stats.caTotal)})"),
                  kvRow("À emporter (${stats.emporterCount})", "${fmt(stats.emporterCA)} (${pctStr(stats.emporterCA, stats.caTotal)})"),
                ],
              ),
            )),
          ],
        ),
        pw.SizedBox(height: 16),

        // ─── SECTION 5 : CA PAR JOUR (si multi-jour) ───
        if (stats.caPerDay.length > 1) ...[
          sectionTitle("5. CA PAR JOUR"),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell("DATE", bold: true),
                  _pdfCell("CA TTC", bold: true, align: pw.TextAlign.right),
                ],
              ),
              ...(stats.caPerDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) {
                String label;
                try {
                  label = DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(DateFormat('yyyy-MM-dd').parse(e.key));
                } catch (_) {
                  label = e.key;
                }
                return pw.TableRow(children: [
                  _pdfCell(label),
                  _pdfCell(fmt(e.value), align: pw.TextAlign.right),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 16),
        ],

        // ─── SECTION 6 : TOP PRODUITS ───
        sectionTitle("6. TOP PRODUITS (classement par quantité)"),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pdfCell("#", bold: true, align: pw.TextAlign.center),
                _pdfCell("PRODUIT", bold: true),
                _pdfCell("QTÉ", bold: true, align: pw.TextAlign.center),
                _pdfCell("CA TTC", bold: true, align: pw.TextAlign.right),
              ],
            ),
            ...stats.sortedProductsByQty.take(30).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              return pw.TableRow(children: [
                _pdfCell("${i + 1}", align: pw.TextAlign.center),
                _pdfCell(e.key),
                _pdfCell("${e.value}", align: pw.TextAlign.center),
                _pdfCell(fmt(stats.productCA[e.key] ?? 0), align: pw.TextAlign.right),
              ]);
            }),
          ],
        ),

        // ─── SECTION 7 : SESSIONS DE CAISSE ───
        if (sessions.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          sectionTitle("7. SESSIONS DE CAISSE"),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell("OUVERTURE", bold: true),
                  _pdfCell("FERMETURE", bold: true),
                  _pdfCell("FOND INITIAL", bold: true, align: pw.TextAlign.right),
                  _pdfCell("ESPÈCES DÉCL.", bold: true, align: pw.TextAlign.right),
                  _pdfCell("STATUT", bold: true, align: pw.TextAlign.center),
                ],
              ),
              ...sessions.map((s) => pw.TableRow(children: [
                _pdfCell(DateFormat('dd/MM/yyyy HH:mm').format(s.openingTime)),
                _pdfCell(s.closingTime != null ? DateFormat('dd/MM/yyyy HH:mm').format(s.closingTime!) : "—"),
                _pdfCell(fmt(s.initialCash), align: pw.TextAlign.right),
                _pdfCell(s.finalCash != null ? fmt(s.finalCash!) : "—", align: pw.TextAlign.right),
                _pdfCell(s.isClosed ? "Clôturée" : "Ouverte", align: pw.TextAlign.center),
              ])),
            ],
          ),
        ],

        // ─── MENTIONS LÉGALES ───
        pw.SizedBox(height: 24),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Mentions légales", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
              pw.SizedBox(height: 4),
              pw.Text(
                "Document à conserver selon la réglementation française (articles L123-22 et R123-175 du Code de commerce) : "
                    "les livres, documents comptables et pièces justificatives doivent être conservés pendant 10 ans. "
                    "Ce document constitue un récapitulatif des ventes enregistrées sur la période indiquée.",
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ],
    ));

    final bytes = await pdf.save();
    final fileName = 'Z_Caisse_${DateFormat('yyyyMMdd_HHmm').format(startDate)}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static pw.Widget _pdfCell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT CSV (FORMAT FR, compatible Excel)
// ─────────────────────────────────────────────────────────────────────────────

class StatsCsvExporter {
  /// Génère un CSV structuré (plusieurs sections dans le même fichier)
  /// et partage le fichier via share_plus.
  static Future<void> generateAndShareCsv({
    required List<model.Transaction> transactions,
    required AdvancedStatsSummary stats,
    required String companyName,
    required String restaurantName,
    required String address,
    required String zipCity,
    required String siret,
    required String tvaNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // On utilise ';' comme séparateur (standard Excel FR) + BOM UTF-8 pour les accents
    const converter = ListToCsvConverter(fieldDelimiter: ';', textDelimiter: '"');
    final buffer = StringBuffer();
    // BOM pour que Excel ouvre en UTF-8
    buffer.writeCharCode(0xFEFF);

    void writeSection(String title) {
      buffer.writeln();
      buffer.writeln(converter.convert([['=== $title ===']]));
    }

    void writeRows(List<List<dynamic>> rows) {
      for (final r in rows) {
        buffer.writeln(converter.convert([r]));
      }
    }

    String money(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

    // ─── ENTÊTE ───
    writeRows([
      ["Z DE CAISSE"],
      ["Établissement", restaurantName],
      if (companyName.isNotEmpty) ["Société", companyName],
      if (address.isNotEmpty) ["Adresse", address],
      if (zipCity.isNotEmpty) ["Code postal / Ville", zipCity],
      if (siret.isNotEmpty) ["SIRET", siret],
      if (tvaNumber.isNotEmpty) ["N° TVA", tvaNumber],
      ["Période début", DateFormat('dd/MM/yyyy HH:mm').format(startDate)],
      ["Période fin", DateFormat('dd/MM/yyyy HH:mm').format(endDate)],
      ["Généré le", DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())],
    ]);

    // ─── RÉCAP COMPTABLE ───
    writeSection("RECAPITULATIF COMPTABLE");
    writeRows([
      ["Indicateur", "Valeur"],
      ["Nombre de tickets", stats.count],
      ["CA TTC", money(stats.caTotal)],
      ["CA HT", money(stats.caHt)],
      ["TVA totale", money(stats.tvaTotal)],
      ["Remises totales", money(stats.totalDiscounts)],
      ["Nombre tickets remisés", stats.discountsCount],
      ["Panier moyen", money(stats.panierMoyen)],
      ["Ticket maximum", money(stats.maxTicket)],
      ["Ticket minimum", money(stats.minTicket)],
    ]);

    // ─── TVA LÉGALE ───
    writeSection("TVA LEGALE PAR TAUX");
    writeRows([
      ["Taux", "Base HT", "TVA", "Total TTC"],
      ...stats.vatByRate.entries.map((e) => [e.key, money(e.value.baseHt), money(e.value.tva), money(e.value.baseHt + e.value.tva)]),
      ["TOTAL", money(stats.caHt), money(stats.tvaTotal), money(stats.caTotal)],
    ]);

    // ─── PAIEMENTS ───
    writeSection("REPARTITION DES ENCAISSEMENTS");
    final totalPay = stats.payments.values.fold<double>(0.0, (a, b) => a + b);
    writeRows([
      ["Mode", "Montant", "Pourcentage"],
      ...stats.payments.entries.where((e) => e.value > 0.001).map((e) {
        final pct = totalPay > 0 ? (e.value / totalPay * 100) : 0.0;
        return [e.key, money(e.value), "${pct.toStringAsFixed(1).replaceAll('.', ',')}%"];
      }),
    ]);

    // ─── CANAL & SERVICE ───
    writeSection("CANAL DE VENTE");
    writeRows([
      ["Canal", "Nombre tickets", "CA TTC"],
      ["Borne", stats.borneCount, money(stats.borneCA)],
      ["Caisse", stats.caisseCount, money(stats.caisseCA)],
    ]);
    writeSection("TYPE DE SERVICE");
    writeRows([
      ["Service", "Nombre tickets", "CA TTC"],
      ["Sur place", stats.surPlaceCount, money(stats.surPlaceCA)],
      ["A emporter", stats.emporterCount, money(stats.emporterCA)],
    ]);

    // ─── CA PAR JOUR ───
    if (stats.caPerDay.length > 1) {
      writeSection("CA PAR JOUR");
      writeRows([
        ["Date", "CA TTC"],
        ...(stats.caPerDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => [e.key, money(e.value)]),
      ]);
    }

    // ─── CA PAR HEURE ───
    if (stats.caPerHour.isNotEmpty) {
      writeSection("CA PAR HEURE");
      writeRows([
        ["Heure", "CA TTC"],
        ...(stats.caPerHour.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => ["${e.key}h", money(e.value)]),
      ]);
    }

    // ─── TOP PRODUITS ───
    writeSection("PRODUITS VENDUS");
    writeRows([
      ["Produit", "Quantité", "CA TTC"],
      ...stats.sortedProductsByQty.map((e) => [e.key, e.value, money(stats.productCA[e.key] ?? 0)]),
    ]);

    // ─── ✅ NOUVEAU — SUPPLEMENTS PAYANTS (avec CA) ───
    if (stats.topPaidOptions.isNotEmpty) {
      writeSection("SUPPLEMENTS PAYANTS");
      writeRows([
        ["Supplément", "Quantité vendue", "CA TTC généré"],
        ...stats.topPaidOptions.map((e) => [e.key, e.value, money(stats.paidOptionCA[e.key] ?? 0)]),
        ["TOTAL", "", money(stats.paidOptionsTotalCA)],
      ]);
    }

    // ─── ✅ NOUVEAU — CHOIX GRATUITS / SAUCES ───
    if (stats.topFreeOptions.isNotEmpty) {
      writeSection("CHOIX GRATUITS / SAUCES");
      writeRows([
        ["Choix / Sauce", "Nombre de demandes"],
        ...stats.topFreeOptions.map((e) => [e.key, e.value]),
      ]);
    }

    // ─── DÉTAIL DES TRANSACTIONS ───
    writeSection("DETAIL DES TRANSACTIONS");
    writeRows([[
      "Date", "Heure", "ID Ticket", "Référence", "Canal", "Service",
      "CA TTC", "CA HT", "TVA", "Remise", "Modes paiement", "Client"
    ]]);
    final txsSorted = [...transactions]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (final t in txsSorted) {
      // ✅ FIX — utilise les helpers globaux + cast sécurisé pour paiements
      final isBorne = _isBorneTx(t);
      final isSurPlace = _isSurPlaceTx(t);
      final paymentStr = t.paymentMethods.entries.map((e) {
        final amt = e.value is num
            ? (e.value as num).toDouble()
            : double.tryParse(e.value.toString()) ?? 0.0;
        return "${e.key.replaceAll('Card_Kiosk', 'CB Borne').replaceAll('Card_Counter', 'CB Comptoir').replaceAll('Cash', 'Especes').replaceAll('Ticket', 'TR')}:${money(amt)}";
      }).join(' | ');
      writeRows([[
        DateFormat('yyyy-MM-dd').format(t.timestamp),
        DateFormat('HH:mm:ss').format(t.timestamp),
        t.id,
        t.identifier,
        isBorne ? "Borne" : "Caisse",
        isSurPlace ? "Sur place" : "A emporter",
        money(t.total),
        money(t.total - t.vatTotal),
        money(t.vatTotal),
        money(t.discountAmount),
        paymentStr,
        t.customerName ?? '',
      ]]);
    }

    // ─── LIGNES DÉTAIL PRODUITS PAR TRANSACTION ───
    writeSection("DETAIL DES LIGNES DE VENTE");
    writeRows([[
      "Date", "Heure", "ID Ticket", "Produit", "Quantité",
      "PU TTC", "Taux TVA", "Total TTC"
    ]]);
    for (final t in txsSorted) {
      for (final item in t.items) {
        final name = item['name']?.toString() ?? '';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final taxRate = (item['vatRate'] as num?)?.toDouble() ?? (item['taxRate'] as num?)?.toDouble() ?? 10.0;
        writeRows([[
          DateFormat('yyyy-MM-dd').format(t.timestamp),
          DateFormat('HH:mm:ss').format(t.timestamp),
          t.id,
          name,
          qty,
          money(price),
          "${taxRate.toStringAsFixed(1).replaceAll('.', ',')}%",
          money(price * qty),
        ]]);
      }
    }

    // ─── ÉCRITURE DU FICHIER + PARTAGE ───
    final dir = await getTemporaryDirectory();
    final fileName = 'Z_Caisse_${DateFormat('yyyyMMdd_HHmm').format(startDate)}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString(), encoding: const Utf8Codec());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Z de caisse $restaurantName',
      text: 'Z de caisse du ${DateFormat('dd/MM/yyyy').format(startDate)} au ${DateFormat('dd/MM/yyyy').format(endDate)}',
    );
  }
}