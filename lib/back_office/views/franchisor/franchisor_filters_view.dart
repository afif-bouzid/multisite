import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/constants.dart';
import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';

class FiltersView extends StatelessWidget {
  const FiltersView({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return StreamBuilder<List<ProductFilter>>(
      stream: repository.getFiltersStream(authProvider.firebaseUser!.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final filters = snapshot.data ?? [];
        if (filters.isEmpty) {
          return const Center(child: Text("Aucun filtre de rangement créé."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filters.length,
          itemBuilder: (context, index) {
            final filter = filters[index];
            return Card(
              child: ListTile(
                title: Text(filter.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async =>
                      await repository.deleteFilter(filter.id),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void showFilterDialog(BuildContext context) {
    final repository = FranchiseRepository();
    final nameController = TextEditingController();
    String? selectedColorHex;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Créer un filtre de rangement"),
        content: _FilterDialogContent(
          nameController: nameController,
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
                await repository.addFilter(
                    nameController.text, selectedColorHex);
                nameController.clear();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            child: const Text("Créer"),
          ),
        ],
      ),
    );
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
          children: kColorPalette.map((hexColor) {
            final color = colorFromHex(hexColor);
            final isSelected = _selectedColor == hexColor;
            return InkWell(
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
                    color:
                        isSelected ? Colors.blueAccent : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                ),
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
