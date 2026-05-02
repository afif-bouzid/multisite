import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../../../core/auth_provider.dart';
import '../../../../../core/repository/repository.dart';
import '../../../../models.dart';

// =========================================================================
// ONGLET 1 : CONFIGURATION COMMERCIALE (LA BOUTIQUE ULTRA-COMPLÈTE)
// =========================================================================
class ClickAndCollectManager extends StatefulWidget {
  const ClickAndCollectManager({super.key});
  @override
  State<ClickAndCollectManager> createState() => _ClickAndCollectManagerState();
}

class _ClickAndCollectManagerState extends State<ClickAndCollectManager> {
  final _formKey = GlobalKey<FormState>();

  // Identité & Design
  final _domainController = TextEditingController();
  final _themeColorController = TextEditingController();
  final _messageController = TextEditingController();

  // Logistique & Tarifs
  final _minAmountController = TextEditingController();
  final _prepTimeController = TextEditingController();
  final _serviceFeeController = TextEditingController();
  final _instructionController = TextEditingController();

  // Contrôle des Flux
  final _maxOrdersPerSlotController = TextEditingController();
  final _webClosingOffsetController = TextEditingController();

  // Toggles
  bool _allowOnlinePayment = true;
  bool _allowPayAtCounter = true;
  bool _isPreOrderEnabled = true;
  bool _enableWebDeals = true; // NOUVEAU : Toggle pour les promos Web
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.effectiveStoreId).get();
    if (doc.exists) {
      final data = doc.data()?['clickAndCollectConfig'] as Map<String, dynamic>? ?? {};
      setState(() {
        _domainController.text = data['customDomain'] ?? '';
        _themeColorController.text = data['themeColorHex'] ?? '#000000';
        _minAmountController.text = (data['minOrderAmount'] ?? 0.0).toString();
        _prepTimeController.text = (data['estimatedPrepTime'] ?? 15).toString();
        _messageController.text = data['contactMessage'] ?? '';
        _instructionController.text = data['pickupInstructions'] ?? '';
        _serviceFeeController.text = (data['serviceFee'] ?? 0.0).toString();
        _maxOrdersPerSlotController.text = (data['maxOrdersPer15Min'] ?? 10).toString();
        _webClosingOffsetController.text = (data['webClosingOffsetMin'] ?? 30).toString();

        _allowOnlinePayment = data['allowOnlinePayment'] ?? true;
        _allowPayAtCounter = data['allowPayAtCounter'] ?? true;
        _isPreOrderEnabled = data['isPreOrderEnabled'] ?? true;
        _enableWebDeals = data['enableWebDeals'] ?? true; // Chargement de l'option Promo
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- SECTION 1 : VISIBILITÉ & DESIGN ---
            _buildSectionTitle("Visibilité & Design"),
            Row(
              children: [
                Expanded(flex: 2, child: TextFormField(controller: _domainController, decoration: const InputDecoration(labelText: "Identifiant URL boutique", prefixIcon: Icon(Icons.link)))),
                const SizedBox(width: 15),
                Expanded(flex: 1, child: TextFormField(controller: _themeColorController, decoration: const InputDecoration(labelText: "Couleur (Hex)", prefixIcon: Icon(Icons.color_lens)))),
              ],
            ),
            const SizedBox(height: 15),
            TextFormField(controller: _messageController, decoration: const InputDecoration(labelText: "Message d'accueil (Bannière)", border: OutlineInputBorder())),
            const SizedBox(height: 20),

            // --- SECTION 2 : LOGISTIQUE & TARIFS ---
            _buildSectionTitle("Logistique & Tarifs"),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _minAmountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Minimum (€)", prefixIcon: Icon(Icons.shopping_basket)))),
                const SizedBox(width: 15),
                Expanded(child: TextFormField(controller: _serviceFeeController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Frais emballage (€)", prefixIcon: Icon(Icons.takeout_dining)))),
              ],
            ),
            const SizedBox(height: 15),
            TextFormField(controller: _instructionController, maxLines: 2, decoration: const InputDecoration(labelText: "Instructions de retrait (Ex: Allez au comptoir dédié)", border: OutlineInputBorder())),
            const SizedBox(height: 20),

            // --- SECTION 3 : CONTRÔLE DES FLUX ---
            _buildSectionTitle("Contrôle des Flux & Cuisine"),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _prepTimeController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Temps Prep. (min)", prefixIcon: Icon(Icons.timer)))),
                const SizedBox(width: 15),
                Expanded(child: TextFormField(controller: _maxOrdersPerSlotController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Max commandes / 15min", prefixIcon: Icon(Icons.speed), helperText: "Anti-engorgement cuisine"))),
                const SizedBox(width: 15),
                Expanded(child: TextFormField(controller: _webClosingOffsetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Fermeture anticipée (min)", prefixIcon: Icon(Icons.door_front_door), helperText: "Avant la fermeture réelle"))),
              ],
            ),
            const SizedBox(height: 20),

            // --- SECTION 4 : PROMOTIONS & FIDÉLITÉ (NOUVEAU) ---
            _buildSectionTitle("Promotions & Offres"),
            SwitchListTile(
                title: const Text("Activer les offres en ligne"),
                subtitle: const Text("Permet aux clients Web d'utiliser les promotions configurées dans votre onglet 'Offres'."),
                value: _enableWebDeals,
                onChanged: (v) => setState(() => _enableWebDeals = v)
            ),
            const SizedBox(height: 20),

            // --- SECTION 5 : PAIEMENTS & COMMANDES ---
            _buildSectionTitle("Paiements & Commandes"),
            SwitchListTile(title: const Text("Autoriser les précommandes"), subtitle: const Text("Le client peut choisir l'heure de retrait de son choix."), value: _isPreOrderEnabled, onChanged: (v) => setState(() => _isPreOrderEnabled = v)),
            SwitchListTile(title: const Text("Paiement CB en ligne"), value: _allowOnlinePayment, onChanged: (v) => setState(() => _allowOnlinePayment = v)),
            SwitchListTile(title: const Text("Paiement au comptoir (Sur place)"), value: _allowPayAtCounter, onChanged: (v) => setState(() => _allowPayAtCounter = v)),

            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: const Icon(Icons.save),
              label: const Text("ENREGISTRER LA BOUTIQUE"),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.black, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveConfig() async {
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    await FirebaseFirestore.instance.collection('users').doc(user?.effectiveStoreId).set({
      'clickAndCollectConfig': {
        'customDomain': _domainController.text.trim().toLowerCase(),
        'themeColorHex': _themeColorController.text.trim(),
        'minOrderAmount': double.tryParse(_minAmountController.text.replaceAll(',', '.')) ?? 0.0,
        'estimatedPrepTime': int.tryParse(_prepTimeController.text) ?? 15,
        'serviceFee': double.tryParse(_serviceFeeController.text.replaceAll(',', '.')) ?? 0.0,
        'maxOrdersPer15Min': int.tryParse(_maxOrdersPerSlotController.text) ?? 10,
        'webClosingOffsetMin': int.tryParse(_webClosingOffsetController.text) ?? 30,
        'contactMessage': _messageController.text,
        'pickupInstructions': _instructionController.text,
        'allowOnlinePayment': _allowOnlinePayment,
        'allowPayAtCounter': _allowPayAtCounter,
        'isPreOrderEnabled': _isPreOrderEnabled,
        'enableWebDeals': _enableWebDeals, // Sauvegarde de l'option Promo
      }
    }, SetOptions(merge: true));
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Réglages enregistrés avec succès !")));
  }

  Widget _buildSectionTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 12, top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)), const Divider()]));
}

