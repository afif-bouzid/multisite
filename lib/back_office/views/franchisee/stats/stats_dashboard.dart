import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/models.dart';
import '../../../../core/repository/repository.dart';
class StatsDashboard extends StatefulWidget {
  final String franchiseeId;
  final DateTime? startDate;
  final DateTime? endDate;
  const StatsDashboard({
    super.key,
    required this.franchiseeId,
    this.startDate,
    this.endDate,
  });
  @override
  State<StatsDashboard> createState() => _StatsDashboardState();
}
class _StatsDashboardState extends State<StatsDashboard> {
  final FranchiseRepository _repository = FranchiseRepository();
  @override
  Widget build(BuildContext context) {
    final start =
        widget.startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = widget.endDate ?? DateTime.now();
    return StreamBuilder<List<Transaction>>(
      stream: _repository.getTransactionsInDateRange(
        widget.franchiseeId,
        startDate: start,
        endDate: end,
        limit: 2000,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text("Pas assez de données pour afficher les graphiques."),
              ],
            ),
          );
        }
        final transactions = snapshot.data!;
        return _buildFixedDashboard(transactions);
      },
    );
  }
  Widget _buildFixedDashboard(List<Transaction> transactions) {
    double totalRevenue = transactions.fold(0, (sum, t) => sum + t.total);
    int totalOrders = transactions.length;
    double averageBasket = totalOrders > 0 ? totalRevenue / totalOrders : 0;
    Map<String, double> paymentStats = {};
    for (var t in transactions) {
      t.paymentMethods.forEach((method, amount) {
        paymentStats[method] =
            (paymentStats[method] ?? 0) + (amount as num).toDouble();
      });
    }
    var groupedByDay = groupBy(transactions, (Transaction t) {
      return DateFormat('yyyy-MM-dd').format(t.timestamp);
    });
    var sortedKeys = groupedByDay.keys.toList()..sort();
    Map<String, int> productCounts = {};
    Map<String, double> productRevenues = {};
    for (var t in transactions) {
      for (var item in t.items) {
        final name = item['name'] ?? 'Inconnu';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final total = (item['total'] as num?)?.toDouble() ?? 0.0;
        productCounts[name] = (productCounts[name] ?? 0) + qty;
        productRevenues[name] = (productRevenues[name] ?? 0) + total;
      }
    }
    final topProducts = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = topProducts.take(5).toList();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildKpiCard(
                    "Chiffre d'Affaires",
                    "${totalRevenue.toStringAsFixed(2)} €",
                    Icons.euro,
                    Colors.indigo),
                const SizedBox(width: 16),
                _buildKpiCard("Commandes", "$totalOrders", Icons.shopping_bag,
                    Colors.orange),
                const SizedBox(width: 16),
                _buildKpiCard(
                    "Panier Moyen",
                    "${averageBasket.toStringAsFixed(2)} €",
                    Icons.shopping_basket,
                    Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildChartContainer(
                          title: "Évolution CA",
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _getMaxY(groupedByDay),
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipColor: (_) => Colors.indigo,
                                  getTooltipItem:
                                      (group, groupIndex, rod, rodIndex) {
                                    return BarTooltipItem(
                                        '${rod.toY.toStringAsFixed(0)}€',
                                        const TextStyle(color: Colors.white));
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 30,
                                    getTitlesWidget: (value, meta) {
                                      int interval =
                                          (sortedKeys.length / 7).ceil();
                                      if (value.toInt() % interval != 0) {
                                        return const SizedBox.shrink();
                                      }
                                      if (value.toInt() >= 0 &&
                                          value.toInt() < sortedKeys.length) {
                                        final date = DateTime.parse(
                                            sortedKeys[value.toInt()]);
                                        return Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8.0),
                                            child: Text(
                                                DateFormat('dd/MM')
                                                    .format(date),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey)));
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: false),
                              barGroups:
                                  sortedKeys.asMap().entries.map((entry) {
                                final dayTotal = groupedByDay[entry.value]!
                                    .fold(0.0, (sum, t) => sum + t.total);
                                return BarChartGroupData(
                                    x: entry.key,
                                    barRods: [
                                      BarChartRodData(
                                          toY: dayTotal,
                                          color: Colors.indigo,
                                          width: 12,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(4)))
                                    ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 3,
                        child: _buildChartContainer(
                          title: "Top 5 Ventes (Quantité)",
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: top5.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final entry = top5[index];
                              final revenue = productRevenues[entry.key] ?? 0.0;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: index == 0
                                      ? Colors.amber
                                      : Colors.grey.shade100,
                                  foregroundColor:
                                      index == 0 ? Colors.white : Colors.black,
                                  radius: 14,
                                  child: Text("${index + 1}",
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ),
                                title: Text(entry.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    "${revenue.toStringAsFixed(2)} € générés",
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600)),
                                trailing: Text("${entry.value} ventes",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildChartContainer(
                    title: "Paiements",
                    child: Column(
                      children: [
                        Expanded(
                          flex: 2,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 30,
                              sections: paymentStats.entries.map((e) {
                                final color = _getPaymentColor(e.key);
                                return PieChartSectionData(
                                    color: color,
                                    value: e.value,
                                    title: '',
                                    radius: 40);
                              }).toList(),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            child: Column(
                              children: paymentStats.entries
                                  .map((e) => ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                                color: _getPaymentColor(e.key),
                                                shape: BoxShape.circle)),
                                        title: Text(e.key,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                        trailing: Text(
                                            "${e.value.toStringAsFixed(2)} €",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ))
                                  .toList(),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  double _getMaxY(Map<String, List<Transaction>> grouped) {
    double max = 0;
    grouped.forEach((key, value) {
      final total = value.fold(0.0, (sum, t) => sum + t.total);
      if (total > max) max = total;
    });
    return max == 0 ? 100 : max * 1.1;
  }
  Color _getPaymentColor(String method) {
    switch (method) {
      case 'Cash':
        return Colors.teal;
      case 'Card':
        return Colors.blue;
      case 'Ticket':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text(title,
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: TextStyle(
                              color: Colors.black87,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)))
                ]))
          ],
        ),
      ),
    );
  }
  Widget _buildChartContainer({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 16),
        Expanded(child: child)
      ]),
    );
  }
}
