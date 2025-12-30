import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _firebaseUser;
  FranchiseUser? _franchiseUser;
  bool _isLoading = true;

  User? get firebaseUser => _firebaseUser;

  FranchiseUser? get franchiseUser => _franchiseUser;

  bool get isLoading => _isLoading;

  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    _franchiseUser = null;
    if (user != null) {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        _franchiseUser = FranchiseUser.fromFirestore(
            doc.data() as Map<String, dynamic>, user.uid);
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        return 'Email ou mot de passe incorrect.';
      }
      return 'Une erreur est survenue. Veuillez réessayer.';
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