// =========================================================================
// ONGLET 2 : EXCLUSION PRODUITS
// =========================================================================
class ClickCollectProductExclusionTab extends StatefulWidget {
  const ClickCollectProductExclusionTab({super.key});
  @override
  State<ClickCollectProductExclusionTab> createState() => _ClickCollectProductExclusionTabState();
}

class _ClickCollectProductExclusionTabState extends State<ClickCollectProductExclusionTab> {
  final Set<String> _excludedProductIds = {};
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadExclusions();
  }

  Future<void> _loadExclusions() async {
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user?.effectiveStoreId).collection('config').doc('click_collect_exclusions').get();
    if (doc.exists) {
      setState(() => _excludedProductIds.addAll(List<String>.from(doc.data()?['excludedIds'] ?? [])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final repo = FranchiseRepository();
    return Column(
      children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(decoration: const InputDecoration(hintText: "Rechercher un produit...", prefixIcon: Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder()), onChanged: (v) => setState(() => _searchQuery = v))),
        Expanded(
          child: StreamBuilder<List<MasterProduct>>(
            stream: repo.getFranchiseeVisibleProductsStream(auth.franchiseUser!.effectiveStoreId, auth.franchiseUser!.franchisorId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final products = snapshot.data!.where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.separated(
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final p = products[index];
                    final isExcluded = _excludedProductIds.contains(p.productId);
                    return SwitchListTile(
                      title: Text(p.name, style: TextStyle(decoration: isExcluded ? TextDecoration.lineThrough : null, color: isExcluded ? Colors.grey : Colors.black, fontWeight: isExcluded ? FontWeight.normal : FontWeight.bold)),
                      secondary: Icon(isExcluded ? Icons.web_asset_off : Icons.web, color: isExcluded ? Colors.red : Colors.green),
                      subtitle: Text(isExcluded ? "Exclu" : "En ligne"),
                      value: !isExcluded,
                      activeColor: Colors.green,
                      onChanged: (v) => setState(() => v ? _excludedProductIds.remove(p.productId) : _excludedProductIds.add(p.productId)),
                    );
                  },
                ),
              );
            },
          ),
        ),
        Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
                onPressed: _saveExclusions,
                icon: const Icon(Icons.cloud_upload),
                label: const Text("PUBLIER LE MENU WEB"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.black, foregroundColor: Colors.white)
            )
        ),
      ],
    );
  }

  Future<void> _saveExclusions() async {
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    await FirebaseFirestore.instance.collection('users').doc(user?.effectiveStoreId).collection('config').doc('click_collect_exclusions').set({'excludedIds': _excludedProductIds.toList()});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Menu mis à jour !")));
  }
}

