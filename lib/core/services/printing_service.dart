import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import 'local_config_service.dart';

class _PrintJob {
  final Future<List<int>> Function() byteGenerator;
  final Map<String, dynamic> config;
  _PrintJob(this.byteGenerator, this.config);
}

// ==============================================================================
// 1. GÉNÉRATEURS DE BYTES (ISOLATES)
// ==============================================================================

/// TICKET CUISINE (Aéré et Lisible - 80mm)
List<int> _generateKitchenBytes(Map<String, dynamic> params) {
  final int paperWidthInt = int.tryParse(params['paperWidthInt'].toString()) ?? 80;
  final String header = params['header']?.toString() ?? '';
  final String identifier = params['identifier']?.toString() ?? '';
  final String orderType = params['orderType']?.toString() ?? ''; // [MODIFICATION] Récupération du type
  final List<dynamic> lines = params['lines'] as List? ?? [];
  final String date = params['date']?.toString() ?? '';
  final CapabilityProfile profile = params['profile'];

  final PaperSize paperSize = paperWidthInt == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final Generator generator = Generator(paperSize, profile);
  List<int> bytes = [];

  const PosStyles styleTitre = PosStyles(codeTable: 'CP1252', bold: true, height: PosTextSize.size2, width: PosTextSize.size2);
  const PosStyles styleNormal = PosStyles(codeTable: 'CP1252', bold: true, width: PosTextSize.size2);

  if (header.isNotEmpty) {
    bytes += generator.text(header, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, codeTable: 'CP1252'));
  }

  // [MODIFICATION] Affichage du type de commande (SUR PLACE / EMPORTER)
  if (orderType.isNotEmpty) {
    bytes += generator.feed(1);
    bytes += generator.text(orderType, styles: const PosStyles(align: PosAlign.center, bold: true, reverse: true, width: PosTextSize.size2, height: PosTextSize.size2, codeTable: 'CP1252'));
    bytes += generator.feed(1);
  }

  String idClean = identifier.replaceAll("Table", "TBL").toUpperCase();
  bytes += generator.text(idClean,
      styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size3, width: PosTextSize.size3, bold: true, codeTable: 'CP1252'));

  bytes += generator.text(date, styles: const PosStyles(align: PosAlign.center, codeTable: 'CP1252'));
  bytes += generator.hr();

  for (var line in lines) {
    if (line is Map) {
      bytes += generator.row([
        PosColumn(text: "${line['qty']}x", width: 2, styles: styleTitre),
        PosColumn(text: line['name'].toString(), width: 10, styles: styleTitre),
      ]);

      for (var opt in (line['options'] as List? ?? [])) {
        if (opt.toString() == "___SECTION_SEP___") {
          bytes += generator.feed(1); // Espace entre les sections
          continue;
        }
        bytes += generator.row([
          PosColumn(text: "", width: 2),
          PosColumn(text: opt.toString(), width: 10, styles: styleNormal),
        ]);
      }

      for (var rem in (line['removed'] as List? ?? [])) {
        bytes += generator.row([
          PosColumn(text: "", width: 2),
          PosColumn(text: "SANS ${rem.toString().toUpperCase()}", width: 10, styles: const PosStyles(codeTable: 'CP1252', bold: true, reverse: true, width: PosTextSize.size2)),
        ]);
      }
      bytes += generator.feed(2);
      bytes += generator.hr(ch: '_');
    }
  }
  bytes += generator.feed(3);
  bytes += generator.cut();
  return bytes;
}

