import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Imports Core
import '../../../core/auth_provider.dart';
import '../../../core/services/local_config_service.dart';
import '../../../core/services/printing_service.dart';
import '../../../models.dart';

class FranchiseeSettingsView extends StatelessWidget {
  const FranchiseeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).franchiseUser;
    final bool hasWeb = user?.enabledModules['click_and_collect'] == true;

    return DefaultTabController(
      length: hasWeb ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Paramètres"),
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.print_outlined), text: "Imprimantes"),
              const Tab(icon: Icon(Icons.receipt_long_outlined), text: "Ticket de caisse"),
              if (hasWeb)
                const Tab(icon: Icon(Icons.notifications_active_outlined), text: "Web & Impression"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const PrinterSettingsForm(),
            const ReceiptSettingsForm(),
            if (hasWeb) const ClickAndCollectPrintSettingsForm(),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// NOUVEAU FORMULAIRE : CONFIGURATION IMPRESSION WEB & ALERTES
// =========================================================================
class ClickAndCollectPrintSettingsForm extends StatefulWidget {
  const ClickAndCollectPrintSettingsForm({super.key});

  @override
  State<ClickAndCollectPrintSettingsForm> createState() => _ClickAndCollectPrintSettingsFormState();
}

class _ClickAndCollectPrintSettingsFormState extends State<ClickAndCollectPrintSettingsForm> {
  final LocalConfigService _localService = LocalConfigService();
  bool _isLoading = true;

  // Options de réglages
  bool _autoPrintWebKitchen = true;
  bool _autoPrintWebReceipt = false;
  bool _enableSoundAlert = true;
  bool _repeatAlertUntilAction = true;
  int _kitchenCopies = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.effectiveStoreId).get();
    if (doc.exists) {
      final data = doc.data()?['printConfigWeb'] as Map<String, dynamic>? ?? {};
      setState(() {
        _autoPrintWebKitchen = data['autoPrintKitchen'] ?? true;
        _autoPrintWebReceipt = data['autoPrintReceipt'] ?? false;
        _enableSoundAlert = data['enableSoundAlert'] ?? true;
        _repeatAlertUntilAction = data['repeatAlert'] ?? true;
        _kitchenCopies = data['kitchenCopies'] ?? 1;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;

    await FirebaseFirestore.instance.collection('users').doc(user?.effectiveStoreId).set({
      'printConfigWeb': {
        'autoPrintKitchen': _autoPrintWebKitchen,
        'autoPrintReceipt': _autoPrintWebReceipt,
        'enableSoundAlert': _enableSoundAlert,
        'repeatAlert': _repeatAlertUntilAction,
        'kitchenCopies': _kitchenCopies,
      }
    }, SetOptions(merge: true));

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réglages Web enregistrés'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text("Automatisation Web", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SwitchListTile(
          title: const Text("Impression auto. Cuisine"),
          subtitle: const Text("Lance le ticket cuisine dès qu'une commande est payée en ligne."),
          value: _autoPrintWebKitchen,
          onChanged: (v) => setState(() => _autoPrintWebKitchen = v),
        ),
        SwitchListTile(
          title: const Text("Impression auto. Ticket Client"),
          subtitle: const Text("Sort le ticket de caisse immédiatement (pour le sac)."),
          value: _autoPrintWebReceipt,
          onChanged: (v) => setState(() => _autoPrintWebReceipt = v),
        ),
        const Divider(height: 40),

        const Text("Alertes & Notifications", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up, color: Colors.orange),
          title: const Text("Sonnerie type 'Uber Eats'"),
          subtitle: const Text("Alerte sonore répétée lors d'une nouvelle commande web."),
          value: _enableSoundAlert,
          onChanged: (v) => setState(() => _enableSoundAlert = v),
        ),
        if (_enableSoundAlert)
          SwitchListTile(
            title: const Text("Répéter jusqu'à validation"),
            subtitle: const Text("Le son continue tant que la commande n'est pas consultée."),
            value: _repeatAlertUntilAction,
            onChanged: (v) => setState(() => _repeatAlertUntilAction = v),
          ),
        const Divider(height: 40),

        const Text("Copies & Sorties", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ListTile(
          title: const Text("Nombre de copies cuisine (Web)"),
          trailing: DropdownButton<int>(
            value: _kitchenCopies,
            items: [1, 2, 3].map((e) => DropdownMenuItem(value: e, child: Text("$e"))).toList(),
            onChanged: (v) => setState(() => _kitchenCopies = v ?? 1),
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save),
          label: const Text("ENREGISTRER LES PRÉFÉRENCES"),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.black, foregroundColor: Colors.white),
        )
      ],
    );
  }
}

