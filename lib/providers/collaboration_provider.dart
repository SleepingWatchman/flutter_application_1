import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'package:provider/provider.dart';
import '../models/shared_database.dart';
import '../models/shared_database_access.dart';
import '../services/collaboration_service.dart';
import '../services/auto_sync_service.dart';
import '../models/backup_data.dart';
import '../db/database_helper.dart';
import '../models/collaboration_database.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class CollaborationProvider with ChangeNotifier {
  final AuthProvider _authProvider;
  late final CollaborationService _collaborationService;
  late final AutoSyncService _autoSyncService;
  DatabaseProvider? _databaseProvider;
  List<SharedDatabase> _sharedDatabases = [];
  String? _currentDatabaseId;
  bool _isUsingSharedDatabase = false;
  bool _isLoading = false;
  List<SharedDatabase> _databases = [];
  final String _baseUrl = 'http://localhost:8080/api/collaboration';
  String? _error;
  List<CollaborationDatabase>? _collaborationDatabases;

  CollaborationProvider(this._authProvider) {
    print('Инициализация CollaborationProvider');
    print('AuthProvider token: ${_authProvider.token}');
    _collaborationService = CollaborationService(_authProvider.authService);
    _autoSyncService = AutoSyncService(
      _collaborationService,
      DatabaseHelper(),
    );
    _initializeAutoSync();
  }

  Future<void> _initializeAutoSync() async {
    await _autoSyncService.initialize();
  }

  @override
  void dispose() {
    _autoSyncService.dispose();
    super.dispose();
  }

  List<SharedDatabase> get sharedDatabases => _sharedDatabases;
  String? get currentDatabaseId => _currentDatabaseId;
  bool get isUsingSharedDatabase => _isUsingSharedDatabase;
  bool get isLoading => _isLoading;
  List<SharedDatabase> get databases => _databases;
  List<CollaborationDatabase>? get collaborationDatabases => _collaborationDatabases;
  String? get error => _error;

  void setDatabaseProvider(DatabaseProvider provider) {
    try {
      print('Установка DatabaseProvider в CollaborationProvider');
      _databaseProvider = provider;
      provider.setCollaborationProvider(this);
      print('DatabaseProvider успешно установлен');
    } catch (e) {
      print('Ошибка при установке DatabaseProvider: $e');
      rethrow;
    }
  }

  bool get isDatabaseProviderInitialized => _databaseProvider != null;

  void _checkDatabaseProvider() {
    if (_databaseProvider == null) {
      print('DatabaseProvider не инициализирован при попытке выполнения операции');
      throw Exception('DatabaseProvider не инициализирован');
    }
  }

  Future<void> loadSharedDatabases() async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      _sharedDatabases = await _collaborationService.getSharedDatabases();
    } catch (e) {
      print('Ошибка загрузки совместных баз: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDatabases() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('Загрузка списка баз данных');
      print('Текущий токен: ${_authProvider.token}');
      
      if (_authProvider.token == null) {
        throw Exception('Не авторизован');
      }

      _databases = await _collaborationService.getSharedDatabases();
      print('Загружено баз данных: ${_databases.length}');
      _error = null;
    } catch (e) {
      print('Ошибка при загрузке баз данных: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createSharedDatabase(String name) async {
    if (_authProvider.user == null) {
      throw Exception('Пользователь не авторизован');
    }

    _checkDatabaseProvider();

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('Создание совместной базы данных с именем: $name');
      
      final newDatabase = await _collaborationService.createSharedDatabase(name);
      if (newDatabase.serverId.isEmpty) {
        throw Exception('Получен пустой serverId при создании базы данных');
      }
      print('Совместная база данных успешно создана с ID: ${newDatabase.serverId}');
      
      // Инициализируем локальную копию базы
      await _databaseProvider!.initializeSharedDatabase(newDatabase.serverId);
      print('Локальная копия базы инициализирована');
      
      // Обновляем список баз
      await loadDatabases();
      print('Список баз обновлен');
      
      // Автоматически переключаемся на новую базу
      await switchToSharedDatabase(newDatabase.serverId);
      print('Переключение на новую базу выполнено');
      
      _error = null;
    } catch (e) {
      print('Ошибка создания совместной базы: $e');
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importSharedDatabase(String databaseId) async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      print('Начало импорта базы данных с ID: $databaseId');
      print('Токен пользователя: ${_authProvider.token}');
      
      final databases = await _collaborationService.importSharedDatabase(databaseId);
      _databases = databases;
      await loadDatabases();
      
      print('База данных успешно импортирована');
    } catch (e) {
      print('Ошибка импорта совместной базы: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchToSharedDatabase(String databaseId) async {
    _checkDatabaseProvider();

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('Переключение на совместную базу данных: $databaseId');

      // Проверяем существование базы данных на сервере
      final response = await http.get(
        Uri.parse('$_baseUrl/databases/$databaseId'),
        headers: {
          'Authorization': 'Bearer ${_authProvider.token}',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('База данных не найдена на сервере');
      }

      print('База данных найдена на сервере');

      // Создаем резервную копию текущей базы
      if (_currentDatabaseId != null) {
        final backupData = await _databaseProvider!.createBackup(_currentDatabaseId);
        await _databaseProvider!.savePersonalBackup(backupData);
        print('Создана резервная копия текущей базы');
      }

      // Загружаем данные совместной базы
      final sharedBackupData = await downloadDatabase(databaseId);
      print('Загружены данные совместной базы');
      
      // Заменяем локальную базу данными совместной базы
      await _databaseProvider!.restoreFromBackup(sharedBackupData, databaseId);
      print('Локальная база заменена данными совместной базы');

      _currentDatabaseId = databaseId;
      _isUsingSharedDatabase = true;
      
      // Уведомляем о необходимости обновления данных
      _databaseProvider!.setNeedsUpdate(true);
      
      // Обновляем список баз
      await loadDatabases();
      print('Список баз обновлен');

      // Запускаем автоматическую синхронизацию
      await _autoSyncService.syncIfNeeded();
      print('Автоматическая синхронизация запущена');

      _error = null;
    } catch (e) {
      print('Ошибка переключения на совместную базу: $e');
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BackupData> downloadDatabase(String databaseId) async {
    try {
      print('Загрузка базы данных с ID: $databaseId');
      
      final response = await http.get(
        Uri.parse('$_baseUrl/databases/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer ${_authProvider.token}',
        },
      );

      print('Статус ответа: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Данные успешно получены');
        return BackupData.fromJson(data);
      } else if (response.statusCode == 404) {
        print('Бэкап не найден, возвращаю пустой объект');
        return BackupData(
          folders: const [],
          notes: const [],
          scheduleEntries: const [],
          pinboardNotes: const [],
          connections: const [],
          noteImages: const [],
          databaseId: databaseId,
          userId: _authProvider.user?.id ?? '',
        );
      } else {
        print('Ошибка при загрузке базы: ${response.statusCode} - ${response.body}');
        throw Exception('Ошибка при загрузке базы данных: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки базы данных: $e');
      rethrow;
    }
  }

  Future<void> switchToPersonalDatabase() async {
    if (_databaseProvider == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      print('Переключение на личную базу данных');

      if (_currentDatabaseId != null) {
        // Если мы находимся в совместной базе, сначала сохраняем изменения
        final backupData = await _databaseProvider!.createBackup(_currentDatabaseId);
        await _collaborationService.saveDatabaseBackup(_currentDatabaseId!, backupData);
        print('Сохранены изменения в совместной базе');

        // Очищаем таблицы текущей базы
        await _databaseProvider!.clearDatabaseTables(_currentDatabaseId);
        print('Очищены таблицы совместной базы');
      }

      // Восстанавливаем личную базу
      final personalBackup = await _databaseProvider!.getPersonalBackup();
      if (personalBackup != null) {
        await _databaseProvider!.restoreFromBackup(personalBackup);
        print('Восстановлена личная база');
      }

      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      
      // Уведомляем о необходимости обновления данных
      _databaseProvider!.setNeedsUpdate(true);
      
      // Обновляем список баз
      await loadDatabases();
      print('Список баз обновлен');

      // Останавливаем автоматическую синхронизацию
      _autoSyncService.dispose();
      print('Автоматическая синхронизация остановлена');

    } catch (e) {
      print('Ошибка переключения на личную базу: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _replaceLocalDatabase(BackupData backupData, [String? databaseId]) async {
    try {
      await _databaseProvider?.restoreFromBackup(backupData, databaseId);
      notifyListeners();
    } catch (e) {
      print('Error replacing local database: $e');
      rethrow;
    }
  }

  void setState(void Function() fn) {
    fn();
    notifyListeners();
  }

  Future<void> removeSharedDatabase(String databaseId) async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      await _collaborationService.deleteSharedDatabase(databaseId);
      await loadSharedDatabases();
    } catch (e) {
      print('Ошибка удаления совместной базы: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> leaveSharedDatabase(String databaseId) async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      await _collaborationService.leaveSharedDatabase(databaseId);
      await loadSharedDatabases();
    } catch (e) {
      print('Ошибка выхода из совместной базы: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> checkDatabaseExists(int databaseId) async {
    try {
      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/databases/$databaseId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> createNewDatabase() async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/databases'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при создании базы данных: ${response.statusCode}');
      }

      await loadDatabases();
    } catch (e) {
      print('Ошибка при создании базы данных: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadDatabase(BackupData backupData, String databaseId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/databases/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer ${_authProvider.token}',
          'Content-Type': 'application/json',
        },
        body: json.encode(backupData.toJson()),
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при загрузке базы данных: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки базы данных: $e');
      rethrow;
    }
  }

  Future<void> deleteDatabase(String databaseId, bool isOwner) async {
    try {
      if (isOwner) {
        // Если пользователь владелец - удаляем базу полностью
        final response = await http.delete(
          Uri.parse('$_baseUrl/databases/$databaseId'),
          headers: {
            'Authorization': 'Bearer ${_authProvider.token}',
          },
        );

        if (response.statusCode != 204) {
          throw Exception('Ошибка при удалении базы данных: ${response.statusCode}');
        }
      } else {
        // Если пользователь соавтор - удаляем только из списка соавторов
        final response = await http.post(
          Uri.parse('$_baseUrl/databases/$databaseId/leave'),
          headers: {
            'Authorization': 'Bearer ${_authProvider.token}',
          },
        );

        if (response.statusCode != 204) {
          throw Exception('Ошибка при выходе из базы данных: ${response.statusCode}');
        }
      }

      // Обновляем список баз данных
      await loadDatabases();
    } catch (e) {
      print('Ошибка при удалении/выходе из базы данных: $e');
      rethrow;
    }
  }

  Future<void> createDatabase(String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newDatabase = await _collaborationService.createSharedDatabase(name);
      _databases.add(newDatabase);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeDatabase(String databaseId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _collaborationService.deleteSharedDatabase(databaseId);
      _databases.removeWhere((db) => db.id == databaseId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importDatabase(String databaseId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('Начало импорта базы данных с ID: $databaseId');
      print('Токен пользователя: ${_authProvider.token}');
      
      final databases = await _collaborationService.importSharedDatabase(databaseId);
      _databases = databases;
      
      // Проверяем, что база действительно импортирована
      if (!_databases.any((db) => db.id == databaseId && db.collaborators.contains(_authProvider.user?.id))) {
        throw Exception('База данных не была импортирована корректно');
      }
      
      print('База данных успешно импортирована');
      print('Список баз обновлен, количество баз: ${_databases.length}');
      print('Список баз: ${_databases.map((db) => '${db.id}: ${db.name}').join(', ')}');
      
      _error = null;
    } catch (e) {
      print('Ошибка при импорте базы данных: $e');
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> leaveDatabase(String databaseId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _collaborationService.leaveSharedDatabase(databaseId);
      _databases.removeWhere((db) => db.id == databaseId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncSharedDatabase() async {
    if (!_isUsingSharedDatabase || _currentDatabaseId == null || _databaseProvider == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      // Создаем резервную копию текущего состояния
      final backupData = await _databaseProvider!.createBackup(_currentDatabaseId);
      
      // Отправляем изменения на сервер
      await _collaborationService.saveDatabaseBackup(_currentDatabaseId!, backupData);
      
      // Загружаем последние изменения с сервера
      final latestBackup = await _collaborationService.getDatabaseBackup(_currentDatabaseId!);
      
      // Применяем изменения
      await _replaceLocalDatabase(latestBackup, _currentDatabaseId);
      
      // Уведомляем о необходимости обновления данных
      _databaseProvider!.setNeedsUpdate(true);
    } catch (e) {
      print('Ошибка синхронизации совместной базы: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> joinSharedDatabase(String databaseId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _collaborationService.joinSharedDatabase(databaseId);
      await loadSharedDatabases();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncDatabase(SharedDatabase database) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _collaborationService.syncSharedDatabase(database);
      await loadSharedDatabases();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
} 