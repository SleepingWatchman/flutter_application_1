import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shared_database.dart';
import '../db/database_helper.dart';
import 'auth_service.dart';
import '../models/backup_data.dart';
import 'package:dio/dio.dart';

/// Сервис для работы с совместными базами данных (коллаборация)
class CollaborationService {
  final AuthService _authService;
  final String _baseUrl = 'http://localhost:5294/api/shareddatabase';
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Dio _dio = Dio();

  CollaborationService(this._authService);

  String? _getToken() {
    return _authService.token;
  }

  Future<List<SharedDatabase>> getSharedDatabases() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      print('Получение списка общих баз данных...');
      print('Используемый токен: $token');

      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Статус ответа: ${response.statusCode}');
      print('Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => SharedDatabase.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при получении списка баз данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка в getSharedDatabases: $e');
      rethrow;
    }
  }

  Future<SharedDatabase> createSharedDatabase(String name) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'name': name,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return SharedDatabase.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при создании базы данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при создании базы данных: $e');
      rethrow;
    }
  }

  Future<List<SharedDatabase>> importSharedDatabase(String databaseId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/$databaseId/import'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => SharedDatabase.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при импорте базы данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при импорте базы данных: $e');
      rethrow;
    }
  }

  Future<void> deleteSharedDatabase(String databaseId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.delete(
        Uri.parse('$_baseUrl/$databaseId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 204) {
        return;
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при удалении базы данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при удалении базы данных: $e');
      rethrow;
    }
  }

  Future<void> joinSharedDatabase(String databaseId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/$databaseId/join'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final sharedDb = SharedDatabase.fromJson(data);
        await _dbHelper.switchToSharedDatabase(sharedDb);
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при присоединении к базе данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при присоединении к базе данных: $e');
      rethrow;
    }
  }

  Future<void> leaveSharedDatabase(String databaseId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/$databaseId/leave'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 204) {
        return;
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при выходе из базы данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при выходе из базы данных: $e');
      rethrow;
    }
  }

  Future<void> syncSharedDatabase(SharedDatabase database) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      // Получаем только измененные записи с последней синхронизации
      final lastSync = await _getLastSyncTime(database.id);
      final changes = await _dbHelper.getChangesSince(lastSync);
      
      if (changes.isEmpty) return;

      final response = await http.post(
        Uri.parse('$_baseUrl/${database.id}/sync'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'changes': changes,
          'lastSync': lastSync?.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        await _updateLastSyncTime(database.id);
        // Применяем изменения с сервера
        final data = json.decode(response.body);
        final serverChanges = data['changes'] as List;
        await _dbHelper.applyServerChanges(serverChanges);
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при синхронизации базы данных: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при синхронизации базы данных: $e');
      rethrow;
    }
  }

  Future<DateTime?> _getLastSyncTime(String databaseId) async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString('last_sync_$databaseId') ?? '');
  }

  Future<void> _updateLastSyncTime(String databaseId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_$databaseId', DateTime.now().toIso8601String());
  }

  Future<void> saveDatabaseBackup(String databaseId, BackupData backupData) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(backupData.toJson()),
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при сохранении резервной копии: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при сохранении резервной копии: $e');
      rethrow;
    }
  }

  Future<BackupData> getDatabaseBackup(String databaseId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/$databaseId/backup'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return BackupData.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Не авторизован');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка при получении резервной копии: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Ошибка при получении резервной копии: $e');
      rethrow;
    }
  }
} 