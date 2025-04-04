import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _user;
  bool _isLoading = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  String? get token => _authService.token;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Загружаем сохраненные данные
      await _authService.loadSavedData();
      _user = _authService.currentUser;
    } catch (e) {
      debugPrint('Error loading saved data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Подписываемся на изменения пользователя
    _authService.userStream.listen((UserModel? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<void> register(String email, String password, String displayName) async {
    try {
      _isLoading = true;
      notifyListeners();

      _user = await _authService.register(email, password, displayName);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      _user = await _authService.login(email, password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _authService.signOut();
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      _isLoading = true;
      notifyListeners();

      _user = await _authService.updateProfile(
        displayName: displayName,
        photoURL: photoURL,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
} 