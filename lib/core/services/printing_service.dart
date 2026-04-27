import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_config_service.dart';

class _PrintJob {
  final Future<List<int>> Function() byteGenerator;
  final Map<String, dynamic> config;
  _PrintJob(this.byteGenerator, this.config);
}

Uint8List _encodeCP858(String text) {
  final List<int> bytes = [];
  for (int i = 0; i < text.length; i++) {
    final int codeUnit = text.codeUnitAt(i);
    switch (codeUnit) {
      case 0x20AC: bytes.add(0xD5); break;
      case 0x00E9: bytes.add(0x82); break;
      case 0x00E0: bytes.add(0x85); break;
      case 0x00E8: bytes.add(0x8A); break;
      case 0x00EA: bytes.add(0x88); break;
      case 0x00EB: bytes.add(0x89); break;
      case 0x00EE: bytes.add(0x8C); break;
      case 0x00EF: bytes.add(0x8B); break;
      case 0x00F4: bytes.add(0x93); break;
      case 0x00FB: bytes.add(0x96); break;
      case 0x00F9: bytes.add(0x97); break;
      case 0x00C9: bytes.add(0x90); break;
      case 0x00E7: bytes.add(0x87); break;
      case 0x00B0: bytes.add(0xF8); break;
      default:
        if (codeUnit <= 0x7F) {
          bytes.add(codeUnit);
        } else {
          bytes.add(0x20);
        }
    }
  }
  return Uint8List.fromList(bytes);
}

List<int> _forceCP858Commands() {
  return [
    0x1B, 0x40,
    0x1C, 0x2E,
    0x1B, 0x74, 0x13,
    0x1B, 0x52, 0x00,
    0x1B, 0x74, 0x13,
  ];
}

List<int> _forceCP858Alternative() {
  return [
    0x1B, 0x40,
    0x1B, 0x74, 0x13,
    0x1B, 0x74, 0x16,
    0x1C, 0x2E,
    0x1B, 0x74, 0x13,
  ];
}

String _formatRow(String left, String right, {int width = 32}) {
  String l = left.replaceAll('\n', ' ').trim();
  String r = right.replaceAll('\n', ' ').trim();
  if (l.isEmpty && r.isEmpty) return '';
  if (l.length > width - 3) l = '${l.substring(0, width - 6)}...';
  if (r.length > width - 3) r = '${r.substring(0, width - 6)}...';
  if (l.length + r.length >= width) {
    int avail = width - r.length - 2;
    l = avail > 0 ? l.substring(0, avail) : '';
  }
  int spaces = width - l.length - r.length;
  return l + (' ' * (spaces > 0 ? spaces : 0)) + r;
}

