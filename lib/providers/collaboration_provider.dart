import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'package:provider/provider.dart';
import '../models/shared_database.dart';
import '../models/shared_database_access.dart';
import '../services/collaboration_service.dart';
import '../models/backup_data.dart';
import '../db/database_helper.dart';
import '../models/collaboration_database.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class CollaborationProvider with ChangeNotifier {
  final AuthProvider _authProvider;
  final CollaborationService _collaborationService;
  DatabaseProvider? _databaseProvider;
  List<SharedDatabase> _sharedDatabases = [];
  String? _currentDatabaseId;
  bool _isUsingSharedDatabase = false;
  bool _isLoading = false;
  List<SharedDatabase> _databases = [];
  final String _baseUrl = 'http://localhost:5294/api/collaboration';
  String? _error;
  List<CollaborationDatabase>? _collaborationDatabases;

  CollaborationProvider(this._authProvider)
      : _collaborationService = CollaborationService(_authProvider.authService);

  List<SharedDatabase> get sharedDatabases => _sharedDatabases;
  String? get currentDatabaseId => _currentDatabaseId;
  bool get isUsingSharedDatabase => _isUsingSharedDatabase;
  bool get isLoading => _isLoading;
  List<SharedDatabase> get databases => _databases;
  List<CollaborationDatabase>? get collaborationDatabases => _collaborationDatabases;
  String? get error => _error;

  void setDatabaseProvider(DatabaseProvider provider) {
    _databaseProvider = provider;
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
      _databases = await _collaborationService.getSharedDatabases();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createSharedDatabase(String name) async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      print('Создание совместной базы данных с именем: $name');
      print('Токен пользователя: ${_authProvider.token}');
      
      await _collaborationService.createSharedDatabase(name);
      print('Совместная база данных успешно создана');
      
      await loadSharedDatabases();
    } catch (e) {
      print('Ошибка создания совместной базы: $e');
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
      
      await _collaborationService.importSharedDatabase(databaseId);
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
    if (_databaseProvider == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      // Создаем резервную копию текущей базы
      await _databaseProvider!.createBackup();

      // Проверяем существование базы данных на сервере
      final response = await http.get(
        Uri.parse('$_baseUrl/shareddatabase/$databaseId'),
        headers: {
          'Authorization': 'Bearer ${_authProvider.token}',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('База данных не найдена на сервере');
      }

      // Загружаем данные совместной базы
      final backupData = await downloadDatabase(databaseId);
      
      // Заменяем локальную базу данными совместной базы
      await _replaceLocalDatabase(backupData);

      _currentDatabaseId = databaseId;
      _isUsingSharedDatabase = true;
      
      // Уведомляем о необходимости обновления данных
      _databaseProvider!.setNeedsUpdate(true);
      
      // Обновляем список баз
      await loadDatabases();
    } catch (e) {
      print('Ошибка переключения на совместную базу: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BackupData> downloadDatabase(String databaseId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/shareddatabase/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer ${_authProvider.token}',
        },
      );

      if (response.statusCode == 200) {
        return BackupData.fromJson(json.decode(response.body));
      } else {
        throw Exception('Ошибка при загрузке базы данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка загрузки базы данных: $e');
      rethrow;
    }
  }

  Future<void> _replaceLocalDatabase(BackupData backupData) async {
    try {
      await DatabaseHelper().replaceDatabase(backupData);
      notifyListeners();
    } catch (e) {
      print('Error replacing local database: $e');
      rethrow;
    }
  }

  Future<void> switchToPersonalDatabase() async {
    if (_databaseProvider == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      // Восстанавливаем личную базу из резервной копии
      await _databaseProvider!.restoreFromBackup();

      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      
      // Уведомляем о необходимости обновления данных
      _databaseProvider!.setNeedsUpdate(true);
      
      // Обновляем список баз
      await loadDatabases();
    } catch (e) {
      print('Ошибка переключения на личную базу: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
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
      
      // Импортируем базу и получаем обновленный список
      _databases = await _collaborationService.importSharedDatabase(databaseId);
      
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
      final backupData = await _databaseProvider!.createBackup();
      
      // Отправляем изменения на сервер
      await _collaborationService.saveDatabaseBackup(_currentDatabaseId!, backupData);
      
      // Загружаем последние изменения с сервера
      final latestBackup = await _collaborationService.getDatabaseBackup(_currentDatabaseId!);
      
      // Применяем изменения
      await _replaceLocalDatabase(latestBackup);
      
      // Уведомляем о необходимости обновления данных
      _databaseProvider!.setNeedsUpdate(true);
    } catch (e) {
      print('Ошибка синхронизации совместной базы: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
} 