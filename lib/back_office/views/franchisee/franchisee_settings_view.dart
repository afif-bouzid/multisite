import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/repository/repository.dart';
import '../../../core/services/local_config_service.dart';
import '../../../models.dart';

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
          children: [PrinterSettingsForm(), ReceiptSettingsForm()],
        ),
      ),
    );
  }
}

class PrinterSettingsForm extends StatefulWidget {
  const PrinterSettingsForm({super.key});

  @override
  State<PrinterSettingsForm> createState() => _PrinterSettingsFormState();
}

class _PrinterSettingsFormState extends State<PrinterSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  final _receiptIpController = TextEditingController();
  final _kitchenIpController = TextEditingController();
  bool _isAutoPrint = false;

  final LocalConfigService _localService = LocalConfigService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final config = await _localService.loadConfig();
    setState(() {
      _receiptIpController.text = config.receiptPrinterIp;
      _kitchenIpController.text = config.kitchenPrinterIp;
      _isAutoPrint = config.isAutoPrintEnabled;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final currentConfig = await _localService.loadConfig();

    currentConfig.receiptPrinterIp = _receiptIpController.text;
    currentConfig.kitchenPrinterIp = _kitchenIpController.text;
    currentConfig.isAutoPrintEnabled = _isAutoPrint;

    await _localService.saveConfig(currentConfig);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Configuration locale enregistrée !"),
          backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Configuration Réseau (Local)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _receiptIpController,
            decoration: const InputDecoration(
              labelText: "IP Imprimante CAISSE (Ticket Client)",
              hintText: "ex: 192.168.1.100",
              prefixIcon: Icon(Icons.receipt),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _kitchenIpController,
            decoration: const InputDecoration(
              labelText: "IP Imprimante CUISINE (Fabrication)",
              hintText: "ex: 192.168.1.101",
              prefixIcon: Icon(Icons.soup_kitchen),
              border: OutlineInputBorder(),
            ),
          ),
          const Divider(height: 40),
          SwitchListTile(
            title: const Text("Mode Automatique Borne"),
            subtitle: const Text(
                "Si activé, la caisse détecte les paiements borne et imprime automatiquement en cuisine."),
            value: _isAutoPrint,
            onChanged: (val) => setState(() => _isAutoPrint = val),
            secondary: const Icon(Icons.autorenew, color: Colors.blue),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text("Enregistrer la configuration"),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white),
          )
        ],
      ),
    );
  }
}

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
                    "Désactivez si vousne voulez pas de ticket client."),
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
