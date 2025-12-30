import 'package:flutter/material.dart';
import 'package:ouiborne/back_office/views/franchisor/search_and_filter_bar.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';

class SectionGroupsView extends StatefulWidget {
  const SectionGroupsView({super.key});

  @override
  State<SectionGroupsView> createState() => _SectionGroupsViewState();
}

class _SectionGroupsViewState extends State<SectionGroupsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedFilterIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
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
    return Column(
      children: [
        SearchAndFilterBar(
          searchController: _searchController,
          searchQuery: _searchQuery,
          searchLabel: 'Rechercher un groupe...',
          franchisorId: uid,
          selectedFilterIds: _selectedFilterIds,
          onFilterSelected: (filterId) {
            setState(() {
              if (_selectedFilterIds.contains(filterId)) {
                _selectedFilterIds.remove(filterId);
              } else {
                _selectedFilterIds.add(filterId);
              }
            });
          },
        ),
        Expanded(
          child: StreamBuilder<List<SectionGroup>>(
            stream: repository.getSectionGroupsStream(uid,
                filterIds: _selectedFilterIds.toList()),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return Center(child: Text("Erreur: ${snapshot.error}"));
              if (!snapshot.hasData || snapshot.data!.isEmpty)
                return const Center(child: Text("Aucun groupe créé."));
              final filteredGroups = snapshot.data!
                  .where((group) => group.name
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()))
                  .toList();
              if (filteredGroups.isEmpty)
                return Center(
                    child: Text("Aucun résultat pour '$_searchQuery'."));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                itemCount: filteredGroups.length,
                itemBuilder: (context, index) {
                  final group = filteredGroups[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: Colors.purple.withOpacity(0.1),
                          child: const Icon(Icons.collections_bookmark_outlined,
                              color: Colors.purple)),
                      title: Text(group.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${group.sectionIds.length} section(s)"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.copy_outlined),
                              tooltip: "Dupliquer",
                              onPressed: () =>
                                  _duplicateGroup(context, repository, group)),
                          IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: "Modifier",
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          SectionGroupFormView(
                                              groupToEdit: group)))),
                          IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: "Supprimer",
                              onPressed: () =>
                                  _deleteGroup(context, repository, group)),
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
    );
  }

  void _duplicateGroup(BuildContext context, FranchiseRepository repository,
      SectionGroup group) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Duplication de '${group.name}' en cours..."),
        backgroundColor: Colors.blue,
      ),
    );
    await repository.duplicateSectionGroup(group);
  }

  void _deleteGroup(BuildContext context, FranchiseRepository repository,
      SectionGroup group) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Confirmer"),
              content: Text("Supprimer le groupe '${group.name}'?"),
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
      await repository.deleteSectionGroup(group.id);
    }
  }
}

class SectionGroupFormView extends StatefulWidget {
  final SectionGroup? groupToEdit;

  const SectionGroupFormView({super.key, this.groupToEdit});

  @override
  State<SectionGroupFormView> createState() => _SectionGroupFormViewState();
}

