import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'collaboration_provider.dart';
import '../models/backup_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseProvider extends ChangeNotifier {
  bool _needsUpdate = false;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  CollaborationProvider? _collaborationProvider;
  Database? _database;
  String? _lastError;
  bool _isInitializing = false;
  String? _currentDatabaseId;
  bool _isRestoringPersonalData = false;

  bool get needsUpdate => _needsUpdate;
  String? get lastError => _lastError;
  bool get isInitializing => _isInitializing;
  String? get currentDatabaseId => _currentDatabaseId;
  DatabaseHelper get dbHelper => _dbHelper;
  bool get isRestoringPersonalData => _isRestoringPersonalData;

  void setCollaborationProvider(CollaborationProvider provider) {
    try {
      print('Установка CollaborationProvider в DatabaseProvider');
      if (_collaborationProvider != provider) {
        _collaborationProvider = provider;
        print('CollaborationProvider успешно установлен');
      }
    } catch (e) {
      _lastError = 'Ошибка при установке CollaborationProvider: $e';
      print(_lastError);
      rethrow;
    }
  }

  bool get isCollaborationProviderInitialized => _collaborationProvider != null;

  void _checkCollaborationProvider() {
    if (_collaborationProvider == null) {
      _lastError = 'CollaborationProvider не инициализирован';
      print(_lastError);
      throw Exception(_lastError);
    }
  }

  void setNeedsUpdate(bool value) {
    try {
      if (_needsUpdate != value) {
        _needsUpdate = value;
        print('DatabaseProvider: setNeedsUpdate($value)');
        
        // ИСПРАВЛЕНИЕ: Убираем автоматическую синхронизацию для предотвращения бесконечных циклов
        // Синхронизация должна вызываться явно, когда это необходимо
        
        // Уведомляем слушателей после всех изменений
        notifyListeners();
      }
    } catch (e) {
      _lastError = 'Ошибка при обновлении состояния: $e';
      print(_lastError);
      rethrow;
    }
  }

  void resetUpdateFlag() {
    try {
      _needsUpdate = false;
      _lastError = null;
    } catch (e) {
      _lastError = 'Ошибка при сбросе флага обновления: $e';
      print(_lastError);
      rethrow;
    }
  }

  Future<BackupData> createBackup([String? databaseId]) async {
    try {
      print('Начало создания резервной копии${databaseId != null ? " для базы $databaseId" : ""}');
      // Создаем резервную копию текущей базы или указанной совместной базы
      final backup = await _dbHelper.createBackup(databaseId);
      print('Резервная копия успешно создана');
      _lastError = null;
      return backup;
    } catch (e) {
      _lastError = 'Ошибка при создании резервной копии: $e';
      print(_lastError);
      rethrow;
    }
  }

  Future<void> restoreFromBackup(BackupData backupData, [String? databaseId]) async {
    try {
      print('Начало восстановления из резервной копии${databaseId != null ? " для базы $databaseId" : ""}');
      await _dbHelper.restoreFromBackup(backupData, databaseId);
      print('Восстановление из резервной копии успешно завершено');
      setNeedsUpdate(true);
      _lastError = null;
    } catch (e) {
      _lastError = 'Ошибка при восстановлении из резервной копии: $e';
      print(_lastError);
      rethrow;
    }
  }

  Future<void> clearDatabaseTables(String? databaseId) async {
    try {
      print('Начало очистки таблиц${databaseId != null ? " для базы $databaseId" : ""}');
      if (databaseId == null) {
        throw Exception('ID базы данных не может быть null');
      }
      await _dbHelper.executeTransaction((txn) async {
        await _dbHelper.clearDatabaseTables(databaseId, txn);
      });
      print('Очистка таблиц успешно завершена');
      setNeedsUpdate(true);
      _lastError = null;
    } catch (e) {
      _lastError = 'Ошибка при очистке таблиц базы данных: $e';
      print(_lastError);
      rethrow;
    }
  }

  Future<BackupData?> getPersonalBackup() async {
    try {
      print('Получение персональной резервной копии');
      final prefs = await SharedPreferences.getInstance();
      final backupJson = prefs.getString('personal_backup');
      if (backupJson != null) {
        print('Персональная резервная копия найдена');
        _lastError = null;
        return BackupData.fromJson(json.decode(backupJson));
      }
      print('Персональная резервная копия не найдена');
      return null;
    } catch (e) {
      _lastError = 'Ошибка при получении персональной резервной копии: $e';
      print(_lastError);
      rethrow;
    }
  }

  Future<void> savePersonalBackup(BackupData backupData) async {
    try {
      print('Сохранение персональной резервной копии');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('personal_backup', json.encode(backupData.toJson()));
      print('Персональная резервная копия успешно сохранена');
      _lastError = null;
    } catch (e) {
      _lastError = 'Ошибка при сохранении персональной резервной копии: $e';
      print(_lastError);
      rethrow;
    }
  }

  Future<Database> get database async {
    try {
      if (_database != null) return _database!;
      _database = await _dbHelper.database;
      return _database!;
    } catch (e) {
      print('Ошибка при получении базы данных: $e');
      rethrow;
    }
  }

  Future<void> initializeSharedDatabase(String databaseId) async {
    try {
      _isInitializing = true;
      notifyListeners();
      
      print('Инициализация совместной базы данных в DatabaseProvider: $databaseId');
      
      // ИСПРАВЛЕНИЕ: Сохраняем резервную копию ТОЛЬКО если это первое переключение
      if (_currentDatabaseId == null) {
        try {
          print('Создание резервной копии личных данных...');
          final currentBackup = await createBackup(_currentDatabaseId);
          await savePersonalBackup(currentBackup);
          print('Резервная копия личных данных создана');
        } catch (e) {
          print('Ошибка создания резервной копии: $e');
          // Не критично, продолжаем
        }
      } else {
        print('Резервная копия уже создана, пропускаем');
      }
      
      // ИСПРАВЛЕНИЕ: Убираем долгие транзакции - используем прямой вызов DatabaseHelper
      try {
        await _dbHelper.initializeSharedDatabase(databaseId);
        print('Совместная база инициализирована через DatabaseHelper');
      } catch (e) {
        print('Ошибка инициализации через DatabaseHelper: $e');
        // Продолжаем работу даже при ошибке
      }
      
      // Устанавливаем текущую базу данных
      _currentDatabaseId = databaseId;
      
      // Устанавливаем флаг обновления
      setNeedsUpdate(true);
      
      _lastError = null;
      print('Инициализация совместной базы в DatabaseProvider завершена');
    } catch (e) {
      _lastError = 'Ошибка инициализации совместной базы: $e';
      print(_lastError);
      // НЕ перебрасываем исключение, чтобы не блокировать приложение
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> switchToDatabase(String? databaseId) async {
    // Защита от повторного переключения на ту же базу
    if (_currentDatabaseId == databaseId) {
      print('База данных ${databaseId ?? "локальная"} уже активна, пропускаем переключение');
      return;
    }
    
    try {
      _isInitializing = true;
      notifyListeners();
      
      print('Переключение на базу данных в DatabaseProvider: ${databaseId ?? "локальную"}');
      
      // ИСПРАВЛЕНИЕ: Быстрая очистка кешированных данных
      await _clearCachedData();
      
      // ИСПРАВЛЕНИЕ: При переключении на личную базу НЕ создаем резервную копию, а ВОССТАНАВЛИВАЕМ личные данные
      if (_currentDatabaseId != null && databaseId == null) {
        try {
          _isRestoringPersonalData = true; // УСТАНАВЛИВАЕМ ФЛАГ
          print('Восстановление личных данных при переключении на личную базу...');
          final personalBackup = await getPersonalBackup();
          if (personalBackup != null) {
            print('Найдена резервная копия личных данных, восстанавливаем...');
            await restoreFromBackup(personalBackup, null);
            print('Личные данные успешно восстановлены');
          } else {
            print('Резервная копия личных данных не найдена');
          }
        } catch (e) {
          print('Ошибка восстановления личных данных: $e');
          // Не критично, продолжаем
        } finally {
          _isRestoringPersonalData = false; // СБРАСЫВАЕМ ФЛАГ
        }
      } else {
        print('Восстановление личных данных не требуется для данного переключения');
      }
      
      // Обновляем текущую базу данных
      _currentDatabaseId = databaseId;
      
      // Устанавливаем флаг обновления
      setNeedsUpdate(true);
      
      _lastError = null;
      print('Переключение на базу данных в DatabaseProvider ${databaseId ?? "локальную"} завершено успешно');
    } catch (e) {
      _lastError = 'Ошибка переключения базы данных: $e';
      print(_lastError);
      // НЕ перебрасываем исключение, чтобы не блокировать приложение
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  // Метод для очистки кешированных данных
  Future<void> _clearCachedData() async {
    try {
      print('Очистка кешированных данных при переключении базы');
      // Очищаем все кешированные данные в DatabaseHelper
      await _dbHelper.clearCache();
      print('Кешированные данные успешно очищены');
    } catch (e) {
      print('Предупреждение: Ошибка при очистке кеша: $e');
    }
  }

  // Метод для принудительного обновления всех слушателей
  void notifyAllListeners() {
    print('Запрос на обновление всех слушателей DatabaseProvider');
  }

  // Методы для получения данных с учетом текущей базы данных
  Future<List<dynamic>> getNotesForCurrentDatabase() async {
    return await _dbHelper.getAllNotes(_currentDatabaseId);
  }
  
  Future<List<dynamic>> getFoldersForCurrentDatabase() async {
    return await _dbHelper.getFolders(_currentDatabaseId);
  }
  
  Future<List<dynamic>> getScheduleEntriesForCurrentDatabase() async {
    return await _dbHelper.getScheduleEntries(_currentDatabaseId);
  }
  
  Future<List<dynamic>> getPinboardNotesForCurrentDatabase() async {
    return await _dbHelper.getPinboardNotes(_currentDatabaseId);
  }
  
  Future<List<dynamic>> getConnectionsForCurrentDatabase() async {
    return await _dbHelper.getConnectionsDB(_currentDatabaseId);
  }
  
  Future<List<dynamic>> getImagesForCurrentDatabase() async {
    return await _dbHelper.getAllImages(_currentDatabaseId);
  }
  
  // Метод для получения заметок из определенной папки с учетом текущей базы
  Future<List<dynamic>> getNotesByFolderForCurrentDatabase(int folderId) async {
    return await _dbHelper.getNotesByFolder(folderId, _currentDatabaseId);
  }
  
  // Методы для добавления новых элементов с учетом текущей базы
  Future<int> insertNoteWithCurrentDatabase(Map<String, dynamic> note) async {
    if (_currentDatabaseId != null) {
      note['database_id'] = _currentDatabaseId;
    }
    return await _dbHelper.insertNote(note);
  }
  
  Future<int> insertFolderWithCurrentDatabase(Map<String, dynamic> folder) async {
    if (_currentDatabaseId != null) {
      folder['database_id'] = _currentDatabaseId;
    }
    return await _dbHelper.insertFolder(folder);
  }
  
  Future<int> insertScheduleEntryWithCurrentDatabase(Map<String, dynamic> entry) async {
    if (_currentDatabaseId != null) {
      entry['database_id'] = _currentDatabaseId;
    }
    return await _dbHelper.insertScheduleEntry(entry);
  }
  
  Future<int> insertPinboardNoteWithCurrentDatabase(Map<String, dynamic> note) async {
    if (_currentDatabaseId != null) {
      note['database_id'] = _currentDatabaseId;
    }
    return await _dbHelper.insertPinboardNote(note);
  }
  
  Future<int> insertConnectionWithCurrentDatabase(Map<String, dynamic> connection) async {
    if (_currentDatabaseId != null) {
      connection['database_id'] = _currentDatabaseId;
    }
    return await _dbHelper.insertConnection(connection);
  }
} 