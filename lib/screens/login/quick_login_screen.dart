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
  CachedUser(
      {required this.uid,
      required this.name,
      required this.email,
      required this.role});
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      backgroundColor: isError ? Colors.black : Colors.cyan.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Colors.black, strokeWidth: 10))
          : Column(
              children: [
                const SizedBox(height: 80),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 60, vertical: 25),
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.cyan.withOpacity(0.3),
                            blurRadius: 40,
                            offset: const Offset(0, 15))
                      ]),
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -4),
                      children: [
                        TextSpan(
                            text: "O",
                            style: TextStyle(color: Colors.cyanAccent)),
                        TextSpan(
                            text: "uiBorne",
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                const Text("STATION D'ACCÈS TACTILE SÉCURISÉE",
                    style: TextStyle(
                        letterSpacing: 8,
                        color: Colors.black26,
                        fontWeight: FontWeight.w700)),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 100),
                      child: Row(
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
                const SizedBox(height: 50),
              ],
            ),
    );
  }
  void _openSecureModal(CachedUser user, bool isDelete) {
    final pc = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black87,
      pageBuilder: (ctx, anim1, anim2) => Center(
        child: Container(
          width: 700,
          padding: const EdgeInsets.all(60),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(60)),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isDelete ? Icons.delete_forever : Icons.lock_outline,
                    size: 80, color: isDelete ? Colors.red : Colors.cyan),
                const SizedBox(height: 20),
                Text(user.name.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.w900)),
                const SizedBox(height: 40),
                TextField(
                  controller: pc,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 70, letterSpacing: 30),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 50),
                SizedBox(
                  width: double.infinity,
                  height: 110,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: isDelete ? Colors.red : Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30))),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleAuth(user.email, pc.text, isDeleting: isDelete);
                    },
                    child: Text(
                        isDelete ? "SUPPRIMER LE PROFIL" : "DÉVERROUILLER",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
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
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40)),
              content: Container(
                width: 600,
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("NOUVEL ENREGISTREMENT",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 40),
                  TextField(
                      controller: ec,
                      decoration: InputDecoration(
                          labelText: "Email",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)))),
                  const SizedBox(height: 20),
                  TextField(
                      controller: pc,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: "Password",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)))),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 100,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25))),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleAuth(ec.text, pc.text);
                        },
                        child: const Text("VALIDER ET SAUVEGARDER",
                            style:
                                TextStyle(color: Colors.white, fontSize: 22))),
                  )
                ]),
              ),
            ));
  }
}
class _TactileCard extends StatelessWidget {
  final CachedUser user;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _TactileCard(
      {required this.user, required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 50),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          width: 380,
          height: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(70),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 40,
                  offset: const Offset(0, 20))
            ],
            border: Border.all(color: Colors.black.withOpacity(0.02), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.black,
                  child:
                      Icon(Icons.person, size: 70, color: Colors.cyanAccent)),
              const SizedBox(height: 40),
              Text(user.name.toUpperCase(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 34)),
              const SizedBox(height: 15),
              Text(user.role.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.cyan,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4)),
            ],
          ),
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
        width: 380,
        height: 500,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(70),
          border: Border.all(
              color: Colors.black12, width: 4, style: BorderStyle.solid),
        ),
        child: const Icon(Icons.add_circle_outline,
            size: 100, color: Colors.black12),
      ),
    );
  }
}
