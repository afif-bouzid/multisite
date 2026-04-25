import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth_provider.dart';

class CachedUser {
  final String uid;
  final String name;
  final String email;
  final String role;

  CachedUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role
  });

  Map<String, dynamic> toJson() =>
      {'uid': uid, 'name': name, 'email': email, 'role': role};

  factory CachedUser.fromJson(Map<String, dynamic> json) => CachedUser(
      uid: json['uid'] ?? '',
      name: json['name'] ?? 'Utilisateur',
      email: json['email'] ?? '',
      role: json['role'] ?? 'employee');
}

class QuickLoginScreen extends StatefulWidget {
  const QuickLoginScreen({super.key});
  @override
  State<QuickLoginScreen> createState() => _QuickLoginScreenState();
}

class _QuickLoginScreenState extends State<QuickLoginScreen> {
  List<CachedUser> _savedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  // --- LOGIQUE INTACTE ---

  Future<void> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('flame_secure_cache_v6');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() =>
      _savedUsers = decoded.map((e) => CachedUser.fromJson(e)).toList());
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveToCache(CachedUser user) async {
    final prefs = await SharedPreferences.getInstance();
    _savedUsers.removeWhere((u) => u.email == user.email);
    _savedUsers.insert(0, user);
    await prefs.setString('flame_secure_cache_v6', jsonEncode(_savedUsers));
    setState(() {});
  }

  Future<void> _handleAuth(String email, String password,
      {bool isDeleting = false}) async {
    final auth = context.read<AuthProvider>();
    setState(() => _isLoading = true);
    final error = await auth.signIn(email, password);
    if (error == null) {
      if (isDeleting) {
        await auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        _savedUsers.removeWhere((u) => u.email == email);
        await prefs.setString('flame_secure_cache_v6', jsonEncode(_savedUsers));
        _showNotify("PROFIL EFFACÉ", isError: true);
      } else {
        int retry = 0;
        while (auth.franchiseUser == null && retry < 40) {
          await Future.delayed(const Duration(milliseconds: 100));
          retry++;
        }
        if (auth.franchiseUser != null) {
          final p = auth.franchiseUser!;
          final newUser = CachedUser(
            uid: p.uid,
            name: p.contactName ?? email.split('@')[0],
            email: email,
            role: p.role ?? 'employee',
          );
          await _saveToCache(newUser);
          _redirect(newUser.role);
        }
      }
    } else {
      _showNotify("ACCÈS REFUSÉ : $error", isError: true);
    }
    setState(() => _isLoading = false);
  }

  void _redirect(String role) {
    Navigator.pushReplacementNamed(
        context, role == 'franchisor' ? '/franchisor_dashboard' : '/home');
  }

  void _showNotify(String m, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      backgroundColor: isError ? Colors.black87 : Colors.cyan.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ));
  }

  // --- DESIGN RESPONSIVE REVISITÉ ---

  @override
  Widget build(BuildContext context) {
    // Calcul de la taille de l'écran pour un affichage adaptatif
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Fond gris très clair et moderne
      body: SafeArea(
        child: _isLoading
            ? const Center(
            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 4))
            : Column(
          children: [
            SizedBox(height: isMobile ? 30 : 60),

            // LOGO RESPONSIVE
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 30 : 50,
                  vertical: isMobile ? 15 : 20),
              decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(isMobile ? 20 : 30),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.cyan.withOpacity(0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10))
                  ]),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 60, // Réduit pour éviter l'overflow
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2),
                    children: [
                      TextSpan(text: "O", style: TextStyle(color: Colors.cyanAccent)),
                      TextSpan(text: "uiBorne", style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // SOUS-TITRE RESPONSIVE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "STATION D'ACCÈS TACTILE SÉCURISÉE",
                textAlign: TextAlign.center,
                style: TextStyle(
                    letterSpacing: isMobile ? 2 : 5,
                    color: Colors.grey.shade400,
                    fontSize: isMobile ? 10 : 12,
                    fontWeight: FontWeight.w800),
              ),
            ),

            const SizedBox(height: 40),

            // GRILLE D'UTILISATEURS (Wrap remplace le Row fixe)
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 20),
                child: Center(
                  child: Wrap(
                    spacing: 20, // Espace horizontal entre les cartes
                    runSpacing: 20, // Espace vertical entre les cartes
                    alignment: WrapAlignment.center,
                    children: [
                      ..._savedUsers.map((u) => _TactileCard(
                        user: u,
                        onTap: () => _openSecureModal(u, false),
                        onDelete: () => _openSecureModal(u, true),
                      )),
                      _AddTactileCard(onTap: _openNewLoginModal),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MODALES REVISITÉES POUR ÊTRE RESPONSIVES ---

  void _openSecureModal(CachedUser user, bool isDelete) {
    final pc = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black87, // Fond assombri élégant
      pageBuilder: (ctx, anim1, anim2) => Center(
        child: SingleChildScrollView( // Empêche l'overflow du clavier sur mobile
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450), // Taille max bloquée
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 30, spreadRadius: 5)
                ]),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDelete ? Colors.red.shade50 : Colors.cyan.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(isDelete ? Icons.delete_forever : Icons.lock_outline,
                        size: 50, color: isDelete ? Colors.red : Colors.cyan),
                  ),
                  const SizedBox(height: 20),
                  Text(user.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 30),

                  TextField(
                    controller: pc,
                    obscureText: true,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30, letterSpacing: 20),
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      hintText: "••••",
                      hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 10),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none),
                    ),
                  ),

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 65, // Hauteur standardisée
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: isDelete ? Colors.red : Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleAuth(user.email, pc.text, isDeleting: isDelete);
                      },
                      child: FittedBox(
                        child: Text(
                            isDelete ? "SUPPRIMER LE PROFIL" : "DÉVERROUILLER",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openNewLoginModal() {
    final ec = TextEditingController();
    final pc = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => Center(
          child: SingleChildScrollView(
            child: Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("NOUVEL ACCÈS",
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 30),
                  TextField(
                      controller: ec,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                          labelText: "Adresse Email",
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none))),
                  const SizedBox(height: 15),
                  TextField(
                      controller: pc,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: "Mot de passe",
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none))),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15))),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleAuth(ec.text, pc.text);
                        },
                        child: const Text("VALIDER & SAUVEGARDER",
                            style:
                            TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  )
                ]),
              ),
            ),
          ),
        ));
  }
}

// --- COMPOSANTS DE CARTES RESPONSIVES ---

class _TactileCard extends StatelessWidget {
  final CachedUser user;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TactileCard({
    required this.user,
    required this.onTap,
    required this.onDelete
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        width: 180, // Taille idéale pour passer de Desktop (plusieurs) à Mobile (2 colonnes)
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ],
          border: Border.all(color: Colors.grey.shade100, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.cyan.withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2
                    )
                  ]
              ),
              child: const Icon(Icons.person_rounded, size: 40, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                user.name.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.cyan.shade50,
                  borderRadius: BorderRadius.circular(10)
              ),
              child: Text(
                user.role.toUpperCase(),
                style: TextStyle(
                    color: Colors.cyan.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTactileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTactileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: Colors.grey.shade300, width: 2, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 50, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              "AJOUTER",
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2
              ),
            )
          ],
        ),
      ),
    );
  }
}