/// TICKET DE CAISSE (Format Premium - 80mm)
List<int> _generateReceiptBytes(Map<String, dynamic> params) {
  final int paperWidthInt = int.tryParse(params['paperWidthInt'].toString()) ?? 80;
  final PaperSize paperSize = paperWidthInt == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final Generator generator = Generator(paperSize, params['profile']);

  final Map<String, dynamic> tMap = Map<String, dynamic>.from(params['transaction'] ?? {});
  final Map<String, dynamic> fMap = Map<String, dynamic>.from(params['franchisee'] ?? {});
  final Map<String, dynamic> cMap = Map<String, dynamic>.from(params['config'] ?? {});

  List<int> bytes = [];

  const PosStyles styleNormal = PosStyles(codeTable: 'CP1252');
  const PosStyles styleGras = PosStyles(codeTable: 'CP1252', bold: true);
  const PosStyles styleCentre = PosStyles(codeTable: 'CP1252', align: PosAlign.center);

  if (cMap['headerText'] != null && cMap['headerText'].toString().isNotEmpty) {
    bytes += generator.text(cMap['headerText'].toString(), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, codeTable: 'CP1252'));
  } else if (fMap['companyName'] != null) {
    bytes += generator.text(fMap['companyName'].toString().toUpperCase(), styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2, bold: true, codeTable: 'CP1252'));
  }

  if (fMap['address'] != null && fMap['address'].toString().toLowerCase() != 'adresse local') {
    bytes += generator.text(fMap['address'].toString(), styles: styleCentre);
  }
  if (fMap['phone'] != null) {
    bytes += generator.text("Tel: ${fMap['phone']}", styles: styleCentre);
  }
  bytes += generator.hr();

  String orderType = tMap['orderType'].toString().toLowerCase().contains('takeaway') ? "A EMPORTER" : "SUR PLACE";
  bytes += generator.text(orderType, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, reverse: true, codeTable: 'CP1252'));
  bytes += generator.feed(1);

  bytes += generator.row([
    PosColumn(text: DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), width: 6, styles: styleNormal),
    PosColumn(text: "Ticket #${tMap['id']?.toString().substring(0,8).toUpperCase() ?? '---'}", width: 6, styles: const PosStyles(align: PosAlign.right, codeTable: 'CP1252')),
  ]);
  bytes += generator.hr(ch: '=');

  final List items = tMap['items'] as List? ?? [];
  for (var item in items) {
    if (item is Map) {
      bytes += generator.text(item['name'] ?? 'Article', styles: styleGras);
      bytes += generator.row([
        PosColumn(text: "${item['qty']} x ${item['price']}", width: 7, styles: styleNormal),
        PosColumn(text: "${item['total']} EUR", width: 5, styles: const PosStyles(align: PosAlign.right, codeTable: 'CP1252')),
      ]);

      for (var opt in (item['options'] as List? ?? [])) {
        if (opt.toString() != "___SECTION_SEP___") {
          bytes += generator.text("  > ${opt.toString().replaceAll(' (sup)', '')}", styles: styleNormal);
        }
      }
      for (var rem in (item['removed'] as List? ?? [])) {
        bytes += generator.text("  - SANS ${rem.toString()}", styles: styleNormal);
      }
      bytes += generator.hr(ch: '-', linesAfter: 0);
    }
  }

  double totalAmount = double.tryParse(tMap['total'].toString()) ?? 0.0;
  bytes += generator.feed(1);
  bytes += generator.row([
    PosColumn(text: 'TOTAL TTC', width: 6, styles: const PosStyles(height: PosTextSize.size2, bold: true, codeTable: 'CP1252')),
    PosColumn(text: "${totalAmount.toStringAsFixed(2)} EUR", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, codeTable: 'CP1252')),
  ]);
  bytes += generator.hr(ch: '=');

  if (tMap['paymentMethods'] is Map) {
    (tMap['paymentMethods'] as Map).forEach((key, value) {
      if ((double.tryParse(value.toString()) ?? 0) > 0) {
        bytes += generator.row([
          PosColumn(text: "Réglement $key:", width: 8, styles: styleNormal),
          PosColumn(text: "${double.parse(value.toString()).toStringAsFixed(2)} EUR", width: 4, styles: const PosStyles(align: PosAlign.right, codeTable: 'CP1252')),
        ]);
      }
    });
  }

  if (cMap['showVatDetails'] == true || cMap['showVatDetails'].toString() == 'true') {
    double vatRate = double.tryParse(tMap['vatRate']?.toString() ?? '10') ?? 10.0;
    double ht = totalAmount / (1 + (vatRate / 100));
    bytes += generator.row([
      PosColumn(text: "H.T.: ${ht.toStringAsFixed(2)}", width: 6, styles: styleCentre),
      PosColumn(text: "TVA ($vatRate%): ${(totalAmount - ht).toStringAsFixed(2)}", width: 6, styles: styleCentre),
    ]);
  }

  if (cMap['footerText'] != null && cMap['footerText'].toString().isNotEmpty) {
    bytes += generator.hr();
    bytes += generator.text(cMap['footerText'].toString(), styles: styleCentre);
  }

  bytes += generator.feed(3);
  bytes += generator.cut();
  return bytes;
}

