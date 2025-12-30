import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';

class FranchiseesView extends StatelessWidget {
  const FranchiseesView({super.key});

  void _deleteFranchisee(BuildContext context, FranchiseRepository repository,
      FranchiseUser franchisee) async {
    final emailConfirmationController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Suppression Définitive"),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    "Vous êtes sur le point de supprimer définitivement le franchisé '${franchisee.companyName}' (${franchisee.email})."),
                const SizedBox(height: 10),
                const Text("Cette action est IRREVERSIBLE et supprimera :",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text(
                    "- Son compte de connexion\n- Toutes ses données (sessions, transactions)\n- Toute sa configuration (prix, etc.)"),
                const SizedBox(height: 20),
                TextFormField(
                  controller: emailConfirmationController,
                  decoration: InputDecoration(
                      labelText: "Tapez '${franchisee.email}' pour confirmer"),
                  validator: (value) => (value != franchisee.email)
                      ? "L'email ne correspond pas."
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text("Confirmer la Suppression"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Dialog(
              child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Suppression en cours...")
                  ]))));

      final error = await repository.deleteFranchiseeAccount(franchisee.uid);

      if (!context.mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error == null
            ? "Franchisé supprimé avec succès."
            : "Erreur: $error"),
        backgroundColor: error == null ? Colors.green : Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();
    final uid =
        Provider.of<AuthProvider>(context, listen: false).firebaseUser!.uid;

    return StreamBuilder<List<FranchiseUser>>(
      stream: repository.getFranchiseesStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Erreur: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("Aucun franchisé pour le moment."));
        }

        final franchisees = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: franchisees.length,
          itemBuilder: (context, index) {
            final franchisee = franchisees[index];
            return Card(
              elevation: 2.0,
              margin: const EdgeInsets.only(bottom: 16.0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Icon(Icons.storefront,
                        color: Theme.of(context).primaryColor),
                  ),
                  title: Text(franchisee.companyName ?? 'Nom non défini',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(franchisee.email),
                      Text(franchisee.contactName ?? '',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => FranchiseeFormView(
                                    franchiseeToEdit: franchisee))),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_outlined,
                            color: Colors.red),
                        onPressed: () =>
                            _deleteFranchisee(context, repository, franchisee),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class FranchiseeFormView extends StatefulWidget {
  final FranchiseUser? franchiseeToEdit;

  const FranchiseeFormView({super.key, this.franchiseeToEdit});

  @override
  State<FranchiseeFormView> createState() => _FranchiseeFormViewState();
}

class _FranchiseeFormViewState extends State<FranchiseeFormView> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  late bool _isEditing;

  bool _moduleKioskEnabled = true;
  bool _moduleClickAndCollectEnabled = false;
  bool _moduleDealsEnabled = true;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.franchiseeToEdit != null;
    if (_isEditing) {
      final franchisee = widget.franchiseeToEdit!;
      _companyNameController.text = franchisee.companyName ?? '';
      _contactNameController.text = franchisee.contactName ?? '';
      _phoneController.text = franchisee.phone ?? '';
      _addressController.text = franchisee.address ?? '';
      _emailController.text = franchisee.email;
      _moduleKioskEnabled = franchisee.enabledModules['kiosk'] ?? true;
      _moduleClickAndCollectEnabled =
          franchisee.enabledModules['click_and_collect'] ?? false;
      _moduleDealsEnabled = franchisee.enabledModules['deals'] ?? true;
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveFranchisee() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final repository = FranchiseRepository();
    final String? result;
    final Map<String, bool> enabledModules = {
      'kiosk': _moduleKioskEnabled,
      'click_and_collect': _moduleClickAndCollectEnabled,
      'deals': _moduleDealsEnabled,
    };

    if (_isEditing) {
      result = await repository.updateFranchiseeDetails(
        uid: widget.franchiseeToEdit!.uid,
        companyName: _companyNameController.text.trim(),
        contactName: _contactNameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        enabledModules: enabledModules,
      );
    } else {
      result = await repository.createFranchisee(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        companyName: _companyNameController.text.trim(),
        contactName: _contactNameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        enabledModules: enabledModules,
      );
    }

    if (!mounted) return;

    if (result == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Franchisé ${_isEditing ? 'mis à jour' : 'créé'} avec succès !"),
        backgroundColor: Colors.green,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur: $result"), backgroundColor: Colors.red));
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isEditing ? "Modifier un Franchisé" : "Créer un Franchisé"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text("Sauvegarder"),
              onPressed: _isLoading ? null : _saveFranchisee,
            ),
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Informations sur l'entreprise",
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 24),
                    TextFormField(
                        controller: _companyNameController,
                        decoration: const InputDecoration(
                            labelText: "Nom de la société",
                            prefixIcon: Icon(Icons.business)),
                        validator: (v) => v!.isEmpty ? "Requis" : null),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _contactNameController,
                        decoration: const InputDecoration(
                            labelText: "Nom du contact principal",
                            prefixIcon: Icon(Icons.person)),
                        validator: (v) => v!.isEmpty ? "Requis" : null),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                            labelText: "Numéro de téléphone",
                            prefixIcon: Icon(Icons.phone)),
                        validator: (v) => v!.isEmpty ? "Requis" : null),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                            labelText: "Adresse postale",
                            prefixIcon: Icon(Icons.location_on_outlined)),
                        validator: (v) => v!.isEmpty ? "Requis" : null),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Identifiants de Connexion",
                        style: Theme.of(context).textTheme.titleLarge),
                    if (_isEditing)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: Text(
                            "L'email et le mot de passe ne peuvent pas être modifiés depuis cette interface.",
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey.shade700)),
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      readOnly: _isEditing,
                      decoration: InputDecoration(
                          labelText: "Email de connexion",
                          prefixIcon: const Icon(Icons.email_outlined),
                          filled: _isEditing,
                          fillColor: _isEditing ? Colors.grey.shade200 : null),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          (v == null || v.isEmpty || !v.contains('@'))
                              ? "Email invalide"
                              : null,
                    ),
                    if (!_isEditing) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                            labelText: "Mot de passe (8 caractères min.)",
                            prefixIcon: Icon(Icons.lock_outline)),
                        obscureText: true,
                        validator: (v) => (v == null || v.length < 8)
                            ? "8 caractères minimum requis"
                            : null,
                      ),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Modules Activés",
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text("Module Borne"),
                      subtitle: const Text(
                          "Donne accès à la configuration de la borne."),
                      value: _moduleKioskEnabled,
                      onChanged: (value) =>
                          setState(() => _moduleKioskEnabled = value),
                    ),
                    SwitchListTile(
                      title: const Text("Module Offres Promotionnelles"),
                      subtitle: const Text(
                          "Permet au franchisé de créer ses propres offres."),
                      value: _moduleDealsEnabled,
                      onChanged: (value) =>
                          setState(() => _moduleDealsEnabled = value),
                    ),
                    SwitchListTile(
                      title: const Text("Module Click & Collect"),
                      subtitle: const Text(
                          "Active la gestion des commandes en ligne."),
                      value: _moduleClickAndCollectEnabled,
                      onChanged: (value) =>
                          setState(() => _moduleClickAndCollectEnabled = value),
                    ),
                  ],
                ),
              ),
            ),
            if (_isEditing)
              FranchiseeEmployeesSection(
                  franchiseeId: widget.franchiseeToEdit!.uid),
          ],
        ),
      ),
    );
  }
}

