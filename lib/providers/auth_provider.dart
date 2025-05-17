import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _user;
  bool _isLoading = false;
  String? _error;
  bool _wasTokenExpired = false;
  bool _isGuestMode = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null || _isGuestMode;
  String? get token => _authService.token;
  String? get error => _error;
  AuthService get authService => _authService;
  bool get wasTokenExpired => _wasTokenExpired;
  bool get isGuestMode => _isGuestMode;

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
      // Если токен истёк или пользователь не авторизован — signOut
      if (_authService.isTokenExpired() && _user != null) {
        _wasTokenExpired = true;
        await signOut();
      }
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
      _isGuestMode = false;
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

  void resetTokenExpiredFlag() {
    _wasTokenExpired = false;
    notifyListeners();
  }

  void enableGuestMode() {
    _isGuestMode = true;
    notifyListeners();
  }

  void disableGuestMode() {
    _isGuestMode = false;
    notifyListeners();
  }
} 