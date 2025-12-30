import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';

class FiltersView extends StatelessWidget {
  const FiltersView({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Le Scaffold est retiré, le StreamBuilder est maintenant le widget racine.
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

  // La méthode est maintenant "static" pour être accessible de l'extérieur.
  static void showFilterDialog(BuildContext context) {
    final repository = FranchiseRepository();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Créer un filtre de rangement"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Nom du filtre"),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await repository.addFilter(nameController.text);
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