// ==============================================================================
// 2. CLASSE DE SERVICE
// ==============================================================================

class PrintingService {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  BluetoothDevice? _selectedDevice;
  BluetoothDevice? get selectedDevice => _selectedDevice;
  final List<_PrintJob> _queue = [];
  bool _isPrinting = false;

  static final PrintingService _instance = PrintingService._internal();
  factory PrintingService() => _instance;
  PrintingService._internal();

  Future<void> selectDevice(BluetoothDevice device) async {
    _selectedDevice = device;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (device.address != null) {
        await prefs.setString('printer_mac', device.address!);
        await prefs.setString('printer_name', device.name ?? 'Imprimante');
      }
    } catch (_) {}
  }

  Future<void> _tryRestoreSavedDevice() async {
    if (_selectedDevice != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedMac = prefs.getString('printer_mac');
      if (savedMac != null && savedMac.isNotEmpty) {
        final devices = await bluetooth.getBondedDevices().timeout(const Duration(seconds: 2));
        _selectedDevice = devices.firstWhere((d) => d.address == savedMac);
      }
    } catch (_) {}
  }

  Future<List<BluetoothDevice>> getBluetoothDevices() async {
    if (!kIsWeb && Platform.isAndroid) {
      await [Permission.bluetooth, Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    }
    try { return await bluetooth.getBondedDevices().timeout(const Duration(seconds: 2)); } catch (_) { return []; }
  }

  void _addJob(Future<List<int>> Function() generator, Map<String, dynamic> config) {
    _queue.add(_PrintJob(generator, config));
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isPrinting || _queue.isEmpty) return;
    _isPrinting = true;
    try {
      final job = _queue.removeAt(0);
      bool isBle = job.config['isBluetooth'].toString() == 'true';
      String? mac = job.config['macAddress'] ?? _selectedDevice?.address;

      if (isBle && mac != null) {
        if (!(await bluetooth.isConnected ?? false)) {
          await bluetooth.connect(BluetoothDevice("Printer", mac)).timeout(const Duration(seconds: 4));
          await Future.delayed(const Duration(milliseconds: 500));
        }
        final bytes = await job.byteGenerator();
        if (bytes.isNotEmpty && (await bluetooth.isConnected ?? false)) {
          await bluetooth.writeBytes(Uint8List.fromList(bytes));
        }
      }
    } catch (_) {}
    finally {
      _isPrinting = false;
      if (_queue.isNotEmpty) { await Future.delayed(const Duration(milliseconds: 300)); _processQueue(); }
    }
  }

  // --- LOGIQUE D'EXTRACTION UNIFIÉE (IMPORTANT) ---

  String _extractName(dynamic item) {
    if (item == null) return '';
    if (item is Map) return item['name']?.toString() ?? (item['product']?['name']?.toString() ?? 'Article');
    try { return (item as dynamic).product.name; } catch (_) {}
    try { return (item as dynamic).name; } catch (_) {}
    return 'Article';
  }

  Map<String, dynamic> _cleanItemForPrint(dynamic item) {
    List<String> options = [];

    // Fonction locale pour extraire les options (modifiée pour corriger le bug historique)
    void extractOpts(dynamic raw) {
      if (raw == null) return;

      if (raw is List) {
        // --- CORRECTION: Gestion du format Historique (Liste de Maps avec 'items') ---
        for (var element in raw) {
          // Si l'élément est une section sauvegardée (contient une liste 'items')
          if (element is Map && element.containsKey('items') && element['items'] is List) {
            var subItems = element['items'] as List;
            if (subItems.isNotEmpty) {
              // On formate chaque sous-élément (le vrai produit)
              options.addAll(subItems.map((e) => _formatOptionString(e)));
              // On ajoute le séparateur visuel pour regrouper par section
              options.add("___SECTION_SEP___");
            }
          } else {
            // Cas standard (liste simple d'options ou ancien format)
            options.add(_formatOptionString(element));
          }
        }
        // Supprimer le dernier séparateur s'il est à la fin
        if (options.isNotEmpty && options.last == "___SECTION_SEP___") {
          options.removeLast();
        }
        // --------------------------------------------------------------------------

      } else if (raw is Map) {
        // Cas standard du Panier "Live" (Map<String, List>)
        raw.forEach((k, v) {
          if (v is List && v.isNotEmpty) {
            options.addAll(v.map((e) => _formatOptionString(e)));
            options.add("___SECTION_SEP___");
          }
        });
        if (options.isNotEmpty && options.last == "___SECTION_SEP___") options.removeLast();
      }
    }

    final String name = _extractName(item);
    var qtyVal = 1;
    var priceVal = 0.0;

    if (item is Map) {
      qtyVal = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
      priceVal = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      // On tente de récupérer les options (format 'options' ou 'selectedOptions')
      extractOpts(item['options'] ?? item['selectedOptions']);
    } else {
      // Cas où item est un objet Dart (CartItem ou autre)
      try {
        qtyVal = (item as dynamic).quantity;
      } catch (_) {}
      try {
        priceVal = (item as dynamic).price;
      } catch (_) {}
      try {
        extractOpts((item as dynamic).selectedOptions);
      } catch (_) {}
    }

    final List<String> removed = item is Map
        ? (item['removedIngredientNames'] as List? ?? []).map((e) => e.toString()).toList()
        : (item is! Map)
        ? (item as dynamic).removedIngredientNames ?? []
        : [];

    return {
      'name': name,
      'qty': qtyVal,
      'price': priceVal.toStringAsFixed(2),
      'total': (priceVal * qtyVal).toStringAsFixed(2),
      'options': options,
      'removed': removed
    };
  }
  String _formatOptionString(dynamic optionItem) {
    String name = _extractName(optionItem);
    double price = 0.0;
    try {
      if (optionItem is Map) {
        price = double.tryParse(optionItem['supplementPrice']?.toString() ?? '0') ?? 0.0;
      } else {
        price = (optionItem as dynamic).supplementPrice ?? 0.0;
      }
    } catch(_) {}
    return price > 0 ? "$name (sup)" : name;
  }

  List<Map<String, dynamic>> _standardizeItems(dynamic inputItems) {
    List<Map<String, dynamic>> cleanList = [];
    if (inputItems is List) {
      for (var item in inputItems) {
        cleanList.add(_cleanItemForPrint(item));
      }
    }
    return cleanList;
  }

  // --- API PUBLIQUE ---

  Future<void> printKitchenTicketSafe({
    required dynamic printerConfig,
    required List itemsToPrint,
    required String identifier,
    bool isUpdate = false,
    bool isReprint = false,
    String? orderType // [MODIFICATION] Nouveau paramètre
  }) async {
    await _tryRestoreSavedDevice();
    final List<Map<String, dynamic>> lines = _standardizeItems(itemsToPrint);

    _addJob(() async => await compute(_generateKitchenBytes, {
      'paperWidthInt': 80,
      'header': isReprint ? "RE-IMPRESSION" : (isUpdate ? "AJOUT" : "NOUVEAU"),
      'identifier': identifier,
      'orderType': orderType, // [MODIFICATION] Passage du paramètre
      'lines': lines,
      'date': DateFormat('HH:mm').format(DateTime.now()),
      'profile': await CapabilityProfile.load()
    }), _normalizeConfig(printerConfig));
  }

  Future<void> printReceipt({required dynamic printerConfig, required dynamic transaction, required dynamic franchisee, dynamic receiptConfig}) async {
    await _tryRestoreSavedDevice();
    Map<String, dynamic> tMap = transaction is Map ? Map.from(transaction) : (transaction as dynamic).toMap();

    // ON FORCE LE NETTOYAGE ICI AUSSI POUR AVOIR LES SECTIONS
    tMap['items'] = _standardizeItems(tMap['items'] as List);

    Map<String, dynamic> cMap = receiptConfig is Map ? Map.from(receiptConfig) : {};
    try {
      final localService = LocalConfigService();
      final savedConfig = await localService.getReceiptConfig();
      cMap['headerText'] ??= savedConfig.headerText;
      cMap['footerText'] ??= savedConfig.footerText;
      cMap['showVatDetails'] ??= savedConfig.showVatDetails;
    } catch(_) {}

    _addJob(() async => await compute(_generateReceiptBytes, {'paperWidthInt': 80, 'transaction': tMap, 'franchisee': franchisee is Map ? franchisee : (franchisee as dynamic).toMap(), 'config': cMap, 'profile': await CapabilityProfile.load()}), _normalizeConfig(printerConfig));
  }

  Future<void> printOrderAndReceipt({required dynamic printerConfig, required dynamic receiptConfig, required dynamic transaction, required dynamic franchisee}) async {
    await printReceipt(printerConfig: printerConfig, receiptConfig: receiptConfig, transaction: transaction, franchisee: franchisee);
    List items = [];
    if (transaction is Map) {
      items = transaction['items'] ?? [];
    } else {
      try { items = (transaction as dynamic).items; } catch(_) {}
    }

    // [MODIFICATION] Détection du type de commande pour impression auto
    String orderTypeStr = "SUR PLACE";
    try {
      final tMap = transaction is Map ? transaction : (transaction as dynamic).toMap();
      String typeRaw = tMap['orderType']?.toString().toLowerCase() ?? '';
      if (typeRaw.contains('takeaway') || typeRaw.contains('emporter')) {
        orderTypeStr = "A EMPORTER";
      }
    } catch(_) {}

    if (items.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 1500));
      await printKitchenTicketSafe(
          printerConfig: printerConfig,
          itemsToPrint: items,
          identifier: "CLIENT",
          orderType: orderTypeStr // [MODIFICATION] Envoi du type
      );
    }
  }

  Future<void> printTestTicket({required dynamic printerConfig}) async {
    if (printerConfig is Map && printerConfig['macAddress'] != null) { try { final devices = await bluetooth.getBondedDevices(); final d = devices.firstWhere((x) => x.address == printerConfig['macAddress']); await selectDevice(d); } catch(_) {} }
    await _tryRestoreSavedDevice();
    Map<String, dynamic> configMap = _normalizeConfig(printerConfig);
    _addJob(() async { final gen = Generator(PaperSize.mm80, await CapabilityProfile.load()); List<int> b = []; b += gen.text("TEST SYSTEME", styles: const PosStyles(align: PosAlign.center, bold: true, codeTable: 'CP1252')); b += gen.text("Accents: é à è ê", styles: const PosStyles(align: PosAlign.center, codeTable: 'CP1252')); b += gen.feed(2); b += gen.cut(); return b; }, configMap);
  }

  Map<String, dynamic> _normalizeConfig(dynamic config) {
    Map<String, dynamic> m = {};
    if (config is Map) {
      config.forEach((k, v) => m[k.toString()] = v);
    } else {
      try { m['isBluetooth'] = config.isBluetooth; m['macAddress'] = config.macAddress; } catch (_) {}
    }
    if (m['macAddress'] == null && _selectedDevice != null) { m['isBluetooth'] = true; m['macAddress'] = _selectedDevice!.address; }
    return m;
  }
}