class FranchiseeEmployeesSection extends StatelessWidget {
  final String franchiseeId;
  final FranchiseRepository repository = FranchiseRepository();

  FranchiseeEmployeesSection({super.key, required this.franchiseeId});

  void _showAddEmployeeDialog(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Ajouter un employé"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Nom"),
                  validator: (v) => v!.isEmpty ? "Requis" : null,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: "Email"),
                  validator: (v) => v!.contains('@') ? null : "Email invalide",
                ),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: "Mot de passe"),
                  obscureText: true,
                  validator: (v) => v!.length < 6 ? "6 caractères min." : null,
                ),
                if (isLoading)
                  const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator())
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setState(() => isLoading = true);
                        String? error = await repository.createEmployee(
                          managerId: franchiseeId,
                          name: nameController.text.trim(),
                          email: emailController.text.trim(),
                          password: passwordController.text.trim(),
                        );
                        setState(() => isLoading = false);

                        if (context.mounted) {
                          if (error == null) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Employé créé !"),
                                    backgroundColor: Colors.green));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(error),
                                backgroundColor: Colors.red));
                          }
                        }
                      }
                    },
              child: const Text("Ajouter"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Gestion du Personnel",
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.blue),
                  onPressed: () => _showAddEmployeeDialog(context),
                  tooltip: "Ajouter un employé",
                )
              ],
            ),
            const Divider(),
            StreamBuilder<List<FranchiseUser>>(
              stream: repository.getStoreEmployeesStream(franchiseeId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("Aucun employé enregistré pour ce magasin.",
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final employee = snapshot.data![index];
                    return ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.badge, size: 20)),
                      title: Text(employee.companyName ?? "Sans nom"),
                      subtitle: Text(employee.email),
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Supprimer ?"),
                              content: Text(
                                  "Supprimer l'accès de ${employee.companyName} ?"),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text("Annuler")),
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text("Supprimer",
                                        style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await repository.deleteEmployee(employee.uid);
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
