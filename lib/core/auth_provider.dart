import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _firebaseUser;
  FranchiseUser? _franchiseUser;
  bool _isLoading = true;
  User? get firebaseUser => _firebaseUser;
  FranchiseUser? get franchiseUser => _franchiseUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _firebaseUser != null;
  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }
  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    _franchiseUser = null;
    _isLoading = true;
    notifyListeners();
    if (user != null) {
      try {
        DocumentSnapshot doc =
            await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          _franchiseUser = FranchiseUser.fromFirestore(
              doc.data() as Map<String, dynamic>, user.uid);
        }
      } catch (e) {
        if (kDebugMode) print("Erreur AuthProvider: $e");
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<String?> signIn(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.message;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