// =========================================================================
// ONGLET 3 : AUTOMATES & ALERTES (TECHNIQUE)
// =========================================================================
class ClickCollectTechnicalTab extends StatefulWidget {
  const ClickCollectTechnicalTab({super.key});
  @override
  State<ClickCollectTechnicalTab> createState() => _ClickCollectTechnicalTabState();
}

class _ClickCollectTechnicalTabState extends State<ClickCollectTechnicalTab> {
  bool _isRushMode = false;
  bool _uberSound = true;
  bool _autoKitchen = true;
  bool _autoReceipt = false;

  @override
  void initState() {
    super.initState();
    _loadTechConfig();
  }

  Future<void> _loadTechConfig() async {
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user?.effectiveStoreId).get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      setState(() {
        _isRushMode = data['isRushModeActive'] ?? false;
        _uberSound = data['clickAndCollectConfig']?['enableUberSound'] ?? true;
        _autoKitchen = data['clickAndCollectConfig']?['autoPrintKitchen'] ?? true;
        _autoReceipt = data['clickAndCollectConfig']?['autoPrintReceipt'] ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildTechCard("CONTRÔLE D'URGENCE", Icons.warning_amber, Colors.red,
            SwitchListTile(title: const Text("Mode RUSH (Stopper les ventes)"), subtitle: const Text("Désactive la prise de commande sur le site immédiatement."), value: _isRushMode, activeColor: Colors.red, onChanged: (v) => _updateField('isRushModeActive', v))),
        const SizedBox(height: 20),
        _buildTechCard("NOTIFICATIONS CAISSE", Icons.notifications_active, Colors.amber.shade800,
            SwitchListTile(title: const Text("Sonnerie type 'Uber Eats'"), subtitle: const Text("Alerte sonore répétée lors d'une nouvelle commande web."), value: _uberSound, onChanged: (v) => _updateField('enableUberSound', v, nested: true))),
        const SizedBox(height: 20),
        _buildTechCard("IMPRESSION AUTOMATIQUE", Icons.print, Colors.blue,
            Column(children: [
              SwitchListTile(title: const Text("Cuisine auto."), subtitle: const Text("Imprime dès le paiement validé (CB ou Sur place)."), value: _autoKitchen, onChanged: (v) => _updateField('autoPrintKitchen', v, nested: true)),
              SwitchListTile(title: const Text("Ticket client auto."), subtitle: const Text("Imprime le ticket de caisse pour la préparation du sac."), value: _autoReceipt, onChanged: (v) => _updateField('autoPrintReceipt', v, nested: true)),
            ])),
      ],
    );
  }

  Widget _buildTechCard(String title, IconData icon, Color color, Widget content) {
    return Card(
        elevation: 2,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16))]),
                  const Divider(),
                  content
                ]
            )
        )
    );
  }

  Future<void> _updateField(String key, bool value, {bool nested = false}) async {
    setState(() { if (key == 'isRushModeActive') _isRushMode = value; if (key == 'enableUberSound') _uberSound = value; if (key == 'autoPrintKitchen') _autoKitchen = value; if (key == 'autoPrintReceipt') _autoReceipt = value; });
    final user = Provider.of<AuthProvider>(context, listen: false).franchiseUser;
    final data = nested ? {'clickAndCollectConfig': {key: value}} : {key: value};
    await FirebaseFirestore.instance.collection('users').doc(user?.effectiveStoreId).set(data, SetOptions(merge: true));
  }
}