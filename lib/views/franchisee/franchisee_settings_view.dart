import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../printing_service.dart';
import '../../repository.dart';

class FranchiseeSettingsView extends StatelessWidget {
  const FranchiseeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.print_outlined), text: "Imprimantes"),
              Tab(
                  icon: Icon(Icons.receipt_long_outlined),
                  text: "Ticket de caisse"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PrinterSettingsForm(),
            ReceiptSettingsForm(),
          ],
        ),
      ),
    );
  }
}

// FORMULAIRE POUR L'IMPRIMANTE
class PrinterSettingsForm extends StatefulWidget {
  const PrinterSettingsForm({super.key});

  @override
  State<PrinterSettingsForm> createState() => _PrinterSettingsFormState();
}

class _PrinterSettingsFormState extends State<PrinterSettingsForm> {
  final _formKey = GlobalKey<FormState>();

  // SIMPLIFIÉ : Plus besoin de contrôleurs séparés, on utilise la config du Stream
  bool _isLoading = false;
  bool _isTestingPrint = false;
  late String _franchiseeId;
  final _repository = FranchiseRepository();

  @override
  void initState() {
    super.initState();
    _franchiseeId =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
  }

  Future<void> _saveSettings(
    PrinterConfig currentConfig, {
    String? name,
    String? ipAddress,
    PaperWidth? paperWidth,
    bool? isKitchenPrintingEnabled,
  }) async {
    if (_isLoading) return;
    if (isKitchenPrintingEnabled == true && !_formKey.currentState!.validate())
      return;

    setState(() => _isLoading = true);
    final newConfig = PrinterConfig(
      name: name ?? currentConfig.name,
      ipAddress: ipAddress ?? currentConfig.ipAddress,
      paperWidth: paperWidth ?? currentConfig.paperWidth,
      isKitchenPrintingEnabled:
          isKitchenPrintingEnabled ?? currentConfig.isKitchenPrintingEnabled,
    );
    try {
      await _repository.savePrinterConfig(_franchiseeId, newConfig);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Paramètres de l'imprimante enregistrés."),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// --- NOUVELLE MÉTHODE POUR GÉRER LE TEST D'IMPRESSION ---
  Future<void> _runTestPrint(PrinterConfig config) async {
    setState(() => _isTestingPrint = true);
    try {
      await PrintingService().printTestTicket(printerConfig: config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Ticket de test envoyé à l'imprimante."),
          backgroundColor: Colors.blue,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur d'impression: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _isTestingPrint = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PrinterConfig>(
      stream: _repository.getPrinterConfigStream(_franchiseeId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final config = snapshot.data!;

        // Les contrôleurs sont maintenant initialisés ici pour toujours être à jour
        final nameController = TextEditingController(text: config.name);
        final ipController = TextEditingController(text: config.ipAddress);

        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              SwitchListTile(
                title: const Text("Activer l'impression en cuisine"),
                subtitle: const Text(
                    "Désactivez si vous n'avez pas d'imprimante cuisine."),
                value: config.isKitchenPrintingEnabled,
                onChanged: (value) =>
                    _saveSettings(config, isKitchenPrintingEnabled: value),
              ),
              const Divider(height: 30),

              // Les champs ne sont visibles que si l'option est cochée
              if (config.isKitchenPrintingEnabled) ...[
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: "Nom de l'imprimante (ex: Cuisine)"),
                  onEditingComplete: () =>
                      _saveSettings(config, name: nameController.text),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: ipController,
                  decoration: const InputDecoration(
                      labelText: "Adresse IP de l'imprimante"),
                  validator: (v) {
                    if (config.isKitchenPrintingEnabled &&
                        (v == null || v.isEmpty)) {
                      return "Requis si l'impression est activée";
                    }
                    return null;
                  },
                  onEditingComplete: () =>
                      _saveSettings(config, ipAddress: ipController.text),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PaperWidth>(
                  value: config.paperWidth,
                  decoration:
                      const InputDecoration(labelText: "Largeur du papier"),
                  items: PaperWidth.values
                      .map((width) => DropdownMenuItem(
                          value: width,
                          child:
                              Text(width == PaperWidth.mm58 ? "58mm" : "80mm")))
                      .toList(),
                  onChanged: (value) =>
                      _saveSettings(config, paperWidth: value),
                ),

                /// --- NOUVEAU BOUTON DE TEST ---
                const SizedBox(height: 24),
                _isTestingPrint
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.print_outlined),
                        label: const Text("Imprimer un ticket de test"),
                        onPressed: () => _runTestPrint(config),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.indigo,
                        ),
                      ),
              ],

              // Le bouton de sauvegarde n'est plus vraiment nécessaire mais on le garde par sécurité
              const Divider(height: 40),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Container(),
            ],
          ),
        );
      },
    );
  }
}

// FORMULAIRE POUR LE TICKET (logique similaire appliquée)
class ReceiptSettingsForm extends StatefulWidget {
  const ReceiptSettingsForm({super.key});

  @override
  State<ReceiptSettingsForm> createState() => _ReceiptSettingsFormState();
}

class _ReceiptSettingsFormState extends State<ReceiptSettingsForm> {
  bool _isLoading = false;
  late String _franchiseeId;
  final _repository = FranchiseRepository();

  @override
  void initState() {
    super.initState();
    _franchiseeId =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
  }

  Future<void> _saveSettings(
    ReceiptConfig currentConfig, {
    String? headerText,
    String? footerText,
    bool? showVatDetails,
    bool? printReceiptOnPayment,
  }) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final newConfig = ReceiptConfig(
      headerText: headerText ?? currentConfig.headerText,
      footerText: footerText ?? currentConfig.footerText,
      showVatDetails: showVatDetails ?? currentConfig.showVatDetails,
      printReceiptOnPayment:
          printReceiptOnPayment ?? currentConfig.printReceiptOnPayment,
    );
    try {
      await _repository.saveReceiptConfig(_franchiseeId, newConfig);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReceiptConfig>(
      stream: _repository.getReceiptConfigStream(_franchiseeId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final config = snapshot.data!;
        final headerController = TextEditingController(text: config.headerText);
        final footerController = TextEditingController(text: config.footerText);

        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            TextFormField(
                controller: headerController,
                decoration: const InputDecoration(labelText: "Texte d'en-tête"),
                onEditingComplete: () =>
                    _saveSettings(config, headerText: headerController.text),
                maxLines: 3),
            const SizedBox(height: 16),
            TextFormField(
                controller: footerController,
                decoration:
                    const InputDecoration(labelText: "Texte de pied de page"),
                onEditingComplete: () =>
                    _saveSettings(config, footerText: footerController.text),
                maxLines: 3),
            const SizedBox(height: 16),
            SwitchListTile(
                title: const Text("Impression automatique après paiement"),
                subtitle: const Text(
                    "Désactivez si vous ne voulez pas de ticket client."),
                value: config.printReceiptOnPayment,
                onChanged: (value) =>
                    _saveSettings(config, printReceiptOnPayment: value)),
            SwitchListTile(
                title: const Text("Afficher le détail de la TVA"),
                value: config.showVatDetails,
                onChanged: (value) =>
                    _saveSettings(config, showVatDetails: value)),
            const Divider(height: 40),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    );
  }
}
