import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
class SectionsView extends StatelessWidget {
  const SectionsView({super.key});
  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.firebaseUser;
    if (user == null) {
      return const Scaffold(
          body: Center(child: Text("Utilisateur non connecté")));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<ProductSection>>(
        stream: repository.getSectionsStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erreur: ${snapshot.error}"));
          }
          final sections = snapshot.data ?? [];
          if (sections.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt_rounded, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Aucune section créée.",
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }
          sections.sort((a, b) => a.title.compareTo(b.title));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sections.length,
            separatorBuilder: (c, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final section = sections[index];
              return _buildSectionCard(context, section, repository);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_section_fab',
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Nouvelle Section",
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const SectionFormView())),
      ),    );
  }
  Widget _buildSectionCard(BuildContext context, ProductSection section, FranchiseRepository repo) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => SectionFormView(sectionToEdit: section))),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.edit,
                        color: Colors.blueGrey,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    SectionFormView(sectionToEdit: section))),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        icon: Icons.delete_outline,
                        color: Colors.redAccent,
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Supprimer ?"),
                                content: Text(
                                    "Supprimer la section '${section.title}' ?"),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text("Annuler")),
                                  ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white),
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: const Text("Supprimer"))
                                ],
                              ));
                          if (confirm == true) {
                            await repo.deleteSection(section.sectionId);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoBadge(
                    icon: _getTypeIcon(section.type),
                    label: _getTypeLabel(section.type),
                    color: _getTypeColor(section.type),
                    isBold: true,
                  ),
                  _buildInfoBadge(
                    icon: Icons.unfold_more_rounded,
                    label: "Choix : ${section.selectionMin} - ${section.selectionMax}",
                    color: Colors.grey.shade700,
                    bgColor: Colors.grey.shade100,
                  ),
                  _buildInfoBadge(
                    icon: Icons.fastfood_rounded,
                    label: "${section.items.length} produits",
                    color: Colors.blueGrey.shade700,
                    bgColor: Colors.blueGrey.shade50,
                  ),
                ],
              ),
            ],
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
          color: color.withOpacity(0.1),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
  Widget _buildInfoBadge({
    required IconData icon,
    required String label,
    required Color color,
    Color? bgColor,
    bool isBold = false,
  }) {
    final background = bgColor ?? color.withOpacity(0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  String _getTypeLabel(String type) {
    final t = type.toLowerCase();
    if (t.contains('radio') || t.contains('unique')) return 'Choix Unique';
    if (t.contains('check') || t.contains('multi')) return 'Choix Multiples';
    if (t.contains('quantity') || t.contains('increment')) return 'Quantité (Compteur)';
    return 'Standard';
  }
  Color _getTypeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('radio') || t.contains('unique')) return const Color(0xFFE65100);
    if (t.contains('check') || t.contains('multi')) return const Color(0xFF1565C0);
    if (t.contains('quantity') || t.contains('increment')) return const Color(0xFF2E7D32);
    return Colors.grey.shade800;
  }
  IconData _getTypeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('radio') || t.contains('unique')) return Icons.radio_button_checked;
    if (t.contains('check') || t.contains('multi')) return Icons.check_box;
    if (t.contains('quantity') || t.contains('increment')) return Icons.exposure_plus_1;
    return Icons.widgets;
  }
}
class SectionFormView extends StatefulWidget {
  final ProductSection? sectionToEdit;
  const SectionFormView({super.key, this.sectionToEdit});
  @override
  State<SectionFormView> createState() => _SectionFormViewState();
}
class _SectionFormViewState extends State<SectionFormView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _minController = TextEditingController(text: "0");
  final _maxController = TextEditingController(text: "1");
  String _type = 'checkbox';
  List<SectionItem> _items = [];
  bool _isSaving = false;
  final FranchiseRepository _repository = FranchiseRepository();
  List<MasterProduct>? _cachedProducts;
  List<ProductFilter>? _cachedFilters;
  bool _isDataLoading = true;
  @override
  void initState() {
    super.initState();
    if (widget.sectionToEdit != null) {
      final s = widget.sectionToEdit!;
      _titleController.text = s.title;
      _minController.text = s.selectionMin.toString();
      _maxController.text = s.selectionMax.toString();
      _type = s.type;
      _items = List.from(s.items);
    }
    _preloadData();
  }
  Future<void> _preloadData() async {
    final user = Provider.of<AuthProvider>(context, listen: false).firebaseUser;
    if (user == null) return;
    try {
      final results = await Future.wait([
        _repository.getMasterProductsStream(user.uid).first,
        _repository.getFiltersStream(user.uid).first,
      ]);
      if (mounted) {
        setState(() {
          _cachedProducts = results[0] as List<MasterProduct>;
          _cachedFilters = results[1] as List<ProductFilter>;
          _isDataLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur de pré-chargement: $e");
      if (mounted) {
        setState(() => _isDataLoading = false);
      }
    }
  }
  @override
  void dispose() {
    _titleController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }
  Future<void> _saveSection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final user = Provider.of<AuthProvider>(context, listen: false).firebaseUser!;
    final newSection = ProductSection(
      id: widget.sectionToEdit?.id ?? '',
      sectionId: widget.sectionToEdit?.sectionId ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      type: _type,
      selectionMin: int.tryParse(_minController.text) ?? 0,
      selectionMax: int.tryParse(_maxController.text) ?? 1,
      items: _items,
      filterIds: widget.sectionToEdit?.filterIds ?? [],
    );
    try {
      await _repository.saveSection(newSection);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  void _openProductPicker() async {
    if (_isDataLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chargement des produits en cours...")),
      );
      return;
    }
    if (_cachedProducts == null || _cachedFilters == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de récupérer les produits.")),
      );
      return;
    }
    final List<MasterProduct>? selected = await showDialog<List<MasterProduct>>(
      context: context,
      builder: (ctx) => ProductPickerDialog(
        availableProducts: _cachedProducts!,
        availableFilters: _cachedFilters!,
        initialSelection: _items.map((e) => e.product).toList(),
      ),
    );
    if (selected != null) {
      setState(() {
        final newItems = <SectionItem>[];
        for (var prod in selected) {
          final existing = _items
              .where((i) => i.product.productId == prod.productId)
              .firstOrNull;
          newItems.add(SectionItem(
            product: prod,
            supplementPrice: existing?.supplementPrice ?? 0.0,
          ));
        }
        _items = newItems;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.sectionToEdit == null
            ? "Créer une Section"
            : "Modifier la Section"),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.check),
            onPressed: _isSaving ? null : _saveSection,
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: "Titre de la section (ex: Sauces)",
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? "Requis" : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _type,
                          decoration: const InputDecoration(
                              labelText: "Type de choix",
                              border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(
                                value: 'checkbox',
                                child: Text("Choix Multiples")),
                            DropdownMenuItem(
                                value: 'radio', child: Text("Choix Unique")),
                            DropdownMenuItem(
                                value: 'quantity', child: Text("Quantité")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _type = val;
                                if (_type == 'radio') {
                                  _minController.text = "1";
                                  _maxController.text = "1";
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _minController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: "Min", border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _maxController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: "Max", border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text("Produits de la section",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    if (_isDataLoading)
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                  ],
                ),
                TextButton.icon(
                  onPressed: _openProductPicker,
                  icon: const Icon(Icons.add),
                  label: const Text("Ajouter"),
                  style: TextButton.styleFrom(
                    foregroundColor: _isDataLoading ? Colors.grey : Colors.blue,
                  ),
                )
              ],
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300)),
                child: const Text("Aucun produit ajouté.",
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    key: ValueKey(item.product.productId),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    elevation: 1,
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle, color: Colors.grey),
                      title: Text(item.product.name,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: item.product.isIngredient
                          ? const Text("Ingrédient (Non vendable)", style: TextStyle(fontSize: 12, color: Colors.orange))
                          : null,
                      trailing: SizedBox(
                        width: 140,
                        child: Row(
                          children: [
                            const Text("+ ", style: TextStyle(color: Colors.grey)),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.supplementPrice.toString(),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  suffixText: "€",
                                  border: UnderlineInputBorder(),
                                ),
                                onChanged: (val) {
                                  final normalized = val.replaceAll(',', '.');
                                  final p = double.tryParse(normalized) ?? 0.0;
                                  item.supplementPrice = p;
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _items.removeAt(index);
                                });
                              },
                            )
                          ],
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
class ProductPickerDialog extends StatefulWidget {
  final List<MasterProduct> availableProducts;
  final List<ProductFilter> availableFilters;
  final List<MasterProduct> initialSelection;
  final bool ingredientsOnly;
  const ProductPickerDialog({
    super.key,
    required this.availableProducts,
    required this.availableFilters,
    required this.initialSelection,
    this.ingredientsOnly = false,
  });
  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}
class _ProductPickerDialogState extends State<ProductPickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedFilterId;
  List<MasterProduct> _selectedProducts = [];
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedProducts = List.from(widget.initialSelection);
    if (widget.ingredientsOnly) {
      _tabController.index = 1;
    }
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedFilterId = null;
        });
      }
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }
  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }
  void _toggleProduct(MasterProduct product) {
    setState(() {
      if (_selectedProducts.any((p) => p.productId == product.productId)) {
        _selectedProducts.removeWhere((p) => p.productId == product.productId);
      } else {
        _selectedProducts.add(product);
      }
    });
  }
  List<MasterProduct> _filterProducts(List<MasterProduct> source) {
    return source.where((p) {
      if (_selectedFilterId != null) {
        if (!p.filterIds.contains(_selectedFilterId)) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty && !p.name.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();
  }
  @override
  Widget build(BuildContext context) {
    final List<MasterProduct> vendables =
    widget.availableProducts.where((p) => !p.isIngredient).toList();
    final List<MasterProduct> nonVendables =
    widget.availableProducts.where((p) => p.isIngredient).toList();
    final currentTabProducts = _tabController.index == 0 ? vendables : nonVendables;
    final Set<String> presentFilterIds = currentTabProducts
        .expand((p) => p.filterIds)
        .toSet();
    final List<ProductFilter> activeFilters = widget.availableFilters
        .where((f) => presentFilterIds.contains(f.id))
        .toList();
    activeFilters.sort((a, b) => a.name.compareTo(b.name));
    final filteredVendables = _filterProducts(vendables);
    final filteredNonVendables = _filterProducts(nonVendables);
    return AlertDialog(
      title: const Text("Sélection des Produits"),
      content: SizedBox(
        width: 700,
        height: 700,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher par nom...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                onTap: (index) {
                  setState(() {});
                },
                tabs: [
                  Tab(text: "Vendables (${filteredVendables.length})"),
                  Tab(text: "Non Vendables (${filteredNonVendables.length})"),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (activeFilters.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: const Text("Tout"),
                        selected: _selectedFilterId == null,
                        onSelected: (bool selected) {
                          setState(() {
                            _selectedFilterId = null;
                          });
                        },
                        selectedColor: Colors.black,
                        labelStyle: TextStyle(
                          color: _selectedFilterId == null ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    ...activeFilters.map((filter) {
                      final isSelected = _selectedFilterId == filter.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(filter.name),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            setState(() {
                              _selectedFilterId = selected ? filter.id : null;
                            });
                          },
                          selectedColor: Colors.black,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              side: BorderSide(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(20)
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildProductList(filteredVendables),
                  _buildProductList(filteredNonVendables),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedProducts),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          child: Text("Valider (${_selectedProducts.length})"),
        ),
      ],
    );
  }
  Widget _buildProductList(List<MasterProduct> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text("Aucun produit ne correspond aux critères.",
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (c, i) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        final isSelected = _selectedProducts.any((p) => p.productId == product.productId);
        return InkWell(
          onTap: () => _toggleProduct(product),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    image: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                        ? DecorationImage(
                      image: NetworkImage(product.photoUrl!),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: (product.photoUrl == null || product.photoUrl!.isEmpty)
                      ? Icon(
                    product.isIngredient ? Icons.kitchen : Icons.fastfood,
                    size: 20,
                    color: Colors.grey,
                  )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                Checkbox(
                  value: isSelected,
                  activeColor: Colors.black,
                  onChanged: (val) => _toggleProduct(product),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
