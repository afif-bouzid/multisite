import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '../../../core/repository/repository.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

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

  void _showAddAssociateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _AddAssociateDialog(),
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
      appBar: AppBar(
        title: const Text("Mes Employés"),
        actions: [
          TextButton.icon(
            onPressed: _showAddAssociateDialog,
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text("Inviter Associé"),
            style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                textStyle: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('storeId', isEqualTo: franchisee.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                  "Aucun membre dans l'équipe.\nAppuyez sur + pour ajouter du personnel.",
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
              final String role = data['role'] ?? 'employee';
              final bool isAssociate = role == 'associate';

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isAssociate ? Colors.blue : Colors.orange,
                    child: Icon(
                      isAssociate ? Icons.remove_red_eye : Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(data['companyName'] ?? data['name'] ?? 'Membre'),
                  subtitle: Text(data['email'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isAssociate ? Colors.blue : Colors.orange)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isAssociate ? "ASSOCIÉ" : "CAISSIER",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isAssociate ? Colors.blue : Colors.orange,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Supprimer ?"),
                              content:
                              const Text("Cette action est irréversible."),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text("Annuler")),
                                ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
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
                    ],
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

// ============================================================================
// DIALOGUE EMPLOYÉ
// ============================================================================
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
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _functions
          .httpsCallable('createAssociateWithEmailInvite')
          .call({
        'email': _emailController.text.trim(),
        'name': _nameController.text.trim(),
        'role': 'employee', // ✅ FIX
      });

      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailController.text.trim());

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Employé créé et invitation envoyée !"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur : ${e.toString()}"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
            const Text(
              "L'employé recevra un email pour définir son mot de passe.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Prénom / Nom"),
              validator: (v) => v!.isEmpty ? "Requis" : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email de connexion"),
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
              v!.contains("@") ? null : "Email invalide",
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
              ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Créer"),
        ),
      ],
    );
  }
}

// ============================================================================
// DIALOGUE ASSOCIÉ
// ============================================================================
class _AddAssociateDialog extends StatefulWidget {
  const _AddAssociateDialog();

  @override
  State<_AddAssociateDialog> createState() => _AddAssociateDialogState();
}

class _AddAssociateDialogState extends State<_AddAssociateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _functions
          .httpsCallable('createAssociateWithEmailInvite')
          .call({
        'email': _emailController.text.trim(),
        'name': _nameController.text.trim(),
        'role': 'associate', // ✅ FIX
      });

      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailController.text.trim());

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Invitation envoyée par email !"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erreur : ${e.toString()}"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Inviter un Associé"),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "L'associé recevra un email pour créer son mot de passe. Il pourra consulter les chiffres via le Web, mais ne pourra pas encaisser.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration:
              const InputDecoration(labelText: "Nom de l'associé"),
              validator: (v) => v!.isEmpty ? "Requis" : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
              v!.contains("@") ? null : "Email invalide",
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
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue, foregroundColor: Colors.white),
          child: _loading
              ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Text("Envoyer l'invitation"),
        ),
      ],
    );
  }
}