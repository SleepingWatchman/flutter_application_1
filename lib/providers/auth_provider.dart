import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../db/database_helper.dart';
import '../utils/config.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _user;
  bool _isLoading = false;
  String? _error;
  bool _wasTokenExpired = false;
  bool _isGuestMode = false;
  bool _isRestoringBackup = false;
  bool _isCreatingBackupOnSignOut = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null || _isGuestMode;
  String? get token => _authService.token;
  String? get error => _error;
  AuthService get authService => _authService;
  bool get wasTokenExpired => _wasTokenExpired;
  bool get isGuestMode => _isGuestMode;
  bool get isRestoringBackup => _isRestoringBackup;
  bool get isCreatingBackupOnSignOut => _isCreatingBackupOnSignOut;

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

  Future<void> signIn(String email, String password, [Function()? onBackupRestored]) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Выполняем вход
      _user = await _authService.login(email, password);
      
      // После успешного входа пытаемся восстановить данные из бэкапа
      await _attemptBackupRestore(onBackupRestored);
      
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Пытается восстановить пользовательские данные из бэкапа
  Future<void> _attemptBackupRestore([Function()? onBackupRestored]) async {
    if (_user == null || _authService.token == null) {
      return;
    }

    try {
      _isRestoringBackup = true;
      notifyListeners();

      print('🔄 BACKUP: Начинаем автоматическое восстановление пользовательских данных из бэкапа...');
      
      // Импортируем необходимые сервисы локально, чтобы не создавать зависимости
      final backupService = await _createBackupService();
      if (backupService != null) {
        await backupService.restoreFromLatestBackup();
        print('✅ BACKUP: Данные пользователя успешно восстановлены из бэкапа');
        
        // Вызываем коллбэк если он предоставлен
        if (onBackupRestored != null) {
          onBackupRestored();
        }
      }
    } catch (e) {
      print('⚠️ BACKUP: Ошибка при восстановлении данных из бэкапа: $e');
      // Не бросаем исключение, чтобы не прерывать процесс входа
      // Пользователь может войти в систему даже если восстановление не удалось
    } finally {
      _isRestoringBackup = false;
      notifyListeners();
    }
  }

  /// Создает сервис бэкапа для восстановления данных
  Future<UserBackupService?> _createBackupService() async {
    try {
      final dbHelper = DatabaseHelper();
      final token = _authService.token;
      
      if (token == null) return null;
      
      return UserBackupService(
        dbHelper,
        Config.apiBaseUrl,
        token,
      );
    } catch (e) {
      print('⚠️ BACKUP: Не удалось создать сервис бэкапа: $e');
      return null;
    }
  }

  /// Публичный метод для ручного восстановления данных из бэкапа
  Future<void> restoreUserBackup([Function()? onBackupRestored]) async {
    if (_user == null || _authService.token == null) {
      throw Exception('Пользователь не авторизован');
    }

    await _attemptBackupRestore(onBackupRestored);
  }

  /// Создает резервную копию данных перед выходом из аккаунта
  Future<void> _createBackupOnSignOut([Function()? onBackupCreated]) async {
    if (_user == null || _authService.token == null) {
      return;
    }

    try {
      _isCreatingBackupOnSignOut = true;
      notifyListeners();

      print('💾 BACKUP: Создание резервной копии перед выходом из аккаунта...');
      
      final backupService = await _createBackupService();
      if (backupService != null) {
        await backupService.createAndUploadBackup();
        print('✅ BACKUP: Резервная копия успешно создана перед выходом');
        
        // Вызываем коллбэк если он предоставлен
        if (onBackupCreated != null) {
          onBackupCreated();
        }
      }
    } catch (e) {
      print('⚠️ BACKUP: Ошибка при создании резервной копии перед выходом: $e');
      // Не бросаем исключение, чтобы не прерывать процесс выхода
      // Пользователь может выйти из системы даже если создание бэкапа не удалось
    } finally {
      _isCreatingBackupOnSignOut = false;
      notifyListeners();
    }
  }

  Future<void> signOut([Function()? onBackupCreated]) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Создаем резервную копию ДО выхода из аккаунта (только для авторизованных пользователей)
      if (_user != null && !_isGuestMode) {
        await _createBackupOnSignOut(onBackupCreated);
      }

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