import 'dart:async';
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

  // -- CACHE MEMOIRE --
  List<ProductFilter> _allFilters = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  // -- ETAT RECHERCHE --
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final repository = FranchiseRepository();
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    // Abonnement unique au flux de données
    _subscription = repository.getFiltersStream(uid).listen((filters) {
      if (mounted) {
        setState(() {
          _allFilters = filters;
          _isLoading = false;
        });
      }
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  // Filtrage et Tri instantané sur la RAM
  List<ProductFilter> _getFilteredData() {
    List<ProductFilter> processed = List.from(_allFilters);

    if (_searchQuery.isNotEmpty) {
      processed = processed
          .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Tri alphabétique
    processed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return processed;
  }

  // --- LOGIQUE OPTIMISTE (INSTANTANÉE) ---

  void _openFilterDialog(ProductFilter? filter) async {
    final uid = Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    // On attend l'objet créé/modifié par le dialogue
    final result = await showDialog<ProductFilter>(
      context: context,
      builder: (_) => FilterEditorDialog(
          franchisorId: uid,
          filter: filter
      ),
    );

    if (result != null) {
      setState(() {
        // Mise à jour locale immédiate
        final index = _allFilters.indexWhere((f) => f.id == result.id);
        if (index != -1) {
          _allFilters[index] = result;
        } else {
          _allFilters.add(result);
        }
      });

      // Sauvegarde arrière-plan
      final repo = FranchiseRepository();
      try {
        await repo.saveFilter(
          franchisorId: uid,
          id: result.id,
          name: result.name,
          color: result.color,
        );
      } catch (e) {
        print("Erreur de sauvegarde: $e");
      }
    }
  }

  void _confirmDelete(ProductFilter filter) async {
    final repo = FranchiseRepository();

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
              Navigator.pop(ctx); // Ferme le dialogue

              // 1. Suppression visuelle immédiate
              setState(() {
                _allFilters.removeWhere((f) => f.id == filter.id);
              });

              // 2. Suppression base de données
              await repo.deleteFilter(filter.id);
            },
            child: const Text("Supprimer"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedFilters = _getFilteredData();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                return _buildFilterCard(context, displayedFilters[index]);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text("Nouveau Filtre", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openFilterDialog(null),
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

  Widget _buildFilterCard(BuildContext context, ProductFilter filter) {
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
              onPressed: () => _openFilterDialog(filter),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
              onPressed: () => _confirmDelete(filter),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// --- DIALOGUE D'ÉDITION (Retourne l'objet) ---
// -----------------------------------------------------------------------------

class FilterEditorDialog extends StatefulWidget {
  final String franchisorId;
  final ProductFilter? filter;

  const FilterEditorDialog({
    super.key,
    required this.franchisorId,
    this.filter
  });

  @override
  State<FilterEditorDialog> createState() => _FilterEditorDialogState();
}

class _FilterEditorDialogState extends State<FilterEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String? _selectedColorHex;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.filter?.name ?? '');
    if (widget.filter?.color != null && widget.filter!.color!.isNotEmpty) {
      _selectedColorHex = widget.filter!.color!.toUpperCase();
    } else {
      _selectedColorHex = null;
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final filterId = widget.filter?.id ?? const Uuid().v4();

    // Création de l'objet complet
    final newFilter = ProductFilter(
        id: filterId,
        name: _nameController.text.trim(),
        color: _selectedColorHex
    );

    // Retour immédiat vers la vue parente avec l'objet
    Navigator.pop(context, newFilter);
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
                          _selectedColorHex = null;
                        } else {
                          _selectedColorHex = paletteHex.toUpperCase();
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          onPressed: _submit,
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