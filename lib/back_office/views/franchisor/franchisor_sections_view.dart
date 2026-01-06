import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
import 'franchisor_catalogue_view.dart';

class SectionsView extends StatefulWidget {
  const SectionsView({super.key});

  @override
  State<SectionsView> createState() => _SectionsViewState();
}

class _SectionsViewState extends State<SectionsView> {
  final _searchController = TextEditingController();

  // -- CACHE DONNÉES (Listes en mémoire) --
  List<ProductSection> _allSections = [];
  List<ProductFilter> _allFilters = [];

  // Abonnements aux flux de données
  final List<StreamSubscription> _subscriptions = [];
  bool _isLoading = true;

  // -- ETAT FILTRES --
  String _searchQuery = '';
  final Set<String> _selectedFilterIds = {};

  @override
  void initState() {
    super.initState();
    final repository = FranchiseRepository();
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    // 1. Abonnement aux Sections
    _subscriptions.add(repository.getSectionsStream(uid).listen((sections) {
      if (mounted) {
        setState(() {
          _allSections = sections;
          _isLoading = false;
        });
      }
    }));

    // 2. Abonnement aux Filtres
    _subscriptions.add(repository.getFiltersStream(uid).listen((filters) {
      if (mounted) {
        setState(() {
          _allFilters = filters;
        });
      }
    }));

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Logique de filtrage instantané (sur RAM)
  Map<String, dynamic> _getFilteredData() {
    List<ProductSection> filteredSections = List.from(_allSections);

    if (_searchQuery.isNotEmpty) {
      filteredSections = filteredSections
          .where((s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    if (_selectedFilterIds.isNotEmpty) {
      filteredSections = filteredSections
          .where((s) => s.filterIds.any((id) => _selectedFilterIds.contains(id)))
          .toList();
    }

    // Calcul des filtres pertinents
    Set<String> activeFilterIds = {};
    for (var section in _allSections) {
      activeFilterIds.addAll(section.filterIds);
    }

    List<ProductFilter> visibleFilters = _allFilters
        .where((f) => activeFilterIds.contains(f.id))
        .toList();

    // Tris
    visibleFilters.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    filteredSections.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return {
      'sections': filteredSections,
      'filters': visibleFilters,
    };
  }

  // --- NAVIGATION AVEC MISE À JOUR INSTANTANÉE ---
  void _openSectionForm(ProductSection? section, {bool isDuplicating = false}) async {
    // On attend le retour immédiat du formulaire
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SectionFormView(
          sectionToEdit: section,
          isDuplicating: isDuplicating,
        ),
      ),
    );

    // Si on a reçu une section (créée ou modifiée), on l'injecte direct dans la liste locale
    if (result != null && result is ProductSection) {
      setState(() {
        final index = _allSections.indexWhere((s) => s.sectionId == result.sectionId);
        if (index != -1) {
          _allSections[index] = result; // Mise à jour locale
        } else {
          _allSections.add(result); // Ajout local
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();

    final processed = _getFilteredData();
    final List<ProductSection> sectionsToShow = processed['sections'];
    final List<ProductFilter> relevantFilters = processed['filters'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeader(relevantFilters),
          Expanded(
            child: sectionsToShow.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: sectionsToShow.length,
              separatorBuilder: (c, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildSectionCard(
                  context, sectionsToShow[index], repository),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text("Nouvelle Section",
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openSectionForm(null),
      ),
    );
  }

  Widget _buildHeader(List<ProductFilter> filters) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            offset: const Offset(0, 4),
            blurRadius: 10,
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 45,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher une section...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchController.clear())
                    : null,
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          if (filters.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((filter) {
                  final isSelected = _selectedFilterIds.contains(filter.id);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(filter.name),
                      selected: isSelected,
                      showCheckmark: false,
                      selectedColor: Colors.black,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? Colors.black : Colors.grey.shade300,
                        ),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedFilterIds.add(filter.id);
                          } else {
                            _selectedFilterIds.remove(filter.id);
                          }
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.view_stream_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "Aucune section trouvée",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          if (_selectedFilterIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selectedFilterIds.clear()),
              child: const Text("Effacer les filtres"),
            )
        ],
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, ProductSection section,
      FranchiseRepository repository) {

    IconData typeIcon;
    Color typeColor;
    String typeLabel;

    switch (section.type) {
      case 'radio':
        typeIcon = Icons.radio_button_checked;
        typeColor = Colors.teal;
        typeLabel = "Choix Unique";
        break;
      case 'checkbox':
        typeIcon = Icons.check_box;
        typeColor = Colors.indigo;
        typeLabel = "Choix Multiple";
        break;
      case 'increment':
        typeIcon = Icons.exposure_plus_1;
        typeColor = Colors.orange;
        typeLabel = "Quantité";
        break;
      default:
        typeIcon = Icons.list;
        typeColor = Colors.grey;
        typeLabel = "Standard";
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openSectionForm(section),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: typeColor),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300)
                            ),
                            child: Text(
                              typeLabel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${section.items.length} produit(s)",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.copy_all_rounded,
                      color: Colors.grey.shade400,
                      onTap: () => _openSectionForm(section, isDuplicating: true),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.edit_rounded,
                      color: Colors.blue.shade400,
                      onTap: () => _openSectionForm(section),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.delete_outline_rounded,
                      color: Colors.red.shade300,
                      onTap: () =>
                          _deleteSection(context, repository, section),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
        required Color color,
        required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  void _deleteSection(BuildContext context, FranchiseRepository repository,
      ProductSection section) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Supprimer ?"),
          content: Text("Supprimer la section '${section.title}' ?"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
                child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
                onPressed: () => Navigator.pop(ctx, false)),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0
                ),
                child: const Text("Supprimer"),
                onPressed: () => Navigator.pop(ctx, true))
          ],
        ));
    if (confirm == true) {
      // 1. SUPPRESSION INSTANTANÉE (Local)
      setState(() {
        _allSections.removeWhere((s) => s.sectionId == section.sectionId);
      });
      // 2. SUPPRESSION ARRIÈRE-PLAN
      await repository.deleteSection(section.sectionId);
    }
  }
}

