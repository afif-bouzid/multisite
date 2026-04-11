import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';
class _LocalSectionCache {
  static List<ProductSection>? _cachedSections;
  static DateTime? _lastFetch;
  static Future<List<ProductSection>> getSections(FranchiseRepository repo, String uid) async {
    if (_cachedSections != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      return _cachedSections!;
    }
    try {
      final sections = await repo.getSectionsStream(uid).first;
      _cachedSections = sections;
      _lastFetch = DateTime.now();
      return sections;
    } catch (e) {
      debugPrint("Erreur récupération sections: $e");
      return [];
    }
  }
  static void invalidate() {
    _cachedSections = null;
    _lastFetch = null;
  }
}
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
  Map<String, dynamic> _processData(
      List<SectionGroup> allGroups, List<ProductFilter> allFilters) {
    List<SectionGroup> filteredGroups = allGroups;
    if (_searchQuery.isNotEmpty) {
      filteredGroups = filteredGroups
          .where((g) =>
          g.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    if (_selectedFilterIds.isNotEmpty) {
      filteredGroups = filteredGroups
          .where((g) =>
          g.filterIds.any((id) => _selectedFilterIds.contains(id)))
          .toList();
    }
    Set<String> activeFilterIds = {};
    for (var group in allGroups) {
      activeFilterIds.addAll(group.filterIds);
    }
    List<ProductFilter> visibleFilters = allFilters
        .where((f) => activeFilterIds.contains(f.id))
        .toList();
    visibleFilters.sort((a, b) => a.name.compareTo(b.name));
    filteredGroups.sort((a, b) => a.name.compareTo(b.name));
    return {
      'groups': filteredGroups,
      'filters': visibleFilters,
    };
  }
  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<ProductFilter>>(
        stream: repository.getFiltersStream(uid),
        builder: (context, filterSnapshot) {
          return StreamBuilder<List<SectionGroup>>(
            stream: repository.getSectionGroupsStream(uid),
            builder: (context, groupSnapshot) {
              if (!filterSnapshot.hasData || !groupSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final processed = _processData(groupSnapshot.data!, filterSnapshot.data!);
              final List<SectionGroup> groupsToShow = processed['groups'];
              final List<ProductFilter> relevantFilters = processed['filters'];
              return Column(
                children: [
                  _buildHeader(relevantFilters),
                  Expanded(
                    child: groupsToShow.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: groupsToShow.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _buildGroupCard(
                          context, groupsToShow[index], repository),
                    ),
                  ),
                ],
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
        label: const Text("Nouveau Groupe",
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const SectionGroupFormView())),
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
                hintText: 'Rechercher un groupe...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchController.clear())
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "Aucun groupe trouvé",
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
  Widget _buildGroupCard(BuildContext context, SectionGroup group, FranchiseRepository repository) {
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
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => SectionGroupFormView(groupToEdit: group))),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.workspaces_outline, color: Colors.purple.shade700),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${group.sectionIds.length} section(s) incluse(s)",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.copy_rounded,
                      color: Colors.grey.shade400,
                      onTap: () => _duplicateGroup(context, repository, group),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.edit_rounded,
                      color: Colors.blue.shade400,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => SectionGroupFormView(groupToEdit: group))),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.delete_outline_rounded,
                      color: Colors.red.shade300,
                      onTap: () => _deleteGroup(context, repository, group),
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
  void _duplicateGroup(BuildContext context, FranchiseRepository repository, SectionGroup group) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Duplication de '${group.name}'..."),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _LocalSectionCache.invalidate();
    await repository.duplicateSectionGroup(group);
  }
  void _deleteGroup(BuildContext context, FranchiseRepository repository, SectionGroup group) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Supprimer ?"),
          content: Text("Voulez-vous vraiment supprimer le groupe '${group.name}' ?"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0),
                child: const Text("Supprimer"))
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
  final _sectionSearchController = TextEditingController();
  String _sectionSearchQuery = "";
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
    _sectionSearchController.addListener(() {
      setState(() {
        _sectionSearchQuery = _sectionSearchController.text;
      });
    });
    _loadAndCategorizeSections();
  }
  @override
  void dispose() {
    _nameController.dispose();
    _sectionSearchController.dispose();
    super.dispose();
  }
  Future<void> _loadAndCategorizeSections() async {
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final allSections = await _LocalSectionCache.getSections(repository, authProvider.firebaseUser!.uid);
    if (!mounted) return;
    if (widget.groupToEdit != null) {
      final groupSectionIds = widget.groupToEdit!.sectionIds;
      _selectedSections = groupSectionIds
          .where((id) => allSections.any((s) => s.sectionId == id))
          .map((id) => allSections.firstWhere((s) => s.sectionId == id))
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
          content: Text("Veuillez donner un nom et ajouter au moins une section.")));
      return;
    }
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    try {
      final orderedSectionIds = _selectedSections.map((s) => s.sectionId).toList();
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
          .showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
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
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      offset: const Offset(0, 4),
                      blurRadius: 10)
                ],
              ),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "Nom du groupe",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 20),
                  _buildFilterSelector(context),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
        Text("Filtres de Rangement",
            style: Theme.of(context).textTheme.titleSmall),
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
  Widget _buildDragDropLists() {
    final visibleAvailableSections = _availableSections.where((section) {
      if (_sectionSearchQuery.isEmpty) return true;
      return section.title.toLowerCase().contains(_sectionSearchQuery.toLowerCase());
    }).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: _buildSectionColumn(
                  "Sections Disponibles",
                  visibleAvailableSections, 
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
        return Container(
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? Colors.blue.withOpacity(0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: candidateData.isNotEmpty
                    ? Colors.blue
                    : Colors.transparent),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            children: [
              Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      if (isSource) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _sectionSearchController,
                          decoration: InputDecoration(
                            hintText: "Rechercher...",
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _sectionSearchQuery.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => _sectionSearchController.clear(),
                            )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ]
                    ],
                  )),
              const Divider(height: 1),
              Expanded(
                  child: isSource
                      ? _buildDraggableList(sections)
                      : _buildReorderableTargetList(sections)),
            ],
          ),
        );
      },
      onWillAcceptWithDetails: (details) => isSource
          ? _selectedSections.any((s) => s.id == details.data.id)
          : _availableSections.any((s) => s.id == details.data.id),
      onAcceptWithDetails: (details) => setState(() {
        final data = details.data;
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
    if (sections.isEmpty) {
      return Center(
          child: Text("Aucune section",
              style: TextStyle(color: Colors.grey.shade400)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sections.length,
      separatorBuilder: (c, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final section = sections[index];
        return Draggable<ProductSection>(
            data: section,
            feedback: _buildFeedbackTile(section),
            childWhenDragging: Opacity(
                opacity: 0.3, child: _buildSectionTile(section)),
            child: _buildSectionTile(section));
      },
    );
  }
  Widget _buildReorderableTargetList(List<ProductSection> sections) {
    if (sections.isEmpty) {
      return Center(
          child: Text("Glissez des sections ici",
              style: TextStyle(color: Colors.grey.shade400)));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Draggable<ProductSection>(
            key: ValueKey(section.id),
            data: section,
            feedback: _buildFeedbackTile(section),
            childWhenDragging: const SizedBox.shrink(),
            child:
            _buildSectionTile(section, hasHandle: true, index: index));
      },
      onReorder: (oldIndex, newIndex) => setState(() {
        if (newIndex > oldIndex) newIndex -= 1;
        _selectedSections.insert(
            newIndex, _selectedSections.removeAt(oldIndex));
      }),
    );
  }
  Widget _buildSectionTile(ProductSection section,
      {bool hasHandle = false, int? index}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(section.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text("${section.items.length} produit(s)",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(hasHandle ? Icons.drag_handle : Icons.grid_view,
              size: 16, color: Colors.grey.shade700),
        ),
        trailing: hasHandle
            ? CircleAvatar(
          radius: 10,
          backgroundColor: Colors.black,
          child: Text("${(index ?? 0) + 1}",
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        )
            : null,
      ),
    );
  }
  Widget _buildFeedbackTile(ProductSection section) => Material(
    color: Colors.transparent,
    child: Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10)
        ],
      ),
      child: ListTile(
        title: Text(section.title),
        leading: const Icon(Icons.grid_view),
      ),
    ),
  );
}
