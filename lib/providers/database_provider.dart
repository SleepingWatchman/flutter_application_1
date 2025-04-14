import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'collaboration_provider.dart';
import '../models/backup_data.dart';

class DatabaseProvider extends ChangeNotifier {
  bool _needsUpdate = false;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  CollaborationProvider? _collaborationProvider;

  bool get needsUpdate => _needsUpdate;

  void setCollaborationProvider(CollaborationProvider provider) {
    _collaborationProvider = provider;
  }

  void setNeedsUpdate(bool value) {
    if (_needsUpdate != value) {
      _needsUpdate = value;
      notifyListeners();
      
      // Если используется совместная база, синхронизируем изменения
      if (_collaborationProvider?.isUsingSharedDatabase == true) {
        _collaborationProvider?.syncSharedDatabase();
      }
    }
  }

  void resetUpdateFlag() {
    _needsUpdate = false;
  }

  Future<BackupData> createBackup() async {
    // Создаем резервную копию текущей базы
    return await _dbHelper.createBackup();
  }

  Future<void> restoreFromBackup() async {
    // Восстанавливаем базу из резервной копии
    await _dbHelper.restoreFromBackup();
    setNeedsUpdate(true);
  }
} 