// -----------------------------------------------------------------------------
// --- FORMULAIRE D'ÉDITION (Enregistrement Instantané) ---
// -----------------------------------------------------------------------------

class SectionFormView extends StatefulWidget {
  final ProductSection? sectionToEdit;
  final bool isDuplicating;

  const SectionFormView(
      {super.key, this.sectionToEdit, this.isDuplicating = false});

  @override
  State<SectionFormView> createState() => _SectionFormViewState();
}

class _SectionFormViewState extends State<SectionFormView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  String _type = 'radio';
  int _min = 1;
  int _max = 1;
  List<SectionItem> _items = [];
  List<String> _selectedFilterIds = [];

  // Note: On ne met pas de variable _isLoading ici car on quitte instantanément

  List<ProductFilter> _availableFilters = [];
  StreamSubscription? _filtersSub;

  @override
  void initState() {
    super.initState();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final repo = FranchiseRepository();
    // Chargement anticipé
    _filtersSub = repo.getFiltersStream(authProvider.firebaseUser!.uid).listen((data) {
      if(mounted) {
        data.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() => _availableFilters = data);
      }
    });

    if (widget.sectionToEdit != null) {
      _titleController.text = widget.sectionToEdit!.title +
          (widget.isDuplicating ? ' (Copie)' : '');
      _type = widget.sectionToEdit!.type;
      _min = widget.sectionToEdit!.selectionMin;
      _max = widget.sectionToEdit!.selectionMax;
      _items = widget.sectionToEdit!.items
          .map((item) => SectionItem(
          product: item.product, supplementPrice: item.supplementPrice))
          .toList();
      _selectedFilterIds = List.from(widget.sectionToEdit!.filterIds);
    }
  }

  @override
  void dispose() {
    _filtersSub?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  void _reorderProducts(int oldIndex, int newIndex) => setState(() {
    if (newIndex > oldIndex) newIndex -= 1;
    _items.insert(newIndex, _items.removeAt(oldIndex));
  });

  Future<void> _saveSection() async {
    if (!_formKey.currentState!.validate()) return;

    // Pas de spinner, on veut du réactif !

    final repository = FranchiseRepository();
    final sectionId = widget.sectionToEdit == null || widget.isDuplicating
        ? const Uuid().v4()
        : widget.sectionToEdit!.sectionId;
    final id = widget.sectionToEdit == null || widget.isDuplicating
        ? const Uuid().v4()
        : widget.sectionToEdit!.id;

    final newSection = ProductSection(
      id: id,
      sectionId: sectionId,
      title: _titleController.text,
      type: _type,
      selectionMin: _min,
      selectionMax: _max,
      items: _items,
      filterIds: _selectedFilterIds,
    );

    // 1. RETOUR IMMÉDIAT avec la donnée
    Navigator.pop(context, newSection);

    // 2. SAUVEGARDE EN ARRIÈRE-PLAN
    try {
      await repository.saveSection(newSection);
    } catch (e) {
      print("Erreur de sauvegarde (background): $e");
    }
  }

  Widget _buildFilterSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Filtres de Rangement",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: _availableFilters.map((filter) {
            final isSelected = _selectedFilterIds.contains(filter.id);
            return FilterChip(
                label: Text(filter.name),
                selected: isSelected,
                showCheckmark: false,
                selectedColor: Colors.black,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: isSelected ? Colors.black : Colors.grey.shade300),
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedFilterIds.add(filter.id);
                    } else {
                      _selectedFilterIds.remove(filter.id);
                    }
                  });
                });
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
          title: Text(widget.sectionToEdit != null
              ? "Modifier la Section"
              : "Créer une Section"),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text("Enregistrer"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0
                  ),
                  onPressed: _saveSection
              ),
            )
          ]),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Configuration Générale", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                          labelText: "Titre de la section (ex: Choix Sauce)",
                          border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _type,
                          decoration: const InputDecoration(
                              labelText: "Type de sélection",
                              border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(
                                value: 'radio', child: Text("Choix Unique (Radio)")),
                            DropdownMenuItem(
                                value: 'checkbox', child: Text("Choix Multiple (Checkbox)")),
                            DropdownMenuItem(
                                value: 'increment',
                                child: Text("Quantité (Incrémentation)"))
                          ],
                          onChanged: (val) => setState(() {
                            _type = val!;
                            if (_type == 'radio') {
                              _min = 1;
                              _max = 1;
                            } else {
                              if (_min == 1 && _max == 1) {
                                _min = 0;
                                _max = 5;
                              }
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                          child: TextFormField(
                            key: ValueKey('min_$_type'),
                            initialValue: _min.toString(),
                            decoration: const InputDecoration(
                                labelText: "Min", border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (val) => _min = int.tryParse(val) ?? 0,
                            readOnly: _type == 'radio',
                            enabled: _type != 'radio',
                          )),
                      const SizedBox(width: 16),
                      Expanded(
                          child: TextFormField(
                            key: ValueKey('max_$_type'),
                            initialValue: _max.toString(),
                            decoration: const InputDecoration(
                                labelText: "Max", border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (val) => _max = int.tryParse(val) ?? 1,
                            readOnly: _type == 'radio',
                            enabled: _type != 'radio',
                          )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildFilterSelector(context),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Produits inclus dans la section",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  icon: const Icon(Icons.add_circle),
                  label: const Text("Ajouter des produits"),
                  style: TextButton.styleFrom(foregroundColor: Colors.black),
                  onPressed: () async {
                    final selectedProducts =
                    await showDialog<List<MasterProduct>>(
                        context: context,
                        builder: (context) => ProductPickerDialog(
                            ingredientsOnly: false,
                            initialSelection:
                            _items.map((e) => e.product).toList()));
                    if (selectedProducts != null) {
                      setState(() {
                        final updatedItems = <SectionItem>[];
                        for (var p in selectedProducts) {
                          final existing =
                          _items.where((item) => item.product.id == p.id);
                          updatedItems.add(existing.isNotEmpty
                              ? existing.first
                              : SectionItem(product: p));
                        }
                        _items = updatedItems;
                      });
                    }
                  },
                )
              ],
            ),

            const SizedBox(height: 8),

            if (_items.isEmpty)
              Container(
                height: 120,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)
                ),
                child: Center(child: Text("Aucun produit ajouté", style: TextStyle(color: Colors.grey.shade500))),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                onReorder: _reorderProducts,
                proxyDecorator: (child, index, animation) => Material(
                    elevation: 5, color: Colors.transparent, child: child
                ),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Container(
                    key: ValueKey(item.product.id),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 1))
                        ]
                    ),
                    child: ListTile(
                      leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8)
                          ),
                          child: const Icon(Icons.drag_indicator, color: Colors.grey, size: 20)
                      ),
                      title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: SizedBox(
                        width: 120,
                        child: TextFormField(
                          initialValue:
                          item.supplementPrice == 0 ? "" : item.supplementPrice.toStringAsFixed(2),
                          decoration: const InputDecoration(
                              labelText: "+ Supplément",
                              suffixText: "€",
                              isDense: true,
                              border: OutlineInputBorder()),
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            item.supplementPrice = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}