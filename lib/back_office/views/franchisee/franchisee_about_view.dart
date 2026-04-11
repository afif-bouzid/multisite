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
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("À propos"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "OuiBorne Caisse",
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text("Version actuelle : $_version"),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: Consumer<UpdateProvider>(
                        builder: (context, updateProvider, child) {
                          if (updateProvider.isLoading) {
                            return ElevatedButton.icon(
                              icon: const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              label: const Text("Vérification..."),
                              onPressed: null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade600,
                              ),
                            );
                          }
                          if (updateProvider.hasUpdate) {
                            return ElevatedButton.icon(
                              icon: const Icon(Icons.download_for_offline),
                              label: Text(
                                  "Installer v${updateProvider.latestVersion ?? ''}"),
                              onPressed: () {
                                updateProvider.downloadAndInstallUpdate();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                              ),
                            );
                          }
                          return ElevatedButton.icon(
                            icon: const Icon(Icons.system_update),
                            label: const Text("Vérifier les mises à jour"),
                            onPressed: () {
                              updateProvider.checkNowForUpdate();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Cette application est distribuée en dehors du Play Store. Les mises à jour sont téléchargées depuis GitHub.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
