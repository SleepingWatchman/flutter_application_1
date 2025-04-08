import 'package:flutter/foundation.dart';
import '../services/backup_service.dart';
import '../db/database_helper.dart';
import '../utils/config.dart';
import 'auth_provider.dart';

class BackupProvider extends ChangeNotifier {
  final AuthProvider _authProvider;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late final UserBackupService _userBackupService;
  late final CollaborationBackupService _collaborationBackupService;
  bool _isLoading = false;
  String? _error;
  bool _needsReload = false;

  BackupProvider(this._authProvider) {
    _userBackupService = UserBackupService(
      _dbHelper,
      Config.apiBaseUrl,
      _authProvider.token ?? '',
    );
    _collaborationBackupService = CollaborationBackupService(
      _dbHelper,
      Config.apiBaseUrl,
    );
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get needsReload => _needsReload;

  Future<void> createAndUploadUserBackup() async {
    if (_authProvider.token == null) {
      throw Exception('Не авторизован');
    }
    await _userBackupService.createAndUploadBackup();
  }

  Future<void> restoreFromLatestUserBackup() async {
    if (_authProvider.token == null) {
      throw Exception('Не авторизован');
    }
    await _userBackupService.restoreFromLatestBackup();
  }

  Future<void> createAndUploadCollaborationBackup(int databaseId) async {
    await _collaborationBackupService.createAndUploadBackup(databaseId);
  }

  Future<void> restoreFromLatestCollaborationBackup(int databaseId) async {
    await _collaborationBackupService.restoreFromLatestBackup(databaseId);
  }

  Future<void> uploadBackup() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await createAndUploadUserBackup();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> downloadBackup() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await restoreFromLatestUserBackup();
      
      // После успешного восстановления устанавливаем флаг перезагрузки
      _needsReload = true;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
  
  // Метод для сброса флага перезагрузки после перезапуска
  void resetReloadFlag() {
    _needsReload = false;
    notifyListeners();
  }
} 