// ==============================================================================
// 3. EXTENSION Z-TICKET
// ==============================================================================
extension PrintingServiceZ on PrintingService {
  Future<void> printZTicket({required dynamic printerConfig, required dynamic session, required List transactions, required double declaredCash, required bool isManager, required String userName}) async {
    await _tryRestoreSavedDevice();
    Map<String, dynamic> configMap = _normalizeConfig(printerConfig);
    double totalSales = 0;
    for (var t in transactions) {
      Map<String, dynamic> tMap = t is Map ? Map.from(t) : (t as dynamic).toMap();
      totalSales += (tMap['total'] as num? ?? 0).toDouble();
    }
    double initialCash = 0;
    try { initialCash = (session is Map) ? (session['initialCash'] as num).toDouble() : (session as dynamic).initialCash; } catch (_) {}
    _addJob(() async => await compute(_generateZTicketBytes, {'paperWidthInt': 80, 'sessionInitialCash': initialCash, 'declaredCash': declaredCash, 'userName': userName, 'isManager': isManager, 'totalSales': totalSales.toStringAsFixed(2), 'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), 'profile': await CapabilityProfile.load()}), configMap);
  }
}

List<int> _generateZTicketBytes(Map<String, dynamic> params) {
  final int paperWidthInt = int.tryParse(params['paperWidthInt'].toString()) ?? 80;
  final PaperSize paper = paperWidthInt == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final CapabilityProfile profile = params['profile'];
  final Generator generator = Generator(paper, profile);
  List<int> bytes = [];

  const PosStyles sTitle = PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, codeTable: 'CP1252');
  const PosStyles sNormal = PosStyles(codeTable: 'CP1252');

  bytes += generator.text('CLOTURE (Z)', styles: sTitle);
  bytes += generator.text('Date: ${params['date']}', styles: sNormal);
  bytes += generator.text('Fermé par: ${params['userName']}', styles: sNormal);
  bytes += generator.hr();

  double initCash = double.tryParse(params['sessionInitialCash'].toString()) ?? 0.0;
  double declared = double.tryParse(params['declaredCash'].toString()) ?? 0.0;

  bytes += generator.text('FONDS DE CAISSE', styles: const PosStyles(bold: true, codeTable: 'CP1252'));
  bytes += generator.row([
    PosColumn(text: 'Ouverture :', width: 8, styles: sNormal),
    PosColumn(text: '${initCash.toStringAsFixed(2)} EUR', width: 4, styles: const PosStyles(align: PosAlign.right, codeTable: 'CP1252')),
  ]);
  bytes += generator.row([
    PosColumn(text: 'DECLARE :', width: 8, styles: const PosStyles(bold: true, codeTable: 'CP1252')),
    PosColumn(text: '${declared.toStringAsFixed(2)} EUR', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true, codeTable: 'CP1252')),
  ]);
  bytes += generator.hr();

  if (params['isManager'] == true) {
    double totalSales = double.tryParse(params['totalSales'].toString()) ?? 0.0;
    bytes += generator.text('TOTAL VENTES: ${totalSales.toStringAsFixed(2)} EUR', styles: const PosStyles(bold: true, codeTable: 'CP1252'));
  }

  bytes += generator.feed(3);
  bytes += generator.cut();
  return bytes;
}