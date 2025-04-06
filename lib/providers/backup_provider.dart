import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../providers/auth_provider.dart';

class BackupProvider with ChangeNotifier {
  late final BackupService _backupService;
  bool _isLoading = false;
  String? _error;

  BackupProvider(AuthProvider authProvider) {
    _backupService = BackupService(authProvider);
  }

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> uploadBackup() async {
    try {
      _isLoading = true;
      _error = null;
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
      notifyListeners();

      await _backupService.downloadBackup();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
} 