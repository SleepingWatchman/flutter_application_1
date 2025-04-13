import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'package:provider/provider.dart';
import '../models/shared_database.dart';
import '../models/shared_database_access.dart';
import '../services/shared_database_service.dart';

class CollaborationProvider extends ChangeNotifier {
  final AuthProvider _authProvider;
  final SharedDatabaseService _sharedDatabaseService;
  DatabaseProvider? _databaseProvider;
  List<SharedDatabase> _sharedDatabases = [];
  String? _currentDatabaseId;
  bool _isUsingSharedDatabase = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _databases = [];
  final String _baseUrl = 'http://127.0.0.1:5294/api/collaboration';

  CollaborationProvider(this._authProvider)
      : _sharedDatabaseService = SharedDatabaseService(_authProvider.authService);

  List<SharedDatabase> get sharedDatabases => _sharedDatabases;
  String? get currentDatabaseId => _currentDatabaseId;
  bool get isUsingSharedDatabase => _isUsingSharedDatabase;
  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get databases => _databases;

  void setDatabaseProvider(DatabaseProvider provider) {
    _databaseProvider = provider;
  }

  Future<void> loadSharedDatabases() async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      _sharedDatabases = await _sharedDatabaseService.getSharedDatabases();
    } catch (e) {
      print('Ошибка загрузки совместных баз: $e');
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
      
      await _sharedDatabaseService.createSharedDatabase(name);
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

      await _sharedDatabaseService.importSharedDatabase(databaseId);
      await loadSharedDatabases();
    } catch (e) {
      print('Ошибка импорта совместной базы: $e');
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

      _currentDatabaseId = databaseId;
      _isUsingSharedDatabase = true;
      // TODO: Реализовать переключение на совместную базу
    } catch (e) {
      print('Ошибка переключения на совместную базу: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchToPersonalDatabase() async {
    if (_databaseProvider == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      // TODO: Реализовать переключение на личную базу
    } catch (e) {
      print('Ошибка переключения на личную базу: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeSharedDatabase(String databaseId) async {
    if (_authProvider.user == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      await _sharedDatabaseService.deleteSharedDatabase(databaseId);
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

      await _sharedDatabaseService.leaveSharedDatabase(databaseId);
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

  Future<void> loadDatabases() async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/databases'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при загрузке списка баз данных: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      _databases = List<Map<String, dynamic>>.from(data);
      notifyListeners();
    } catch (e) {
      print('Ошибка при загрузке списка баз данных: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
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

  Future<Map<String, dynamic>> downloadDatabase(int databaseId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/databases/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при загрузке базы данных: ${response.statusCode}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      print('Ошибка при загрузке базы данных: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadDatabase(Map<String, dynamic> backupData, int databaseId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/databases/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(backupData),
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при загрузке базы данных на сервер: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка при загрузке базы данных на сервер: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> replaceLocalDatabase(Map<String, dynamic> backupData, int databaseId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/databases/$databaseId/replace'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(backupData),
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при замене данных в локальной базе: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка при замене данных в локальной базе: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
} 