List<int> _generateKitchenBytes(Map<String, dynamic> params) {
  final int paperWidthInt = int.tryParse(params['paperWidthInt'].toString()) ?? 80;
  final String identifier = params['identifier']?.toString() ?? '';
  String rawOrderType = (params['orderType']?.toString() ?? '').toLowerCase();
  String orderType = "SUR PLACE";
  if (rawOrderType.contains('takeaway') || rawOrderType.contains('emporter') || rawOrderType.contains('take_away')) {
    orderType = "A EMPORTER";
  }
  final List<dynamic> lines = params['lines'] as List? ?? [];
  final String date = params['date']?.toString() ?? '';
  final CapabilityProfile profile = params['profile'];
  final PaperSize paperSize = paperWidthInt == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final Generator generator = Generator(paperSize, profile);
  List<int> bytes = [];
  bytes += generator.reset();
  bytes += _forceCP858Commands();
  bytes += [0x1B, 0x64, 0x02];
  const styleOrderType = PosStyles(align: PosAlign.center, bold: true, reverse: true, width: PosTextSize.size3, height: PosTextSize.size3);
  const styleTitreProduit = PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2);
  const styleInfo = PosStyles(bold: true, width: PosTextSize.size2);
  const styleAlerteSans = PosStyles(bold: true, reverse: true, height: PosTextSize.size2);
  bytes += generator.feed(1);
  bytes += generator.textEncoded(_encodeCP858(" $orderType "), styles: styleOrderType);
  bytes += generator.feed(1);
  if (identifier.isNotEmpty) {
    String idClean = identifier.replaceAll("Table", "TBL").toUpperCase();
    bytes += generator.textEncoded(_encodeCP858(idClean), styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2, bold: true));
  }
  bytes += generator.textEncoded(_encodeCP858("Heure: $date"), styles: const PosStyles(align: PosAlign.center));
  bytes += generator.hr(ch: '=');
  int totalQty = 0;
  for (var line in lines) {
    if (line is Map) {
      totalQty += (line['qty'] as int? ?? 1);
      bytes += generator.row([
        PosColumn(textEncoded: _encodeCP858("${line['qty']} x"), width: 2, styles: styleTitreProduit),
        PosColumn(textEncoded: _encodeCP858(line['name'].toString().toUpperCase()), width: 10, styles: styleTitreProduit),
      ]);
      bytes += generator.feed(1);
      for (var rem in (line['removed'] as List? ?? [])) {
        bytes += generator.row([
          PosColumn(textEncoded: _encodeCP858(" !"), width: 1, styles: styleAlerteSans),
          PosColumn(textEncoded: _encodeCP858("SANS ${rem.toString().toUpperCase()}"), width: 11, styles: styleAlerteSans),
        ]);
      }
      for (var opt in (line['options'] as List? ?? [])) {
        String optName = opt is Map ? (opt['name']?.toString() ?? "") : opt.toString();
        double optPrice = opt is Map ? (double.tryParse(opt['price']?.toString() ?? '0') ?? 0.0) : 0.0;
        if (optName == "___SECTION_SEP___") { bytes += generator.feed(1); continue; }
        String label = optPrice > 0 ? "$optName (sup)" : optName;
        bytes += generator.row([
          PosColumn(textEncoded: _encodeCP858("-"), width: 1),
          PosColumn(textEncoded: _encodeCP858(label), width: 11, styles: styleInfo),
        ]);
      }
      bytes += generator.feed(1);
      bytes += generator.hr(ch: '-');
      bytes += generator.feed(1);
    }
  }
  bytes += generator.textEncoded(_encodeCP858("Total articles : $totalQty"), styles: const PosStyles(align: PosAlign.right));
  bytes += generator.feed(3);
  bytes += generator.cut();
  return bytes;
}

