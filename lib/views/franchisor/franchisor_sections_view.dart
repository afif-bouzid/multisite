import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';
import 'franchisor_catalogue_view.dart'; // Pour le ProductPickerDialog

class SectionsView extends StatefulWidget {
  const SectionsView({super.key});

  @override
  State<SectionsView> createState() => _SectionsViewState();
}

class _SectionsViewState extends State<SectionsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedFilterIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
        () => setState(() => _searchQuery = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return Scaffold(
      body: Column(
        children: [
          _buildSearchAndFilterBar(context, repository, uid),
          Expanded(
            child: StreamBuilder<List<ProductSection>>(
              stream: repository.getSectionsStream(uid,
                  filterIds: _selectedFilterIds.toList()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return Center(child: Text("Erreur: ${snapshot.error}"));
                if (!snapshot.hasData || snapshot.data!.isEmpty)
                  return const Center(child: Text("Aucune section créée."));
                final filteredSections = snapshot.data!
                    .where((section) => section.title
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                    .toList();
                if (filteredSections.isEmpty)
                  return Center(
                      child: Text("Aucun résultat pour '$_searchQuery'."));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: filteredSections.length,
                  itemBuilder: (context, index) {
                    final section = filteredSections[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                            backgroundColor: Colors.teal.withOpacity(0.1),
                            child: const Icon(Icons.view_stream_outlined,
                                color: Colors.teal)),
                        title: Text(section.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            "Type: ${section.type.toUpperCase()}, Produits: ${section.items.length}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.copy_outlined),
                                tooltip: "Dupliquer",
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => SectionFormView(
                                            sectionToEdit: section,
                                            isDuplicating: true)))),
                            IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: "Modifier",
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => SectionFormView(
                                            sectionToEdit: section)))),
                            IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: "Supprimer",
                                onPressed: () => _deleteSection(
                                    context, repository, section)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text("Nouvelle Section"),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (context) => const SectionFormView())),
      ),
    );
  }

  Widget _buildSearchAndFilterBar(
      BuildContext context, FranchiseRepository repository, String uid) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
              controller: _searchController,
              decoration: InputDecoration(
                  labelText: 'Rechercher une section...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear())
                      : null)),
          const SizedBox(height: 10),
          StreamBuilder<List<ProductFilter>>(
            stream: repository.getFiltersStream(uid),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Wrap(
                spacing: 8,
                children: snapshot.data!.map((filter) {
                  final isSelected = _selectedFilterIds.contains(filter.id);
                  return FilterChip(
                      label: Text(filter.name),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected)
                            _selectedFilterIds.add(filter.id);
                          else
                            _selectedFilterIds.remove(filter.id);
                        });
                      });
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _deleteSection(BuildContext context, FranchiseRepository repository,
      ProductSection section) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Confirmer"),
              content: Text("Supprimer la section '${section.title}'?"),
              actions: [
                TextButton(
                    child: const Text("Annuler"),
                    onPressed: () => Navigator.pop(ctx, false)),
                ElevatedButton(
                    child: const Text("Supprimer"),
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white))
              ],
            ));
    if (confirm == true) {
      await repository.deleteSection(section.sectionId);
    }
  }
}

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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
    _titleController.dispose();
    super.dispose();
  }

  void _reorderProducts(int oldIndex, int newIndex) => setState(() {
        if (newIndex > oldIndex) newIndex -= 1;
        _items.insert(newIndex, _items.removeAt(oldIndex));
      });

  Future<void> _saveSection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
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
    try {
      await repository.saveSection(newSection);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildFilterSelector(BuildContext context) {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Filtres de Rangement (Back-Office)",
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
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
                    onSelected: (selected) {
                      setState(() {
                        if (selected)
                          _selectedFilterIds.add(filter.id);
                        else
                          _selectedFilterIds.remove(filter.id);
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
      appBar: AppBar(
          title: Text(widget.sectionToEdit != null
              ? "Modifier la Section"
              : "Créer une Section"),
          actions: [
            IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isLoading ? null : _saveSection)
          ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                          labelText: "Titre de la section"),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(
                        labelText: "Comportement de sélection"),
                    items: const [
                      DropdownMenuItem(
                          value: 'radio', child: Text("Choix unique")),
                      DropdownMenuItem(
                          value: 'checkbox', child: Text("Choix multiple")),
                      DropdownMenuItem(
                          value: 'increment',
                          child: Text("Quantité / Incrémentation"))
                    ],
                    onChanged: (val) => setState(() {
                      _type = val!;
                      if (_type == 'radio') {
                        _min = 1;
                        _max = 1;
                      } else {
                        if (_min == 0) _min = 1;
                        if (_max == 1) _max = 5;
                      }
                    }),
                  ),
                  Row(
                    children: [
                      Expanded(
                          child: TextFormField(
                        initialValue: _min.toString(),
                        decoration:
                            const InputDecoration(labelText: "Sélection Min"),
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _min = int.tryParse(val) ?? 0,
                        readOnly: _type == 'radio',
                      )),
                      const SizedBox(width: 16),
                      Expanded(
                          child: TextFormField(
                        initialValue: _max.toString(),
                        decoration:
                            const InputDecoration(labelText: "Sélection Max"),
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _max = int.tryParse(val) ?? 1,
                        readOnly: _type == 'radio',
                      )),
                    ],
                  ),
                  const Divider(height: 40),
                  _buildFilterSelector(context),
                  const Divider(height: 40),
                  Text("Produits disponibles dans cette section:",
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    onReorder: _reorderProducts,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        key: ValueKey(item.product.id),
                        child: ListTile(
                          leading: const Icon(Icons.drag_handle),
                          title: Text(item.product.name),
                          trailing: SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue:
                                  item.supplementPrice.toStringAsFixed(2),
                              decoration: const InputDecoration(
                                  labelText: "Prix suppl. (€)"),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (value) {
                                item.supplementPrice = double.tryParse(
                                        value.replaceAll(',', '.')) ??
                                    0.0;
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_shopping_cart),
                    onPressed: () async {
                      final selectedProducts =
                          await showDialog<List<MasterProduct>>(
                              context: context,
                              builder: (context) => ProductPickerDialog(
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
                    label: const Text("Gérer les produits..."),
                  )
                ],
              ),
            ),
    );
  }
}
