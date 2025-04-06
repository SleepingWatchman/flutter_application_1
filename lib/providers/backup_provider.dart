import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../providers/auth_provider.dart';

class BackupProvider with ChangeNotifier {
  late final BackupService _backupService;
  bool _isLoading = false;
  String? _error;
  bool _needsReload = false;

  BackupProvider(AuthProvider authProvider) {
    _backupService = BackupService(authProvider);
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get needsReload => _needsReload;

  Future<void> uploadBackup() async {
    try {
      _isLoading = true;
      _error = null;
      _needsReload = false;
      notifyListeners();

      await _backupService.uploadBackup();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> downloadBackup() async {
    try {
      _isLoading = true;
      _error = null;
      _needsReload = false;
      notifyListeners();

      await _backupService.downloadBackup();
      
      // После успешного восстановления устанавливаем флаг перезагрузки
      _needsReload = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Метод для сброса флага перезагрузки после перезапуска
  void resetReloadFlag() {
    _needsReload = false;
    notifyListeners();
  }
} 