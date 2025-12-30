import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/repository/repository.dart';

class TeamManagementView extends StatefulWidget {
  const TeamManagementView({super.key});

  @override
  State<TeamManagementView> createState() => _TeamManagementViewState();
}

class _TeamManagementViewState extends State<TeamManagementView> {
  final FranchiseRepository _repository = FranchiseRepository();

  void _showAddEmployeeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddEmployeeDialog(repository: _repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final franchisee = authProvider.franchiseUser;

    if (franchisee == null || !franchisee.isFranchisee) {
      return const Scaffold(
          body: Center(child: Text("Accès réservé au Responsable.")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Mes Employés")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('storeId', isEqualTo: franchisee.uid)
            .where('role', isEqualTo: 'employee')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                  "Aucun employé créé.\nAppuyez sur + pour ajouter votre personnel.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            );
          }

          final employees = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final data = employees[index].data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(data['companyName'] ?? 'Employé'),
                  subtitle: Text(data['email'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Supprimer ?"),
                          content: const Text("Cette action est irréversible."),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Annuler")),
                            ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white),
                                child: const Text("Supprimer")),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(employees[index].id)
                            .delete();
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEmployeeDialog,
        icon: const Icon(Icons.add),
        label: const Text("Ajouter un employé"),
      ),
    );
  }
}

class _AddEmployeeDialog extends StatefulWidget {
  final FranchiseRepository repository;

  const _AddEmployeeDialog({required this.repository});

  @override
  State<_AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<_AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);

    final error = await widget.repository.createEmployee(
      managerId: auth.franchiseUser!.uid,
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passController.text.trim(),
    );

    if (mounted) {
      setState(() => _loading = false);
      if (error == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Employé créé !"), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Nouvel Employé"),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Prénom / Nom"),
              validator: (v) => v!.isEmpty ? "Requis" : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailController,
              decoration:
                  const InputDecoration(labelText: "Email de connexion"),
              validator: (v) => v!.contains("@") ? null : "Email invalide",
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _passController,
              decoration: const InputDecoration(labelText: "Mot de passe"),
              obscureText: true,
              validator: (v) => v!.length < 6 ? "6 car. min" : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler")),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const CircularProgressIndicator()
              : const Text("Créer"),
        ),
      ],
    );
  }
}