List<int> _generateReceiptBytes(Map<String, dynamic> params) {
  final int paperWidthInt = int.tryParse(params['paperWidthInt'].toString()) ?? 80;
  final PaperSize paperSize = paperWidthInt == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final Generator generator = Generator(paperSize, params['profile']);
  final Map<String, dynamic> tMap = Map<String, dynamic>.from(params['transaction'] ?? {});
  final Map<String, dynamic> fMap = Map<String, dynamic>.from(params['franchisee'] ?? {});
  final Map<String, dynamic> cMap = Map<String, dynamic>.from(params['config'] ?? {});
  List<int> bytes = [];
  bytes += generator.reset();
  bytes += _forceCP858Commands();
  bytes += [0x1B, 0x64, 0x02];
  const styleNormal = PosStyles();
  const styleGras = PosStyles(bold: true);
  const styleCentre = PosStyles(align: PosAlign.center);
  const styleTitre = PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2);
  String companyName = fMap['companyName']?.toString() ?? '';
  String restaurantName = fMap['restaurantName']?.toString() ?? '';
  if (companyName == 'null') companyName = '';
  if (restaurantName == 'null') restaurantName = '';
  String headerText = '';
  if (cMap['headerText'] != null && cMap['headerText'].toString().isNotEmpty && cMap['headerText'].toString() != 'null') {
    headerText = cMap['headerText'].toString();
  } else if (companyName.isNotEmpty) {
    headerText = companyName;
  } else if (restaurantName.isNotEmpty) {
    headerText = restaurantName;
  } else {
    headerText = "TICKET DE CAISSE";
  }
  bytes += generator.textEncoded(_encodeCP858(headerText.toUpperCase()), styles: styleTitre);
  if (companyName.isNotEmpty && companyName.toUpperCase() != restaurantName.toUpperCase() && restaurantName.isNotEmpty) {
    bytes += generator.textEncoded(_encodeCP858(restaurantName), styles: styleCentre);
  }
  if (fMap['address'] != null && fMap['address'].toString().toLowerCase() != 'adresse local' && fMap['address'].toString() != 'null') {
    bytes += generator.textEncoded(_encodeCP858(fMap['address'].toString()), styles: styleCentre);
  }
  if (fMap['phone'] != null && fMap['phone'].toString().isNotEmpty && fMap['phone'].toString() != 'null') {
    bytes += generator.textEncoded(_encodeCP858("Tel: ${fMap['phone']}"), styles: styleCentre);
  }
  bytes += generator.feed(1);
  bytes += generator.textEncoded(_encodeCP858("Date : ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}"), styles: styleNormal);
  String uniqueId = tMap['id']?.toString() ?? '';
  if (uniqueId.isNotEmpty && uniqueId != 'null') {
    bytes += generator.textEncoded(_encodeCP858("Ticket #$uniqueId"), styles: styleNormal);
  }
  String identifier = tMap['identifier']?.toString() ?? '';
  if (identifier.isNotEmpty && identifier != 'null') {
    String displayNum = identifier.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+'), '');
    if (displayNum.isEmpty) displayNum = identifier;
    bytes += generator.feed(1);
    bytes += generator.textEncoded(_encodeCP858("COMMANDE $displayNum"), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size3, width: PosTextSize.size2));
    bytes += generator.feed(1);
  }
  if (tMap['customerName'] != null && tMap['customerName'].toString().isNotEmpty && tMap['customerName'].toString() != 'null') {
    bytes += generator.textEncoded(_encodeCP858("Client : ${tMap['customerName']}"), styles: styleGras);
  }
  String source = tMap['source']?.toString().toUpperCase() ?? 'CAISSE';
  String kioskName = tMap['kioskName']?.toString() ?? '';
  if (source.contains('BORNE') || source.contains('KIOSK')) {
    bytes += generator.textEncoded(_encodeCP858("Prise de commande : Borne ${kioskName.isNotEmpty ? '($kioskName)' : ''}"), styles: styleNormal);
  } else {
    bytes += generator.textEncoded(_encodeCP858("Prise de commande : Caisse"), styles: styleNormal);
  }
  bytes += generator.feed(1);
  String orderType = tMap['orderType'].toString().toLowerCase().contains('takeaway') ? "A EMPORTER" : "SUR PLACE";
  bytes += generator.textEncoded(_encodeCP858(orderType), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, reverse: true));
  bytes += generator.feed(1);
  bytes += generator.hr(ch: '=');
  int charWidth = paperWidthInt == 80 ? 48 : 32;
  final List items = tMap['items'] as List? ?? [];
  for (var item in items) {
    if (item is Map) {
      String itemName = item['name'] ?? 'Article';
      int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      double totalItem = double.tryParse(item['total']?.toString() ?? '0') ?? (price * qty);
      bytes += generator.textEncoded(_encodeCP858(_formatRow("${qty}x $itemName", "${totalItem.toStringAsFixed(2)} €", width: charWidth)), styles: styleGras);
      for (var opt in (item['options'] as List? ?? [])) {
        String optName = "";
        double optPrice = 0.0;
        if (opt is Map) {
          optName = opt['name']?.toString() ?? "";
          optPrice = double.tryParse(opt['price']?.toString() ?? '0') ?? 0.0;
        } else {
          optName = opt.toString();
        }
        if (optName != "___SECTION_SEP___") {
          String pStr = optPrice > 0 ? "+${optPrice.toStringAsFixed(2)} €" : "";
          bytes += generator.textEncoded(_encodeCP858(_formatRow("  > $optName", pStr, width: charWidth)), styles: styleNormal);
        }
      }
      for (var rem in (item['removed'] as List? ?? [])) {
        bytes += generator.textEncoded(_encodeCP858("  - SANS ${rem.toString().toUpperCase()}"), styles: styleNormal);
      }
      bytes += generator.hr(ch: '-', linesAfter: 0);
    }
  }
  bytes += generator.feed(1);
  double totalAmount = double.tryParse(tMap['total'].toString()) ?? 0.0;
  double subTotal = double.tryParse(tMap['subTotal'].toString()) ?? totalAmount;
  double discount = double.tryParse(tMap['discountAmount'].toString()) ?? 0.0;
  if (discount > 0) {
    bytes += generator.textEncoded(_encodeCP858(_formatRow("SOUS-TOTAL", "${subTotal.toStringAsFixed(2)} €", width: charWidth)), styles: styleNormal);
    bytes += generator.textEncoded(_encodeCP858(_formatRow("REMISE", "-${discount.toStringAsFixed(2)} €", width: charWidth)), styles: styleNormal);
  }
  bytes += generator.textEncoded(_encodeCP858(_formatRow("TOTAL TTC", "${totalAmount.toStringAsFixed(2)} €", width: charWidth)), styles: styleGras.copyWith(height: PosTextSize.size2));
  bytes += generator.hr(ch: '=');
  if (tMap['paymentMethods'] is Map) {
    (tMap['paymentMethods'] as Map).forEach((key, value) {
      if ((double.tryParse(value.toString()) ?? 0) > 0) {
        String nomPaiement = key.toString();
        if (nomPaiement.toLowerCase() == 'card') nomPaiement = 'Carte Bancaire';
        if (nomPaiement.toLowerCase() == 'cash') nomPaiement = 'Especes';
        if (nomPaiement.toLowerCase() == 'ticket') nomPaiement = 'Tickets Resto';
        bytes += generator.textEncoded(_encodeCP858(_formatRow("Paye en $nomPaiement :", "${double.parse(value.toString()).toStringAsFixed(2)} €", width: charWidth)), styles: styleNormal);
      }
    });
  }
  bytes += generator.feed(1);
  if (cMap['showVatDetails'] == true || cMap['showVatDetails'].toString() == 'true') {
    bytes += generator.textEncoded(_encodeCP858("--- DETAIL DES TAXES ---"), styles: styleCentre);
    bytes += generator.textEncoded(_encodeCP858(_formatRow("Taux", "HT      TVA     TTC", width: charWidth)), styles: styleGras);
    double vatTotal = double.tryParse(tMap['vatTotal']?.toString() ?? '0') ?? 0.0;
    double htTotal = totalAmount - vatTotal;
    String rightPart = "${htTotal.toStringAsFixed(2)}€  ${vatTotal.toStringAsFixed(2)}€  ${totalAmount.toStringAsFixed(2)}€";
    bytes += generator.textEncoded(_encodeCP858(_formatRow("Mixte", rightPart, width: charWidth)), styles: styleNormal);
  }
  if (cMap['footerText'] != null && cMap['footerText'].toString().isNotEmpty && cMap['footerText'].toString() != 'null') {
    bytes += generator.hr();
    bytes += generator.textEncoded(_encodeCP858(cMap['footerText'].toString()), styles: styleCentre);
  }
  bytes += generator.feed(1);
  bytes += generator.textEncoded(_encodeCP858("Merci de votre visite et a bientot !"), styles: styleCentre);
  bytes += generator.feed(3);
  bytes += generator.cut();
  return bytes;
}

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
    try {
      return await bluetooth.getBondedDevices().timeout(const Duration(seconds: 2));
    } catch (_) {
      return [];
    }
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
      bool isWifi = job.config['isWifi'].toString() == 'true';
      String? mac = job.config['macAddress'] ?? _selectedDevice?.address;
      String? ip = job.config['ipAddress']?.toString();
      if (isBle && mac != null) {
        if (!(await bluetooth.isConnected ?? false)) {
          await bluetooth.connect(BluetoothDevice("Printer", mac)).timeout(const Duration(seconds: 4));
          await Future.delayed(const Duration(milliseconds: 500));
        }
        final bytes = await job.byteGenerator();
        if (bytes.isNotEmpty && (await bluetooth.isConnected ?? false)) {
          await bluetooth.writeBytes(Uint8List.fromList(bytes));
          debugPrint("✅ Impression Bluetooth envoyée à ${_selectedDevice?.name}");
        }
      } else if (isWifi && ip != null && ip.isNotEmpty) {
        final bytes = await job.byteGenerator();
        if (bytes.isNotEmpty) {
          Socket? socket;
          try {
            int port = int.tryParse(job.config['port']?.toString() ?? '9100') ?? 9100;
            socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 10));
            socket.add(Uint8List.fromList(bytes));
            await socket.flush();
            await Future.delayed(const Duration(milliseconds: 800));
            debugPrint("✅ Impression Wi-Fi envoyée à $ip:$port");
          } catch (e) {
            debugPrint("🔴 ERREUR WI-FI : $e");
            await _tryAlternativeWifiPrint(ip, job);
          } finally {
            socket?.destroy();
          }
        }
      }
    } catch (e) {
      debugPrint("🔴 ERREUR PROCESS QUEUE : $e");
    } finally {
      _isPrinting = false;
      if (_queue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 1000));
        _processQueue();
      }
    }
  }

  Future<void> _tryAlternativeWifiPrint(String ip, _PrintJob job) async {
    try {
      final bytes = await job.byteGenerator();
      if (bytes.isEmpty) return;
      Socket? socket;
      int port = int.tryParse(job.config['port']?.toString() ?? '9100') ?? 9100;
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 10));
      List<int> altCommands = _forceCP858Alternative();
      socket.add(Uint8List.fromList(altCommands));
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 300));
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint("✅ Impression Wi-Fi (alternative) envoyée à $ip:$port");
      socket.destroy();
    } catch (e) {
      debugPrint("🔴 ERREUR WI-FI ALTERNATIVE : $e");
    }
  }

  String _extractName(dynamic item) {
    if (item == null) return '';
    if (item is Map) return item['name']?.toString() ?? (item['product']?['name']?.toString() ?? 'Article');
    try { return (item as dynamic).product.name; } catch (_) {}
    try { return (item as dynamic).name; } catch (_) {}
    return 'Article';
  }

  Map<String, dynamic> _formatOption(dynamic optionItem) {
    String name = _extractName(optionItem);
    double price = 0.0;
    try {
      if (optionItem is Map) price = double.tryParse(optionItem['supplementPrice']?.toString() ?? '0') ?? 0.0;
      else price = (optionItem as dynamic).supplementPrice ?? 0.0;
    } catch (_) {}
    return {'name': name, 'price': price};
  }

  Map<String, dynamic> _cleanItemForPrint(dynamic item) {
    List<dynamic> options = [];
    void extractOpts(dynamic raw) {
      if (raw == null) return;
      if (raw is List) {
        for (var element in raw) {
          if (element is Map && element.containsKey('items') && element['items'] is List) {
            var subItems = element['items'] as List;
            if (subItems.isNotEmpty) {
              options.addAll(subItems.map((e) => _formatOption(e)));
              options.add({'name': "___SECTION_SEP___", 'price': 0.0});
            }
          } else {
            options.add(_formatOption(element));
          }
        }
        if (options.isNotEmpty && (options.last is Map) && options.last['name'] == "___SECTION_SEP___") options.removeLast();
      } else if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List && v.isNotEmpty) {
            options.addAll(v.map((e) => _formatOption(e)));
            options.add({'name': "___SECTION_SEP___", 'price': 0.0});
          }
        });
        if (options.isNotEmpty && (options.last is Map) && options.last['name'] == "___SECTION_SEP___") options.removeLast();
      }
    }
    final String name = _extractName(item);
    var qtyVal = 1;
    var priceVal = 0.0;
    if (item is Map) {
      qtyVal = int.tryParse(item['quantity']?.toString() ?? item['qty']?.toString() ?? '1') ?? 1;
      priceVal = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      extractOpts(item['options'] ?? item['selectedOptions']);
    } else {
      try { qtyVal = (item as dynamic).quantity; } catch (_) {}
      try { priceVal = (item as dynamic).price; } catch (_) {}
      try { extractOpts((item as dynamic).selectedOptions); } catch (_) {}
    }
    final List<String> removed = item is Map
        ? (item['removedIngredientNames'] as List? ?? []).map((e) => e.toString()).toList()
        : (item is! Map) ? (item as dynamic).removedIngredientNames ?? [] : [];
    return {
      'name': name,
      'qty': qtyVal,
      'price': priceVal.toStringAsFixed(2),
      'total': (priceVal * qtyVal).toStringAsFixed(2),
      'options': options,
      'removed': removed
    };
  }

  List<Map<String, dynamic>> _standardizeItems(dynamic inputItems) {
    List<Map<String, dynamic>> cleanList = [];
    if (inputItems is List) {
      for (var item in inputItems) cleanList.add(_cleanItemForPrint(item));
    }
    return cleanList;
  }

  Map<String, dynamic> _extractTransactionData(dynamic transaction) {
    if (transaction == null) return {};
    if (transaction is Map) return Map<String, dynamic>.from(transaction);
    Map<String, dynamic> tMap = {};
    try { tMap = (transaction as dynamic).toMap(); } catch (_) {}
    try { tMap['id'] ??= (transaction as dynamic).id; } catch (_) {}
    try { tMap['identifier'] ??= (transaction as dynamic).identifier; } catch (_) {}
    try { tMap['franchiseeId'] ??= (transaction as dynamic).franchiseeId; } catch (_) {}
    return tMap;
  }

  // ✅ CORRIGÉ — ne force plus isWifi si isBluetooth est déjà à true
  Future<Map<String, dynamic>> _resolvePrinterConfig(dynamic passedConfig) async {
    Map<String, dynamic> m = _normalizeConfig(passedConfig);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? printerConfigStr = prefs.getString('printer_config');
      if (printerConfigStr != null) {
        final parsed = jsonDecode(printerConfigStr);
        String? freshIp = parsed['ipAddress'] ?? parsed['ip'] ?? parsed['receiptPrinterIp'] ?? parsed['host'];
        if (freshIp != null && freshIp.contains('.')) {
          m['ipAddress'] = freshIp;
          // ✅ Ne pas écraser Bluetooth si déjà configuré en BT
          if (m['isBluetooth'] != true) {
            m['isWifi'] = true;
            m['isBluetooth'] = false;
          }
        }
      }
    } catch (e) {}
    return m;
  }

  // ✅ CORRIGÉ — ne force plus isBluetooth=false si une IP est présente
  Map<String, dynamic> _normalizeConfig(dynamic config) {
    Map<String, dynamic> m = {};
    if (config == null) return m;
    if (config is Map) {
      config.forEach((k, v) => m[k.toString()] = v);
    } else {
      try { m['isBluetooth'] = (config as dynamic).isBluetooth; } catch (_) {}
      try { m['macAddress'] = (config as dynamic).macAddress; } catch (_) {}
      try { m['isWifi'] = (config as dynamic).isWifi; } catch (_) {}
      try { m['ipAddress'] = (config as dynamic).ipAddress; } catch (_) {}
    }
    String detectedIp = m['ipAddress']?.toString() ?? m['ip']?.toString() ?? m['host']?.toString() ?? '';
    if (detectedIp.contains('.')) {
      m['ipAddress'] = detectedIp;
      // ✅ On ne force isWifi/isBluetooth QUE si aucun des deux n'est déjà défini
      if (m['isBluetooth'] == null && m['isWifi'] == null) {
        m['isWifi'] = true;
        m['isBluetooth'] = false;
      }
    }
    return m;
  }

  Future<void> printKitchenTicketSafe({
    required dynamic printerConfig,
    required List itemsToPrint,
    required String identifier,
    bool isUpdate = false,
    bool isReprint = false,
    String? orderType,
    dynamic franchisee
  }) async {
    await _tryRestoreSavedDevice();
    final resolvedConfig = await _resolvePrinterConfig(printerConfig);
    final List<Map<String, dynamic>> lines = _standardizeItems(itemsToPrint);
    final profile = await CapabilityProfile.load();
    _addJob(() async => _generateKitchenBytes({
      'paperWidthInt': 80,
      'identifier': identifier,
      'orderType': orderType,
      'lines': lines,
      'date': DateFormat('HH:mm').format(DateTime.now()),
      'profile': profile
    }), resolvedConfig);
  }

  Future<void> printReceipt({
    required dynamic printerConfig,
    required dynamic transaction,
    dynamic franchisee,
    dynamic receiptConfig
  }) async {
    await _tryRestoreSavedDevice();
    final resolvedConfig = await _resolvePrinterConfig(printerConfig);
    Map<String, dynamic> tMap = _extractTransactionData(transaction);
    tMap['items'] = _standardizeItems(tMap['items'] as List? ?? []);
    Map<String, dynamic> fMap = {};
    try {
      String fId = tMap['franchiseeId']?.toString() ?? '';
      if (fId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(fId).get();
        if (doc.exists) fMap = doc.data()!;
      }
    } catch (e) {}
    Map<String, dynamic> cMap = receiptConfig is Map ? Map.from(receiptConfig) : {};
    try {
      final localService = LocalConfigService();
      final savedConfig = await localService.getReceiptConfig();
      cMap['headerText'] ??= savedConfig.headerText;
      cMap['footerText'] ??= savedConfig.footerText;
      cMap['showVatDetails'] ??= savedConfig.showVatDetails;
    } catch (_) {}
    final profile = await CapabilityProfile.load();
    _addJob(() async => _generateReceiptBytes({
      'paperWidthInt': 80,
      'transaction': tMap,
      'franchisee': fMap,
      'config': cMap,
      'profile': profile
    }), resolvedConfig);
  }

  Future<void> printOrderAndReceipt({
    required dynamic printerConfig,
    required dynamic receiptConfig,
    required dynamic transaction,
    dynamic franchisee
  }) async {
    final resolvedConfig = await _resolvePrinterConfig(printerConfig);
    await printReceipt(printerConfig: resolvedConfig, receiptConfig: receiptConfig, transaction: transaction, franchisee: franchisee);
    List items = [];
    String identifier = "CLIENT";
    String orderTypeStr = "SUR PLACE";
    try {
      final tMap = _extractTransactionData(transaction);
      items = tMap['items'] ?? [];
      identifier = tMap['identifier']?.toString() ?? "CLIENT";
      orderTypeStr = tMap['orderType']?.toString() ?? "SUR PLACE";
    } catch (_) {}
    if (items.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 1500));
      await printKitchenTicketSafe(printerConfig: resolvedConfig, itemsToPrint: items, identifier: identifier, orderType: orderTypeStr);
    }
  }

  Future<void> printTestTicket({required dynamic printerConfig}) async {
    await _tryRestoreSavedDevice();
    final resolvedConfig = await _resolvePrinterConfig(printerConfig);
    _addJob(() async {
      final gen = Generator(PaperSize.mm80, await CapabilityProfile.load());
      List<int> b = [];
      b += gen.reset();
      b += _forceCP858Commands();
      b += [0x1B, 0x64, 0x02];
      b += gen.textEncoded(_encodeCP858("TEST SYSTEME"), styles: const PosStyles(align: PosAlign.center, bold: true));
      b += gen.textEncoded(_encodeCP858("Accents: € é à è ê ç °"), styles: const PosStyles(align: PosAlign.center));
      b += gen.feed(2);
      b += gen.cut();
      return b;
    }, resolvedConfig);
  }

  Future<void> diagnoseWifiPrinter(String ip, {int port = 9100}) async {
    try {
      Socket socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      socket.add([0x10, 0x04, 0x01]);
      await socket.flush();
      await Future.delayed(const Duration(seconds: 2));
      List<int> response = [];
      await for (var data in socket) {
        response.addAll(data);
        if (response.length > 10) break;
      }
      debugPrint("📊 Diagnostic WiFi - Réponse de l'imprimante: $response");
      socket.destroy();
    } catch (e) {
      debugPrint("📊 Diagnostic WiFi - Erreur: $e");
    }
  }
}

