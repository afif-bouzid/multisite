import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';

// Palette de couleurs
const List<String> kDefaultPalette = [
  '#F44336', '#E91E63', '#9C27B0', '#673AB7', '#2196F3',
  '#03A9F4', '#00BCD4', '#009688', '#4CAF50', '#8BC34A',
  '#CDDC39', '#FFC107', '#FF9800', '#FF5722', '#795548',
  '#9E9E9E', '#607D8B', '#000000'
];

class FiltersView extends StatefulWidget {
  const FiltersView({super.key});

  @override
  State<FiltersView> createState() => _FiltersViewState();
}

class _FiltersViewState extends State<FiltersView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProductFilter> _processFilters(List<ProductFilter> filters) {
    List<ProductFilter> processed = List.from(filters);
    if (_searchQuery.isNotEmpty) {
      processed = processed
          .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    processed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return processed;
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    // On récupère l'ID de l'utilisateur connecté
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<ProductFilter>>(
        stream: repository.getFiltersStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Erreur: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          }

          final allFilters = snapshot.data ?? [];
          final displayedFilters = _processFilters(allFilters);

          return Column(
            children: [
              _buildHeader(),
              Expanded(
                child: displayedFilters.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: displayedFilters.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _buildFilterCard(context, displayedFilters[index], repository);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text("Nouveau Filtre", style: TextStyle(fontWeight: FontWeight.bold)),
        // IMPORTANT : On passe le UID à la modale
        onPressed: () => showDialog(
          context: context,
          builder: (_) => FilterEditorDialog(franchisorId: uid),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), offset: const Offset(0, 4), blurRadius: 10)
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Rechercher un filtre...',
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.label_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? "Aucun filtre créé" : "Aucun résultat",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard(BuildContext context, ProductFilter filter, FranchiseRepository repo) {
    // On récupère le UID ici aussi au cas où pour la suppression (si besoin de vérifier les droits)
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;
    final Color chipColor = colorFromHex(filter.color);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), offset: const Offset(0, 2), blurRadius: 8)
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: chipColor.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: chipColor.withOpacity(0.3), width: 1),
          ),
          child: Icon(Icons.label, color: chipColor, size: 22),
        ),
        title: Text(
          filter.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
        ),
        subtitle: const Text("Filtre Back-Office", style: TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.black54),
              // IMPORTANT : On passe le UID et le filtre à éditer
              onPressed: () => showDialog(
                context: context,
                builder: (_) => FilterEditorDialog(franchisorId: uid, filter: filter),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
              onPressed: () => _confirmDelete(context, repo, filter),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, FranchiseRepository repo, ProductFilter filter) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Le filtre '${filter.name}' sera supprimé définitivement."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await repo.deleteFilter(filter.id);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("Supprimer"),
          )
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// --- DIALOGUE D'ÉDITION ---
// -----------------------------------------------------------------------------

class FilterEditorDialog extends StatefulWidget {
  final String franchisorId; // <--- On reçoit l'ID ici
  final ProductFilter? filter;

  const FilterEditorDialog({
    super.key,
    required this.franchisorId, // <--- Requis
    this.filter
  });

  @override
  State<FilterEditorDialog> createState() => _FilterEditorDialogState();
}

class _FilterEditorDialogState extends State<FilterEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String? _selectedColorHex;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.filter?.name ?? '');

    // Initialisation couleur
    if (widget.filter?.color != null && widget.filter!.color!.isNotEmpty) {
      _selectedColorHex = widget.filter!.color!.toUpperCase();
    } else {
      _selectedColorHex = null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isUploading = true);

    try {
      final repository = FranchiseRepository();
      final filterId = widget.filter?.id ?? const Uuid().v4();

      // On sauvegarde avec le franchisorId passé en paramètre
      await repository.saveFilter(
        franchisorId: widget.franchisorId, // <--- ENVOI DE L'ID
        id: filterId,
        name: _nameController.text.trim(),
        color: _selectedColorHex, // Peut être null
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.filter == null ? "Nouveau Filtre" : "Modifier Filtre", style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 350,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Nom du filtre",
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => v!.isEmpty ? "Requis" : null,
              ),
              const SizedBox(height: 24),
              const Text("Couleur (Optionnel) :", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: kDefaultPalette.map((paletteHex) {
                  final color = colorFromHex(paletteHex);
                  final bool isSelected = _selectedColorHex == paletteHex.toUpperCase();

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedColorHex = null; // Désélectionner
                        } else {
                          _selectedColorHex = paletteHex.toUpperCase(); // Sélectionner
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black, width: 2.5)
                              : Border.all(color: Colors.grey.shade300, width: 1),
                          boxShadow: [
                            if(isSelected) BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)
                          ]
                      ),
                      child: isSelected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                    ),
                  );
                }).toList(),
              ),
              if (_isUploading) const Padding(padding: EdgeInsets.only(top: 24), child: LinearProgressIndicator(color: Colors.black))
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          onPressed: _isUploading ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
          child: const Text("Enregistrer"),
        )
      ],
    );
  }
}

Color colorFromHex(String? hexString) {
  if (hexString == null || hexString.isEmpty) return Colors.grey;
  try {
    String hex = hexString.toUpperCase().replaceAll("#", "");
    if (hex.startsWith("0X")) hex = hex.substring(2);
    if (hex.length == 6) hex = "FF$hex";
    return Color(int.parse(hex, radix: 16));
  } catch (_) {
    return Colors.grey;
  }
}