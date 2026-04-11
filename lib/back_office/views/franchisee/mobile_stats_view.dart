import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:ouiborne/core/repository/repository.dart';
import 'package:ouiborne/core/auth_provider.dart';
import 'package:ouiborne/models.dart' as model;
enum DateFilter { today, yesterday, thisWeek, custom }
class MobileStatsView extends StatefulWidget {
  const MobileStatsView({super.key});
  @override
  State<MobileStatsView> createState() => _MobileStatsViewState();
}
class _MobileStatsViewState extends State<MobileStatsView> with TickerProviderStateMixin {
  final _repository = FranchiseRepository();
  DateFilter _currentFilter = DateFilter.today;
  late DateTimeRange _selectedRange;
  late AnimationController _liveController;
  late AnimationController _statusController;
  @override
  void initState() {
    super.initState();
    _applyFilter(DateFilter.today);
    _liveController = AnimationController(duration: const Duration(seconds: 1), vsync: this)..repeat(reverse: true);
    _statusController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
  }
  @override
  void dispose() {
    _liveController.dispose();
    _statusController.dispose();
    super.dispose();
  }
  void _applyFilter(DateFilter filter) async {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (filter) {
      case DateFilter.today:
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case DateFilter.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        start = DateTime(yesterday.year, yesterday.month, yesterday.day);
        end = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;
      case DateFilter.thisWeek:
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case DateFilter.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2023),
          lastDate: now,
          builder: (context, child) => Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          start = picked.start;
          end = picked.end.add(const Duration(hours: 23, minutes: 59));
        } else { return; }
        break;
    }
    setState(() {
      _currentFilter = filter;
      _selectedRange = DateTimeRange(start: start, end: end);
    });
  }
  bool get _isLive => _currentFilter == DateFilter.today;
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).franchiseUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.black)));
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), 
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generatePdfAndShare(context, user),
        backgroundColor: Colors.black,
        elevation: 5,
        icon: const Icon(Icons.ios_share, color: Colors.white),
        label: const Text("EXPORTER LE PDF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: StreamBuilder<List<model.Transaction>>(
        stream: _repository.getTransactionsInDateRange(user.uid, startDate: _selectedRange.start, endDate: _selectedRange.end),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }
          final transactions = snapshot.data ?? [];
          double caTotal = 0;
          double tvaTotal = 0;
          Map<String, int> productQty = {};
          Map<String, double> productRev = {};
          double cbComptoire = 0;
          double cbBorne = 0;
          double especes = 0;
          double ticketsResto = 0;
          for (var t in transactions) {
            caTotal += t.total;
            tvaTotal += t.vatTotal;
            String typeCmd = t.orderType.toString().toLowerCase();
            bool isKiosk = typeCmd.contains('kiosk') || typeCmd.contains('borne');
            t.paymentMethods.forEach((method, val) {
              double amount = (val as num).toDouble();
              String key = method.toLowerCase();
              if (key.contains('cb') || key.contains('carte') || key.contains('visa') || key.contains('master')) {
                if (isKiosk) {
                  cbBorne += amount;
                } else {
                  cbComptoire += amount;
                }
              } else if (key.contains('esp') || key.contains('cash') || key.contains('liquide')) {
                especes += amount;
              } else if (key.contains('ticket') || key.contains('resto') || key.contains('tr') || key.contains('dej')) {
                ticketsResto += amount;
              } else {
                cbComptoire += amount;
              }
            });
            for (var item in t.items) {
              final name = item['name']?.toString() ?? 'Article Inconnu';
              final qty = int.tryParse(item['quantity'].toString()) ?? 1;
              final price = double.tryParse(item['price'].toString()) ?? 0.0;
              productQty[name] = (productQty[name] ?? 0) + qty;
              productRev[name] = (productRev[name] ?? 0) + (price * qty);
            }
          }
          final count = transactions.length;
          final panierMoyen = count > 0 ? caTotal / count : 0.0;
          final sortedProducts = productQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildSliverAppBar(user.companyName ?? "Dashboard"),
              if (_isLive)
                SliverToBoxAdapter(child: _buildLiveStoreStatus(user.uid)),
              SliverToBoxAdapter(
                child: Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildFilterChip("Aujourd'hui", DateFilter.today),
                      _buildFilterChip("Hier", DateFilter.yesterday),
                      _buildFilterChip("Cette Semaine", DateFilter.thisWeek),
                      _buildFilterChip("Autre...", DateFilter.custom, isIcon: true),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildBigStatCard(caTotal, count, panierMoyen),
                      const SizedBox(height: 24),
                      Row(children: [
                        Text("VENTILATION DES ENCAISSEMENTS", style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      ]),
                      const SizedBox(height: 12),
                      _buildPaymentGrid(cbComptoire, cbBorne, especes, ticketsResto),
                      const SizedBox(height: 30),
                      Row(children: [
                        Text("TOP PRODUITS", style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                        const Spacer(),
                        Text("${sortedProducts.length} Réf.", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              sortedProducts.isEmpty
                  ? const SliverFillRemaining(child: Center(child: Text("Aucune vente sur cette période", style: TextStyle(color: Colors.grey))))
                  : AnimationLimiter(
                child: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final entry = sortedProducts[index];
                      final revenue = productRev[entry.key] ?? 0.0;
                      return AnimationConfiguration.staggeredList(
                        position: index,
                        duration: const Duration(milliseconds: 375),
                        child: SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(
                            child: _buildProductTile(index, entry.key, entry.value, revenue),
                          ),
                        ),
                      );
                    },
                    childCount: sortedProducts.length,
                  ),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          );
        },
      ),
    );
  }
  Widget _buildLiveStoreStatus(String shopId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('sessions')
          .where('endTime', isNull: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        bool isOpen = false;
        String cashierName = "Fermé";
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          isOpen = true;
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          cashierName = data['openerName'] ?? data['cashierName'] ?? "Caissier";
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isOpen ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isOpen ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              FadeTransition(
                opacity: _statusController,
                child: Icon(Icons.circle, color: isOpen ? Colors.green : Colors.red, size: 12),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOpen ? "CAISSE EN LIGNE" : "CAISSE HORS LIGNE",
                    style: TextStyle(
                        color: isOpen ? Colors.green.shade800 : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5
                    ),
                  ),
                  if (isOpen)
                    Text("Session de : $cashierName", style: TextStyle(color: Colors.green.shade900, fontSize: 13, fontWeight: FontWeight.w600))
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                child: Icon(isOpen ? Icons.check : Icons.lock, size: 16, color: isOpen ? Colors.green : Colors.grey),
              )
            ],
          ),
        );
      },
    );
  }
  Widget _buildPaymentGrid(double cbC, double cbB, double esp, double tr) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _paymentCard("CB Comptoir", cbC, Icons.point_of_sale, const Color(0xFF1E88E5))),
            const SizedBox(width: 12),
            Expanded(child: _paymentCard("CB Borne", cbB, Icons.touch_app, const Color(0xFF8E24AA))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _paymentCard("Espèces", esp, Icons.euro, const Color(0xFF43A047))),
            const SizedBox(width: 12),
            Expanded(child: _paymentCard("Titres Resto", tr, Icons.restaurant, const Color(0xFFFB8C00))),
          ],
        ),
      ],
    );
  }
  Widget _paymentCard(String label, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(amount.toStringAsFixed(2) + " €", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  Widget _buildSliverAppBar(String title) {
    return SliverAppBar(
      expandedHeight: 60.0,
      pinned: true,
      backgroundColor: Colors.black,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Row(
          children: [
            if (_isLive) ...[
              FadeTransition(opacity: _liveController, child: const Icon(Icons.circle, color: Colors.red, size: 10)),
              const SizedBox(width: 6),
            ],
            Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ],
        ),
        background: Container(color: Colors.black),
      ),
    );
  }
  Widget _buildFilterChip(String label, DateFilter filter, {bool isIcon = false}) {
    final isSelected = _currentFilter == filter;
    return GestureDetector(
      onTap: () => _applyFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: isSelected ? null : Border.all(color: Colors.grey.shade300),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,2))] : [],
        ),
        child: Center(
          child: isIcon
              ? Icon(Icons.calendar_month, size: 18, color: isSelected ? Colors.white : Colors.black)
              : Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }
  Widget _buildBigStatCard(double ca, int count, double panier) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Text("CHIFFRE D'AFFAIRES TTC", style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
          const SizedBox(height: 5),
          Text("${ca.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -1.5)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _kpiItem(Icons.receipt, "$count", "Commandes"),
              Container(width: 1, height: 30, color: Colors.grey.shade200),
              _kpiItem(Icons.shopping_bag_outlined, "${panier.toStringAsFixed(2)}€", "Panier Moy."),
            ],
          )
        ],
      ),
    );
  }
  Widget _kpiItem(IconData icon, String val, String label) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
      ],
    );
  }
  Widget _buildProductTile(int index, String name, int qty, double revenue) {
    Color badgeColor;
    Color textColor = Colors.white;
    if (index == 0) { badgeColor = const Color(0xFFFFD700); textColor = Colors.black; }
    else if (index == 1) { badgeColor = const Color(0xFFC0C0C0); textColor = Colors.black; }
    else if (index == 2) { badgeColor = const Color(0xFFCD7F32); }
    else { badgeColor = Colors.grey.shade100; textColor = Colors.black54; }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
          child: Center(child: Text("${index + 1}", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("$qty ventes"),
        trailing: Text("${revenue.toStringAsFixed(0)} €", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }
  Future<void> _generatePdfAndShare(BuildContext context, model.FranchiseUser user) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)));
    try {
      final txs = await _repository.getTransactionsInDateRange(user.uid, startDate: _selectedRange.start, endDate: _selectedRange.end).first;
      double ttc = 0;
      double cbC = 0, cbB = 0, esp = 0, tr = 0;
      Map<String, int> products = {};
      for (var t in txs) {
        ttc += t.total;
        String typeCmd = t.orderType.toString().toLowerCase();
        bool isKiosk = typeCmd.contains('kiosk') || typeCmd.contains('borne');
        t.paymentMethods.forEach((method, val) {
          double v = (val as num).toDouble();
          String k = method.toLowerCase();
          if (k.contains('cb') || k.contains('carte')) isKiosk ? cbB += v : cbC += v;
          else if (k.contains('esp') || k.contains('cash')) esp += v;
          else if (k.contains('ticket') || k.contains('resto') || k.contains('tr')) tr += v;
          else cbC += v;
        });
        for (var i in t.items) {
          String n = i['name']?.toString() ?? 'Inconnu';
          products[n] = (products[n] ?? 0) + (int.tryParse(i['quantity'].toString()) ?? 1);
        }
      }
      final sortedEntries = products.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topProductsData = sortedEntries
          .take(20)
          .map((e) => [e.key, "${e.value}"])
          .toList();
      final pdf = pw.Document();
      String dateText = _currentFilter == DateFilter.today
          ? "Aujourd'hui (${DateFormat('dd/MM').format(_selectedRange.start)})"
          : "${DateFormat('dd/MM').format(_selectedRange.start)} au ${DateFormat('dd/MM').format(_selectedRange.end)}";
      pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(level: 0, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text("RAPPORT DÉTAILLÉ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
              pw.Text(user.companyName ?? ""),
            ])),
            pw.Text("Période : $dateText"),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("CA TOTAL TTC", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("${ttc.toStringAsFixed(2)} €", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                ])
            ),
            pw.SizedBox(height: 20),
            pw.Text("Ventilation des Paiements", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Mode', 'Montant'],
              data: [
                ['CB Comptoir', "${cbC.toStringAsFixed(2)} €"],
                ['CB Borne', "${cbB.toStringAsFixed(2)} €"],
                ['Espèces', "${esp.toStringAsFixed(2)} €"],
                ['Tickets Resto', "${tr.toStringAsFixed(2)} €"],
              ],
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {1: pw.Alignment.centerRight},
            ),
            pw.SizedBox(height: 20),
            pw.Text("Top 20 Produits", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Produit', 'Quantité'],
              data: topProductsData,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            ),
          ]
      ));
      Navigator.pop(context);
      await Printing.sharePdf(bytes: await pdf.save(), filename: 'Stats.pdf');
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    }
  }
}