extension PrintingServiceZ on PrintingService {
  Future<void> printZTicket({
    required dynamic printerConfig,
    required dynamic session,
    required List transactions,
    required double declaredCash,
    required bool isManager,
    required String userName
  }) async {
    await _tryRestoreSavedDevice();
    final resolvedConfig = await _resolvePrinterConfig(printerConfig);
    double totalSales = 0;
    for (var t in transactions) {
      Map<String, dynamic> tMap = _extractTransactionData(t);
      totalSales += (tMap['total'] as num? ?? 0).toDouble();
    }
    double initialCash = 0;
    try {
      initialCash = (session is Map) ? (session['initialCash'] as num).toDouble() : (session as dynamic).initialCash;
    } catch (_) {}
    final profile = await CapabilityProfile.load();
    _addJob(() async => _generateZTicketBytes({
      'paperWidthInt': 80,
      'sessionInitialCash': initialCash,
      'declaredCash': declaredCash,
      'userName': userName,
      'isManager': isManager,
      'totalSales': totalSales.toStringAsFixed(2),
      'date': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      'profile': profile
    }), resolvedConfig);
  }
}

List<int> _generateZTicketBytes(Map<String, dynamic> params) {
  final int paperWidthInt = int.tryParse(params['paperWidthInt'].toString()) ?? 80;
  final PaperSize paper = paperWidthInt == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final CapabilityProfile profile = params['profile'];
  final Generator generator = Generator(paper, profile);
  List<int> bytes = [];
  bytes += generator.reset();
  bytes += _forceCP858Commands();
  bytes += [0x1B, 0x64, 0x02];
  const PosStyles sTitle = PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2);
  const PosStyles sNormal = PosStyles();
  bytes += generator.textEncoded(_encodeCP858('CLOTURE (Z)'), styles: sTitle);
  bytes += generator.textEncoded(_encodeCP858('Date: ${params['date']}'), styles: sNormal);
  bytes += generator.textEncoded(_encodeCP858('Ferme par: ${params['userName']}'), styles: sNormal);
  bytes += generator.hr();
  double initCash = double.tryParse(params['sessionInitialCash'].toString()) ?? 0.0;
  double declared = double.tryParse(params['declaredCash'].toString()) ?? 0.0;
  bytes += generator.textEncoded(_encodeCP858('FONDS DE CAISSE'), styles: const PosStyles(bold: true));
  int charWidth = paperWidthInt == 80 ? 48 : 32;
  bytes += generator.textEncoded(_encodeCP858(_formatRow('Ouverture :', '${initCash.toStringAsFixed(2)} EUR', width: charWidth)), styles: sNormal);
  bytes += generator.textEncoded(_encodeCP858(_formatRow('DECLARE :', '${declared.toStringAsFixed(2)} EUR', width: charWidth)), styles: const PosStyles(bold: true));
  bytes += generator.hr();
  if (params['isManager'] == true) {
    double totalSales = double.tryParse(params['totalSales'].toString()) ?? 0.0;
    bytes += generator.textEncoded(_encodeCP858('TOTAL VENTES: ${totalSales.toStringAsFixed(2)} EUR'), styles: const PosStyles(bold: true));
  }
  bytes += generator.feed(3);
  bytes += generator.cut();
  return bytes;
}