class _SectionGroupFormViewState extends State<SectionGroupFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  List<ProductSection> _availableSections = [];
  List<ProductSection> _selectedSections = [];
  List<String> _selectedFilterIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.groupToEdit != null) {
      _nameController.text = widget.groupToEdit!.name;
      _selectedFilterIds = List.from(widget.groupToEdit!.filterIds);
    }
    _loadAndCategorizeSections();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadAndCategorizeSections() async {
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final allSections = await repository
        .getSectionsStream(authProvider.firebaseUser!.uid)
        .first;
    if (!mounted) return;
    if (widget.groupToEdit != null) {
      final groupSectionIds = widget.groupToEdit!.sectionIds;
      _selectedSections = groupSectionIds
          .map((id) => allSections.firstWhere((s) => s.sectionId == id,
              orElse: () => ProductSection(id: 'not-found', sectionId: '')))
          .where((s) => s.id != 'not-found')
          .toList();
      _availableSections = allSections
          .where((s) => !groupSectionIds.contains(s.sectionId))
          .toList();
    } else {
      _availableSections = allSections;
      _selectedSections = [];
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveGroup() async {
    if (!_formKey.currentState!.validate() || _selectedSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Veuillez donner un nom et ajouter au moins une section.")));
      return;
    }
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    try {
      final orderedSectionIds =
          _selectedSections.map((s) => s.sectionId).toList();
      await repository.saveSectionGroup(
          groupId: widget.groupToEdit?.id,
          name: _nameController.text,
          sectionIds: orderedSectionIds,
          filterIds: _selectedFilterIds);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erreur de sauvegarde: $e")));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.groupToEdit == null
              ? "Créer un Groupe"
              : "Modifier le Groupe"),
          actions: [
            IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isLoading ? null : _saveGroup)
          ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                                labelText: "Nom du groupe"),
                            validator: (v) => v!.isEmpty ? "Requis" : null),
                        const SizedBox(height: 20),
                        _buildFilterSelector(context),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildDragDropLists()),
                ],
              ),
            ),
    );
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

  Widget _buildDragDropLists() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: _buildSectionColumn(
                  "Sections Disponibles", _availableSections,
                  isSource: true)),
          const SizedBox(width: 16),
          Expanded(
              child: _buildSectionColumn(
                  "Sections du Groupe (ordonnées)", _selectedSections,
                  isSource: false)),
        ],
      ),
    );
  }

  Widget _buildSectionColumn(String title, List<ProductSection> sections,
      {required bool isSource}) {
    return DragTarget<ProductSection>(
      builder: (context, candidateData, rejectedData) {
        return Card(
          elevation: candidateData.isNotEmpty ? 4 : 1,
          color: candidateData.isNotEmpty
              ? Colors.deepOrange.withOpacity(0.05)
              : null,
          child: Column(
            children: [
              Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium)),
              const Divider(height: 1),
              Expanded(
                  child: isSource
                      ? _buildDraggableList(sections)
                      : _buildReorderableTargetList(sections)),
            ],
          ),
        );
      },
      onWillAccept: (data) => isSource
          ? _selectedSections.any((s) => s.id == data?.id)
          : _availableSections.any((s) => s.id == data?.id),
      onAccept: (data) => setState(() {
        if (isSource) {
          _availableSections.add(data);
          _selectedSections.removeWhere((s) => s.id == data.id);
        } else {
          _selectedSections.add(data);
          _availableSections.removeWhere((s) => s.id == data.id);
        }
      }),
    );
  }

  Widget _buildDraggableList(List<ProductSection> sections) {
    if (sections.isEmpty)
      return const Center(
          child: Padding(padding: EdgeInsets.all(8.0), child: Text("Aucune.")));
    return ListView.builder(
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Draggable<ProductSection>(
            data: section,
            feedback: _buildFeedbackTile(section),
            childWhenDragging: const SizedBox.shrink(),
            child: _buildSectionTile(section));
      },
    );
  }

  Widget _buildReorderableTargetList(List<ProductSection> sections) {
    if (sections.isEmpty)
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Glissez des sections ici.")));
    return ReorderableListView.builder(
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Draggable<ProductSection>(
            key: ValueKey(section.id),
            data: section,
            feedback: _buildFeedbackTile(section),
            childWhenDragging: const SizedBox.shrink(),
            child: _buildSectionTile(section, hasHandle: true));
      },
      onReorder: (oldIndex, newIndex) => setState(() {
        if (newIndex > oldIndex) newIndex -= 1;
        _selectedSections.insert(
            newIndex, _selectedSections.removeAt(oldIndex));
      }),
    );
  }

  Widget _buildSectionTile(ProductSection section, {bool hasHandle = false}) =>
      Material(
          color: Colors.transparent,
          child: ListTile(
              title: Text(section.title),
              subtitle: Text("${section.items.length} produit(s)"),
              leading:
                  Icon(hasHandle ? Icons.drag_handle : Icons.label_outline)));

  Widget _buildFeedbackTile(ProductSection section) => Card(
      elevation: 4,
      child: SizedBox(width: 250, child: _buildSectionTile(section)));
}
