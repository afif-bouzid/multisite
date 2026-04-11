import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '/models.dart';
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
        title: const Text("⚠️ Suppression Définitive",
            style: TextStyle(fontWeight: FontWeight.bold)),
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
                    "- Son compte de connexion\n- Toutes ses données (sessions, transactions)\n- Toute sa configuration (prix, etc.)",
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: emailConfirmationController,
                  decoration: InputDecoration(
                    labelText: "Tapez '${franchisee.email}' pour confirmer",
                    border: const OutlineInputBorder(),
                  ),
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
              child:
              const Text("Annuler", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
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
                    CircularProgressIndicator(color: Colors.black),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<List<FranchiseUser>>(
        stream: repository.getFranchiseesStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erreur: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storefront, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("Aucun franchisé pour le moment.",
                      style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }
          final franchisees = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: franchisees.length,
            separatorBuilder: (c, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final franchisee = franchisees[index];
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
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.storefront_rounded,
                            color: Colors.blue.shade700),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              franchisee.companyName ?? 'Nom non défini',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.email_outlined,
                                    size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(franchisee.email,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ],
                            ),
                            if (franchisee.contactName != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.person_outline,
                                      size: 14, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(franchisee.contactName!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ]
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _buildActionButton(
                            icon: Icons.edit_rounded,
                            color: Colors.blue.shade400,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => FranchiseeFormView(
                                        franchiseeToEdit: franchisee))),
                          ),
                          const SizedBox(width: 8),
                          _buildActionButton(
                            icon: Icons.delete_forever_rounded,
                            color: Colors.red.shade300,
                            onTap: () => _deleteFranchisee(
                                context, repository, franchisee),
                          ),
                        ],
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
        elevation: 4,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text("Nouveau Franchisé",
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const FranchiseeFormView())),
      ),
    );
  }
  Widget _buildActionButton(
      {required IconData icon,
        required Color color,
        required VoidCallback onTap}) {
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title:
        Text(_isEditing ? "Modifier un Franchisé" : "Créer un Franchisé"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              icon: _isLoading
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.blue))
                  : const Icon(Icons.check, color: Colors.blue),
              label: Text("Sauvegarder",
                  style: TextStyle(
                      color: _isLoading ? Colors.grey : Colors.blue,
                      fontWeight: FontWeight.bold)),
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
            _buildSectionTitle("Informations Entreprise"),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  TextFormField(
                      controller: _companyNameController,
                      decoration: const InputDecoration(
                          labelText: "Nom de la société",
                          prefixIcon: Icon(Icons.business_rounded),
                          border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _contactNameController,
                      decoration: const InputDecoration(
                          labelText: "Nom du contact",
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                          labelText: "Téléphone",
                          prefixIcon: Icon(Icons.phone_rounded),
                          border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                          labelText: "Adresse",
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? "Requis" : null),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle("Connexion"),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_isEditing)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Email et mot de passe non modifiables ici.",
                              style: TextStyle(
                                  color: Colors.blue.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextFormField(
                    controller: _emailController,
                    readOnly: _isEditing,
                    decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: _isEditing,
                        fillColor: _isEditing ? Colors.grey.shade100 : null,
                        border: const OutlineInputBorder()),
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
                          labelText: "Mot de passe (8+ car.)",
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder()),
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 8)
                          ? "8 caractères minimum"
                          : null,
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle("Modules"),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    activeThumbColor: Colors.black,
                    title: const Text("Borne",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Accès à la configuration borne."),
                    secondary:
                    const Icon(Icons.touch_app, color: Colors.black87),
                    value: _moduleKioskEnabled,
                    onChanged: (value) =>
                        setState(() => _moduleKioskEnabled = value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    activeThumbColor: Colors.black,
                    title: const Text("Offres Promos",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Création d'offres spéciales."),
                    secondary:
                    const Icon(Icons.local_offer, color: Colors.black87),
                    value: _moduleDealsEnabled,
                    onChanged: (value) =>
                        setState(() => _moduleDealsEnabled = value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    activeThumbColor: Colors.black,
                    title: const Text("Click & Collect",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Gestion commandes en ligne."),
                    secondary:
                    const Icon(Icons.shopping_bag, color: Colors.black87),
                    value: _moduleClickAndCollectEnabled,
                    onChanged: (value) =>
                        setState(() => _moduleClickAndCollectEnabled = value),
                  ),
                ],
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 32),
              FranchiseeEmployeesSection(
                  franchiseeId: widget.franchiseeToEdit!.uid),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
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
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: "Nom", border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? "Requis" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                      labelText: "Email", border: OutlineInputBorder()),
                  validator: (v) => v!.contains('@') ? null : "Email invalide",
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                      labelText: "Mot de passe", border: OutlineInputBorder()),
                  obscureText: true,
                  validator: (v) => v!.length < 6 ? "6 caractères min." : null,
                ),
                if (isLoading)
                  const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator())
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler",
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black, foregroundColor: Colors.white),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4.0),
              child: Text(
                "Personnel",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text("Ajouter"),
              onPressed: () => _showAddEmployeeDialog(context),
            )
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: StreamBuilder<List<FranchiseUser>>(
            stream: repository.getStoreEmployeesStream(franchiseeId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator()));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text("Aucun employé enregistré.",
                        style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final employee = snapshot.data![index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade100,
                      child:
                      Icon(Icons.badge_outlined, color: Colors.grey.shade600),
                    ),
                    title: Text(employee.companyName ?? "Sans nom",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(employee.email),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.red.shade300),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("Supprimer ?"),
                            content: Text(
                                "Révoquer l'accès de ${employee.companyName} ?"),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("Annuler",
                                      style: TextStyle(color: Colors.grey))),
                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("Supprimer")),
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
        ),
      ],
    );
  }
}