// =========================================================================
// VOS CLASSES ORIGINALES (PrinterSettingsForm & ReceiptSettingsForm)
// =========================================================================

class PrinterSettingsForm extends StatefulWidget {
  const PrinterSettingsForm({super.key});
  @override
  State<PrinterSettingsForm> createState() => _PrinterSettingsFormState();
}
class _PrinterSettingsFormState extends State<PrinterSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  final _receiptIpController = TextEditingController();
  final _kitchenIpController = TextEditingController();
  bool _useBluetooth = false;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _isScanning = false;
  final LocalConfigService _localService = LocalConfigService();
  final PrintingService _printingService = PrintingService();
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  @override
  void dispose() {
    _receiptIpController.dispose();
    _kitchenIpController.dispose();
    super.dispose();
  }
  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final config = await _localService.getPrinterConfig();
    if (mounted) {
      setState(() {
        _receiptIpController.text = config.ipAddress;
        _kitchenIpController.text = config.kitchenIpAddress ?? "";
        _useBluetooth = config.isBluetooth;
      });
      if (_useBluetooth) {
        await _scanBluetoothDevices();
        if (config.macAddress != null && _devices.isNotEmpty) {
          try {
            final device = _devices.firstWhere(
                  (d) => d.address == config.macAddress,
            );
            setState(() {
              _selectedDevice = device;
            });
            _printingService.selectDevice(device);
          } catch (e) {
            _selectedDevice = null;
          }
        }
      }
    }
    setState(() => _isLoading = false);
  }
  Future<void> _scanBluetoothDevices() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });
    try {
      final devices = await _printingService.getBluetoothDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur scan Bluetooth: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }
  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final existing = await _localService.getPrinterConfig();
      final newConfig = PrinterConfig(
        name: _useBluetooth
            ? (_selectedDevice?.name ?? 'Imprimante BT')
            : 'Imprimante Principale',
        ipAddress: _receiptIpController.text,
        kitchenIpAddress: _kitchenIpController.text,
        isBluetooth: _useBluetooth,
        macAddress: _useBluetooth ? _selectedDevice?.address : null,
        autoSendKitchenOnPayment: existing.autoSendKitchenOnPayment,
      );
      await _localService.savePrinterConfig(newConfig);
      if (_useBluetooth && _selectedDevice != null) {
        await _printingService.selectDevice(_selectedDevice!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration enregistrée et appliquée !'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
  Future<void> _testPrint() async {
    setState(() => _isLoading = true);
    try {
      if (_useBluetooth && _selectedDevice != null) {
        _printingService.selectDevice(_selectedDevice!);
      }
      final testConfig = PrinterConfig(
        ipAddress: _receiptIpController.text,
        kitchenIpAddress: _kitchenIpController.text,
        isBluetooth: _useBluetooth,
        macAddress: _selectedDevice?.address,
      );
      await _printingService.printTestTicket(printerConfig: testConfig);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket de test envoyé')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Imprimante Principale",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Utiliser Bluetooth"),
              subtitle: Text(_useBluetooth ? "Bluetooth" : "Réseau (IP)"),
              value: _useBluetooth,
              onChanged: (val) {
                setState(() {
                  _useBluetooth = val;
                  if (val && _devices.isEmpty) {
                    _scanBluetoothDevices();
                  }
                });
              },
            ),
            const Divider(),
            if (_useBluetooth) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<BluetoothDevice>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Choisir l'appareil",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.bluetooth),
                      ),
                      initialValue: _selectedDevice,
                      items: _devices.map((d) {
                        return DropdownMenuItem(
                          value: d,
                          child: Text(d.name ?? d.address ?? "Inconnu"),
                        );
                      }).toList(),
                      onChanged: (device) {
                        setState(() => _selectedDevice = device);
                      },
                      validator: (value) =>
                      value == null ? "Sélectionnez une imprimante" : null,
                    ),
                  ),
                  IconButton(
                    icon: _isScanning
                        ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    onPressed: _isScanning ? null : _scanBluetoothDevices,
                  )
                ],
              ),
            ] else ...[
              TextFormField(
                controller: _receiptIpController,
                decoration: const InputDecoration(
                  labelText: "Adresse IP Caisse",
                  hintText: "192.168.1.200",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lan),
                ),
                keyboardType: TextInputType.datetime,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'IP requise';
                  return null;
                },
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              "Imprimante Cuisine",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _kitchenIpController,
              decoration: const InputDecoration(
                labelText: "Adresse IP Cuisine",
                hintText: "192.168.1.100",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.kitchen),
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text("Tester"),
                    onPressed: _testPrint,
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text("Enregistrer"),
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
  final headerController = TextEditingController();
  final footerController = TextEditingController();
  final LocalConfigService _localService = LocalConfigService();
  ReceiptConfig _config = ReceiptConfig(
      headerText: '',
      footerText: '',
      showVatDetails: true,
      printReceiptOnPayment: true);
  bool _autoSendKitchenOnPayment = false;
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadReceiptSettings();
  }
  @override
  void dispose() {
    headerController.dispose();
    footerController.dispose();
    super.dispose();
  }
  Future<void> _loadReceiptSettings() async {
    setState(() => _isLoading = true);
    final config = await _localService.getReceiptConfig();
    final printerConfig = await _localService.getPrinterConfig();
    if (mounted) {
      setState(() {
        _config = config;
        headerController.text = config.headerText;
        footerController.text = config.footerText;
        _autoSendKitchenOnPayment = printerConfig.autoSendKitchenOnPayment;
        _isLoading = false;
      });
    }
  }
  Future<void> _saveAutoSendKitchen(bool value) async {
    final existing = await _localService.getPrinterConfig();
    final updated = PrinterConfig(
      name: existing.name,
      ipAddress: existing.ipAddress,
      kitchenIpAddress: existing.kitchenIpAddress,
      type: existing.type,
      paperWidth: existing.paperWidth,
      isKitchenPrintingEnabled: existing.isKitchenPrintingEnabled,
      isBluetooth: existing.isBluetooth,
      macAddress: existing.macAddress,
      autoSendKitchenOnPayment: value,
    );
    await _localService.savePrinterConfig(updated);
    if (mounted) {
      setState(() => _autoSendKitchenOnPayment = value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Préférences sauvegardées')),
      );
    }
  }
  Future<void> _saveSettings(
      {String? headerText,
        String? footerText,
        bool? showVatDetails,
        bool? printReceiptOnPayment}) async {
    setState(() => _isLoading = true);
    final newConfig = ReceiptConfig(
      headerText: headerText ?? headerController.text,
      footerText: footerText ?? footerController.text,
      showVatDetails: showVatDetails ?? _config.showVatDetails,
      printReceiptOnPayment:
      printReceiptOnPayment ?? _config.printReceiptOnPayment,
    );
    await _localService.saveReceiptConfig(newConfig);
    if (mounted) {
      setState(() {
        _config = newConfig;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Préférences sauvegardées')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Personnalisation",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextFormField(
          controller: headerController,
          decoration: const InputDecoration(
            labelText: "En-tête du ticket",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          onEditingComplete: () => _saveSettings(),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: footerController,
          decoration: const InputDecoration(
            labelText: "Pied de page",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          onEditingComplete: () => _saveSettings(),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text("Imprimer auto. après paiement"),
          subtitle: const Text("Le ticket client sort automatiquement à l'encaissement."),
          value: _config.printReceiptOnPayment,
          onChanged: (value) => _saveSettings(printReceiptOnPayment: value),
        ),
        SwitchListTile(
          title: const Text("Envoyer auto. en cuisine à l'encaissement"),
          subtitle: const Text(
            "Imprime le ticket cuisine au paiement uniquement s'il n'a pas déjà été envoyé.",
          ),
          value: _autoSendKitchenOnPayment,
          onChanged: _saveAutoSendKitchen,
        ),
        SwitchListTile(
          title: const Text("Détail TVA"),
          value: _config.showVatDetails,
          onChanged: (value) => _saveSettings(showVatDetails: value),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          onPressed: () => _saveSettings(),
          label: const Text("Enregistrer"),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
        )
      ],
    );
  }
}