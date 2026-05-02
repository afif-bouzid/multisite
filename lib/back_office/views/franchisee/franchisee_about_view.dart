import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/update_provider.dart';

class FranchiseeAboutView extends StatefulWidget {
  const FranchiseeAboutView({super.key});
  @override
  State<FranchiseeAboutView> createState() => _FranchiseeAboutViewState();
}

class _FranchiseeAboutViewState extends State<FranchiseeAboutView> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = packageInfo.version);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("À propos")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Carte mise à jour ──────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Consumer<UpdateProvider>(
                  builder: (context, updateProv, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Titre section
                        const Row(
                          children: [
                            Icon(Icons.system_update,
                                color: Colors.blueGrey, size: 20),
                            SizedBox(width: 8),
                            Text(
                              "SYSTÈME & MISE À JOUR",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.blueGrey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Badge version installée
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Version installée :",
                                  style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                _version,
                                style: TextStyle(
                                    color: Colors.blueGrey[800],
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Statut mise à jour
                        Row(
                          children: [
                            Icon(
                              updateProv.hasUpdate
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline,
                              color: updateProv.hasUpdate
                                  ? Colors.orange
                                  : Colors.green,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                updateProv.hasUpdate
                                    ? "Nouvelle version disponible (v${updateProv.latestVersion})"
                                    : "L'application est à jour",
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Barre de progression pendant le téléchargement
                        if (updateProv.isLoading && updateProv.progress > 0) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: updateProv.progress,
                              color: Colors.green,
                              backgroundColor: Colors.green.withValues(alpha: 0.15),
                              minHeight: 10,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              "Téléchargement : ${(updateProv.progress * 100).toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Message d'erreur
                        if (updateProv.errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    updateProv.errorMessage!,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Boutons
                        if (!(updateProv.isLoading && updateProv.progress > 0))
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    foregroundColor: Colors.blueGrey,
                                  ),
                                  onPressed: updateProv.isLoading
                                      ? null
                                      : () => updateProv.checkNowForUpdate(),
                                  icon: updateProv.isLoading
                                      ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                      : const Icon(Icons.refresh),
                                  label: Text(updateProv.isLoading
                                      ? "VÉRIFICATION..."
                                      : "VÉRIFIER"),
                                ),
                              ),
                              if (updateProv.hasUpdate) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    onPressed: updateProv.isLoading
                                        ? null
                                        : () => _confirmUpdate(
                                        context, updateProv),
                                    icon: const Icon(Icons.download),
                                    label: const Text("INSTALLER"),
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              "Cette application est distribuée en dehors du Play Store et du Microsoft Store. Les mises à jour sont téléchargées directement depuis GitHub.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmUpdate(BuildContext context, UpdateProvider updateProv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text("Confirmer la mise à jour"),
          ],
        ),
        content: const Text(
          "Assurez-vous d'avoir une connexion internet stable.\n\n"
              "Une coupure pendant la mise à jour peut bloquer l'application.\n\n"
              "Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              updateProv.downloadAndInstallUpdate();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white),
            child: const Text("Oui, mettre à jour"),
          ),
        ],
      ),
    );
  }
}