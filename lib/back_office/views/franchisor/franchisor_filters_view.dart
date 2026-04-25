import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
import '../../../core/repository/repository.dart';

const List<String> _kLocalPalette = [
  '#F44336',
  '#E91E63',
  '#9C27B0',
  '#673AB7',
  '#2196F3',
  '#03A9F4',
  '#00BCD4',
  '#009688',
  '#4CAF50',
  '#8BC34A',
  '#CDDC39',
  '#FFC107',
  '#FF9800',
  '#FF5722',
  '#795548',
  '#9E9E9E',
  '#607D8B',
  '#000000'
];

class FiltersView extends StatelessWidget {
  const FiltersView({super.key});
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
      body: StreamBuilder<List<ProductFilter>>(
        stream: repository.getFiltersStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final filters = snapshot.data ?? [];
          filters.sort((a, b) => a.name.compareTo(b.name));
          if (filters.isEmpty) {
            return const Center(child: Text("Aucun filtre de rangement créé."));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filters.length,
            separatorBuilder: (c, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final filter = filters[index];
              final color = _getColorFromHex(filter.color);
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
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Icon(Icons.label, color: color, size: 20),
                  ),
                  title: Text(filter.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.black54),
                        onPressed: () =>
                            showFilterDialog(context, filter: filter),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () =>
                            _confirmDelete(context, repository, filter),
                      ),
                    ],
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
        onPressed: () => showFilterDialog(context),
        icon: const Icon(Icons.add),
        label: const Text("Nouveau Filtre"),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, FranchiseRepository repo, ProductFilter filter) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Voulez-vous supprimer le filtre '${filter.name}' ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await repo.deleteFilter(filter.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Supprimer"),
          )
        ],
      ),
    );
  }

  static void showFilterDialog(BuildContext context, {ProductFilter? filter}) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.firebaseUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur: Vous devez être connecté.")),
      );
      return;
    }
    final repository = FranchiseRepository();
    final nameController = TextEditingController(text: filter?.name ?? '');
    String? selectedColorHex = filter?.color;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(filter == null ? "Créer un filtre" : "Modifier le filtre"),
        content: _FilterDialogContent(
          nameController: nameController,
          initialColor: selectedColorHex,
          onColorSelected: (color) {
            selectedColorHex = color;
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await repository.saveFilter(
                  franchisorId: user.uid,
                  id: filter?.id ?? const Uuid().v4(),
                  name: nameController.text.trim(),
                  color: selectedColorHex,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  static Color _getColorFromHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.grey;
    try {
      String hex = hexString.replaceAll("#", "");
      if (hex.length == 6) hex = "FF$hex";
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }
}

class _FilterDialogContent extends StatefulWidget {
  final TextEditingController nameController;
  final Function(String?) onColorSelected;
  final String? initialColor;
  const _FilterDialogContent({
    required this.nameController,
    required this.onColorSelected,
    this.initialColor,
  });
  @override
  State<_FilterDialogContent> createState() => _FilterDialogContentState();
}

class _FilterDialogContentState extends State<_FilterDialogContent> {
  String? _selectedColor;
  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.nameController,
          decoration: const InputDecoration(labelText: "Nom du filtre"),
          autofocus: true,
        ),
        const SizedBox(height: 24),
        Text("Couleur", style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kLocalPalette.map((hexColor) {
            final color = FiltersView._getColorFromHex(hexColor);
            final isSelected = _selectedColor == hexColor;
            return InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () {
                setState(() {
                  _selectedColor = isSelected ? null : hexColor;
                });
                widget.onColorSelected(_selectedColor);
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.grey.shade300,
                      width: isSelected ? 2.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: color.withOpacity(0.4), blurRadius: 6)
                          ]
                        : null),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
