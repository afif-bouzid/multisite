import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';

class FranchiseeDealsView extends StatelessWidget {
  const FranchiseeDealsView({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.firebaseUser == null) {
      return const Center(child: Text("Erreur : Utilisateur non trouvé."));
    }
    final franchiseeId = authProvider.firebaseUser!.uid;

    final dealsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(franchiseeId)
        .collection('deals');

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: dealsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text("Créez votre première offre promotionnelle !"));
          }

          final deals = snapshot.data!.docs
              .map((doc) => Deal.fromFirestore(doc))
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: deals.length,
            itemBuilder: (context, index) {
              final deal = deals[index];
              return Card(
                child: ListTile(
                  title: Text(deal.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      "${deal.price.toStringAsFixed(2)} € - ${deal.sectionIds.length} sections au choix"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => FranchiseeDealFormView(
                                      dealToEdit: deal)))),
                      IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () async {
                            await dealsRef.doc(deal.id).delete();
                          }),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text("Nouvelle Offre"),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const FranchiseeDealFormView())),
      ),
    );
  }
}

class FranchiseeDealFormView extends StatefulWidget {
  final Deal? dealToEdit;

  const FranchiseeDealFormView({super.key, this.dealToEdit});

  @override
  State<FranchiseeDealFormView> createState() => _FranchiseeDealFormViewState();
}

class _FranchiseeDealFormViewState extends State<FranchiseeDealFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  List<String> _selectedSectionIds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.dealToEdit != null) {
      _nameController.text = widget.dealToEdit!.name;
      _priceController.text = widget.dealToEdit!.price.toStringAsFixed(2);
      _selectedSectionIds = List.from(widget.dealToEdit!.sectionIds);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _saveDeal() async {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (price == null || _selectedSectionIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Veuillez saisir un prix valide et sélectionner au moins une section.")));
      return;
    }
    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.firebaseUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final franchiseeId = authProvider.firebaseUser!.uid;
    final dealsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(franchiseeId)
        .collection('deals');

    final deal = Deal(
      id: widget.dealToEdit?.id ?? const Uuid().v4(),
      name: _nameController.text,
      price: price,
      sectionIds: _selectedSectionIds,
    );

    try {
      await dealsRef.doc(deal.id).set(deal.toMap());
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur de sauvegarde: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.franchiseUser?.franchisorId == null) {
      return const Scaffold(
          body: Center(
              child: Text("Erreur: Données du franchiseur introuvables.")));
    }
    final franchisorId = authProvider.franchiseUser!.franchisorId!;
    final repository = FranchiseRepository();

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.dealToEdit == null
              ? "Créer une Offre Promo"
              : "Modifier l'Offre"),
          actions: [
            IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isLoading ? null : _saveDeal)
          ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                          labelText: "Nom de l'offre (ex: Menu Étudiant)"),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                          labelText: "Prix promotionnel (€)"),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const Divider(height: 40),
                  Text("Sélection des Sections pour cette Formule",
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  StreamBuilder<List<ProductSection>>(
                    stream: repository.getSectionsStream(franchisorId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final allSections = snapshot.data ?? [];
                      if (allSections.isEmpty)
                        return const Text(
                            "Le franchiseur doit d'abord créer des sections.");

                      return Column(
                        children: allSections.map((section) {
                          final isSelected =
                              _selectedSectionIds.contains(section.sectionId);
                          return CheckboxListTile(
                            title: Text(section.title),
                            subtitle: Text(
                                "Type: ${section.type}, Min: ${section.selectionMin}, Max: ${section.selectionMax}"),
                            value: isSelected,
                            onChanged: (selected) {
                              setState(() {
                                if (selected!) {
                                  _selectedSectionIds.add(section.sectionId);
                                } else {
                                  _selectedSectionIds.remove(section.sectionId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
