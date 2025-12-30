import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_provider.dart';
import '../../models.dart';
import '../../repository.dart';

class KioskView extends StatelessWidget {
  const KioskView({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return StreamBuilder<List<KioskCategory>>(
      stream: repository.getKioskCategoriesStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(child: Text("Erreur: ${snapshot.error}"));
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const Center(child: Text("Aucune catégorie de borne créée."));

        final categories = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: CircleAvatar(child: Text("${index + 1}")),
                title: Text(category.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: "Modifier",
                        onPressed: () =>
                            showCategoryDialog(context, category: category)),
                    IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: "Supprimer",
                        onPressed: () =>
                            repository.deleteKioskCategory(category.id)),
                  ],
                ),
                children: [
                  ...category.filters.map((filter) => ListTile(
                        leading:
                            const Icon(Icons.label_important_outline, size: 16),
                        title: Text(filter.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: "Modifier",
                                onPressed: () => _showFilterDialog(
                                    context, repository, category.id,
                                    filter: filter)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: "Supprimer",
                                onPressed: () => repository.deleteKioskFilter(
                                    categoryId: category.id,
                                    filterId: filter.id)),
                          ],
                        ),
                      )),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Ajouter un filtre (sous-catégorie)"),
                      onPressed: () => _showFilterDialog(
                          context, repository, category.id,
                          nextPosition: category.filters.length),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static void showCategoryDialog(BuildContext context,
      {KioskCategory? category}) {
    final repository = FranchiseRepository();
    final nameController = TextEditingController(text: category?.name);
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(category == null
                  ? "Créer une Catégorie"
                  : "Modifier la Catégorie"),
              content: TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: "Nom (ex: Burgers)")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text("Annuler")),
                ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isNotEmpty) {
                        await repository.saveKioskCategory(
                            id: category?.id,
                            name: nameController.text,
                            position: category?.position ?? 0);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text("Sauvegarder")),
              ],
            ));
  }

  void _showFilterDialog(
      BuildContext context, FranchiseRepository repository, String categoryId,
      {KioskFilter? filter, int nextPosition = 0}) {
    final nameController = TextEditingController(text: filter?.name);
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(
                  filter == null ? "Créer un Filtre" : "Modifier le Filtre"),
              content: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: "Nom (ex: Burgers au boeuf)")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text("Annuler")),
                ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isNotEmpty) {
                        await repository.saveKioskFilter(
                            categoryId: categoryId,
                            filterId: filter?.id,
                            name: nameController.text,
                            position: filter?.position ?? nextPosition);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text("Sauvegarder")),
              ],
            ));
  }
}
