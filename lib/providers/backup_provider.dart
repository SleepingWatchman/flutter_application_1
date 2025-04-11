import 'package:flutter/foundation.dart';
import '../services/backup_service.dart';
import '../db/database_helper.dart';
import '../utils/config.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

class BackupProvider extends ChangeNotifier {
  final AuthProvider _authProvider;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late final UserBackupService _userBackupService;
  late final CollaborationBackupService _collaborationBackupService;
  bool _isLoading = false;
  String? _error;
  bool _needsReload = false;
  late final DatabaseProvider _databaseProvider;
  bool _disposed = false;

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

  // Метод для установки DatabaseProvider
  void setDatabaseProvider(DatabaseProvider provider) {
    _databaseProvider = provider;
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get needsReload => _needsReload;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyIfNotDisposed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

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
      _notifyIfNotDisposed();

      await createAndUploadUserBackup();

      _isLoading = false;
      _notifyIfNotDisposed();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyIfNotDisposed();
      rethrow;
    }
  }

  Future<void> downloadBackup() async {
    try {
      _isLoading = true;
      _error = null;
      _notifyIfNotDisposed();

      await restoreFromLatestUserBackup();
      
      // После успешного восстановления уведомляем о необходимости обновления данных
      _needsReload = true;
      _databaseProvider.setNeedsUpdate(true);
      _isLoading = false;
      _notifyIfNotDisposed();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyIfNotDisposed();
      rethrow;
    }
  }
  
  // Метод для сброса флага перезагрузки после перезапуска
  void resetReloadFlag() {
    _needsReload = false;
    _notifyIfNotDisposed();
  }
} 