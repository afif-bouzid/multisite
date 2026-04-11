import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import '../../../core/services/local_config_service.dart';
import '../../../core/services/printing_service.dart';
import '../../../models.dart';
class FranchiseeSettingsView extends StatelessWidget {
  const FranchiseeSettingsView({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Paramètres"),
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
  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final config = await _localService.getPrinterConfig();
    if (mounted) {
      setState(() {
        _receiptIpController.text = config.ipAddress;
        _useBluetooth = config.isBluetooth;
        _kitchenIpController.text = "192.168.1.100"; 
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
      final newConfig = PrinterConfig(
        name: _useBluetooth
            ? (_selectedDevice?.name ?? 'Imprimante BT')
            : 'Imprimante Principale',
        ipAddress: _receiptIpController.text,
        isBluetooth: _useBluetooth,
        macAddress: _useBluetooth ? _selectedDevice?.address : null,
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
                      value: _selectedDevice,
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
                  labelText: "Adresse IP",
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
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadReceiptSettings();
  }
  Future<void> _loadReceiptSettings() async {
    setState(() => _isLoading = true);
    final config = await _localService.getReceiptConfig();
    setState(() {
      _config = config;
      headerController.text = config.headerText;
      footerController.text = config.footerText;
      _isLoading = false;
    });
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
    setState(() {
      _config = newConfig;
      _isLoading = false;
    });
    if (mounted) {
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
          value: _config.printReceiptOnPayment,
          onChanged: (value) => _saveSettings(printReceiptOnPayment: value),
        ),
        SwitchListTile(
          title: const Text("Détail TVA"),
          value: _config.showVatDetails,
          onChanged: (value) => _saveSettings(showVatDetails: value),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
            onPressed: () => _saveSettings(), child: const Text("Enregistrer"))
      ],
    );
  }
}
