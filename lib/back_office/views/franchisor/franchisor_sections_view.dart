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
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<ProductSection>>(
        stream: repository.getSectionsStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sections = snapshot.data ?? [];
          if (sections.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt_rounded, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("Aucune section créée", style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: sections.length,
            separatorBuilder: (c, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final section = sections[index];
              return Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          offset: const Offset(0, 2),
                          blurRadius: 8
                      )
                    ]
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => SectionFormView(sectionToEdit: section))),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.list_rounded, color: Colors.green.shade700),
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
                                      color: Colors.black87),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${section.items.length} produit(s) • Min: ${section.selectionMin} / Max: ${section.selectionMax}",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              _buildActionButton(
                                icon: Icons.edit_rounded,
                                color: Colors.blue.shade400,
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => SectionFormView(sectionToEdit: section))),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: Icons.delete_outline_rounded,
                                color: Colors.red.shade300,
                                onTap: () => _deleteSection(context, repository, section),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add),
        label: const Text("Nouvelle Section", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (context) => const SectionFormView())),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required VoidCallback onTap}) {
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

  void _deleteSection(BuildContext context, FranchiseRepository repository, ProductSection section) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Supprimer ?"),
          content: Text("Voulez-vous vraiment supprimer la section '${section.title}' ?"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0),
                child: const Text("Supprimer"))
          ],
        ));

    if (confirm == true) {
      await repository.deleteSection(section.sectionId);
    }
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
  int _min = 0;
  int _max = 1;
  String _type = 'checkbox';
  List<SectionItem> _items = [];
  bool _isLoading = false;
  final Set<String> _selectedFilterIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.sectionToEdit != null) {
      final s = widget.sectionToEdit!;
      _titleController.text = s.title;
      _min = s.selectionMin;
      _max = s.selectionMax;
      _type = s.type;
      _items = List.from(s.items);
      _selectedFilterIds.addAll(s.filterIds);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final repository = FranchiseRepository();
    final sectionId = widget.sectionToEdit?.sectionId ?? const Uuid().v4();

    final section = ProductSection(
      id: widget.sectionToEdit?.id ?? '',
      sectionId: sectionId,
      title: _titleController.text,
      selectionMin: _min,
      selectionMax: _max,
      type: _type,
      items: _items,
      filterIds: _selectedFilterIds.toList(),
    );

    await repository.saveSection(section);
    if (mounted) Navigator.pop(context);
  }

  Widget _buildFilterSelector(BuildContext context) {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Filtres de Rangement", style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        StreamBuilder<List<ProductFilter>>(
          stream: repository.getFiltersStream(authProvider.firebaseUser!.uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            return Wrap(
              spacing: 8,
              children: snapshot.data!.map((filter) {
                final isSelected = _selectedFilterIds.contains(filter.id);
                return FilterChip(
                    label: Text(filter.name),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: Colors.black,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
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
                    });
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.sectionToEdit == null ? "Créer une Section" : "Modifier la Section"),
        actions: [
          IconButton(
            icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.check),
            onPressed: _isLoading ? null : _save,
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                  ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: "Titre de la section (ex: Sauces, Cuisson)",
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? "Requis" : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _type,
                          decoration: const InputDecoration(labelText: "Type de choix", border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'checkbox', child: Text("Choix Multiple (Checkbox)")),
                            DropdownMenuItem(value: 'radio', child: Text("Choix Unique (Radio)")),
                            DropdownMenuItem(value: 'quantity', child: Text("Quantité (Compteur)")),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _type = val!;
                              if (_type == 'radio') {
                                _min = 1;
                                _max = 1;
                              }
                            });
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
                            key: ValueKey('min_$_type'),
                            initialValue: _min.toString(),
                            decoration: const InputDecoration(labelText: "Min", border: OutlineInputBorder()),
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
                            decoration: const InputDecoration(labelText: "Max", border: OutlineInputBorder()),
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
                    // --- UTILISATION DE ProductPickerDialog (Maintenant défini plus bas) ---
                    final selectedProducts = await showDialog<List<MasterProduct>>(
                        context: context,
                        builder: (context) => ProductPickerDialog(
                          ingredientsOnly: false,
                          initialSelection: _items.map((e) => e.product).toList(),
                          products: [], // Le dialogue chargera les produits si la liste est vide
                        ));

                    if (selectedProducts != null) {
                      setState(() {
                        final updatedItems = <SectionItem>[];
                        for (var p in selectedProducts) {
                          final existing = _items.where((item) => item.product.id == p.id);
                          updatedItems.add(existing.isNotEmpty
                              ? existing.first
                              : SectionItem(product: p));
                        }
                        _items = updatedItems;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("Aucun produit ajouté."),
              ))
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
                    key: ValueKey(item.product.id),
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300)
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle, color: Colors.grey),
                      title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Prix Supplément: ${item.supplementPrice.toStringAsFixed(2)} €"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.euro, color: Colors.green),
                            onPressed: () async {
                              final priceStr = await _showPriceDialog(context, item.supplementPrice);
                              if (priceStr != null) {
                                setState(() {
                                  // Grâce à la modification dans models.dart, on peut setter supplementPrice
                                  item.supplementPrice = double.tryParse(priceStr) ?? 0.0;
                                });
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _items.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showPriceDialog(BuildContext context, double currentPrice) {
    final controller = TextEditingController(text: currentPrice.toString());
    return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Prix du supplément"),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: "€"),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Valider")),
          ],
        ));
  }
}

// --- AJOUT DE LA CLASSE ProductPickerDialog ICI ---
class ProductPickerDialog extends StatefulWidget {
  final bool ingredientsOnly;
  final List<MasterProduct> initialSelection;
  final List<MasterProduct> products; // Si vide, on charge depuis Firebase

  const ProductPickerDialog({
    super.key,
    this.ingredientsOnly = false,
    required this.initialSelection,
    required this.products,
  });

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  List<MasterProduct> _availableProducts = [];
  List<MasterProduct> _selectedProducts = [];
  List<MasterProduct> _filteredProducts = [];
  String _searchQuery = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedProducts = List.from(widget.initialSelection);
    if (widget.products.isEmpty) {
      _loadProducts();
    } else {
      _availableProducts = widget.products;
      _filteredProducts = widget.products;
      _isLoading = false;
    }
  }

  Future<void> _loadProducts() async {
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    final repo = FranchiseRepository();
    // On charge tous les produits pour simplifier la sélection
    final all = await repo.getMasterProductsStream(uid).first;
    if (mounted) {
      setState(() {
        _availableProducts = widget.ingredientsOnly
            ? all.where((p) => p.isIngredient).toList()
            : all.where((p) => !p.isIngredient).toList(); // Par défaut on affiche les vendables

        // Tri alphabétique
        _availableProducts.sort((a, b) => a.name.compareTo(b.name));
        _filteredProducts = _availableProducts;
        _isLoading = false;
      });
    }
  }

  void _filter(String query) {
    setState(() {
      _searchQuery = query;
      _filteredProducts = _availableProducts
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.ingredientsOnly ? "Sélectionner Ingrédients" : "Sélectionner Produits"),
      content: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: "Rechercher...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filter,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final p = _filteredProducts[index];
                  final isSelected = _selectedProducts.any((x) => x.id == p.id);
                  return CheckboxListTile(
                    title: Text(p.name),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedProducts.add(p);
                        } else {
                          _selectedProducts.removeWhere((x) => x.id == p.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _selectedProducts),
            child: const Text("Valider")),
      ],
    );
  }
}