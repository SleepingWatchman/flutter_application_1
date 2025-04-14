import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shared_database.dart';
import 'auth_service.dart';
import '../models/backup_data.dart';

/// Сервис для работы с совместными базами данных (коллаборация)
class CollaborationService {
  final String _baseUrl;
  final AuthService _authService;

  CollaborationService(this._authService, {String? baseUrl})
      : _baseUrl = baseUrl ?? 'http://localhost:5294/api';

  Future<List<SharedDatabase>> getSharedDatabases() async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    print('Запрос списка баз данных');
    print('URL: $_baseUrl/shareddatabase');
    print('Токен: $token');

    final response = await http.get(
      Uri.parse('$_baseUrl/shareddatabase'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Ответ сервера: ${response.statusCode}');
    print('Тело ответа: ${response.body}');

    if (response.statusCode == 200) {
      try {
        final List<dynamic> data = json.decode(response.body);
        print('Получено баз данных: ${data.length}');
        return data.map((json) => SharedDatabase.fromJson(json)).toList();
      } catch (e) {
        print('Ошибка при парсинге ответа: $e');
        throw Exception('Ошибка при получении списка баз: неверный формат ответа');
      }
    } else {
      print('Ошибка получения списка баз: ${response.statusCode} - ${response.body}');
      throw Exception('Ошибка загрузки совместных баз: ${response.statusCode}');
    }
  }

  Future<SharedDatabase> createSharedDatabase(String name) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    print('Создание совместной базы данных с именем: $name');
    print('URL: $_baseUrl/SharedDatabase');

    final response = await http.post(
      Uri.parse('$_baseUrl/SharedDatabase'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode({'name': name}),
    );

    print('Ответ сервера: ${response.statusCode}');
    print('Тело ответа: ${response.body}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      try {
        return SharedDatabase.fromJson(json.decode(response.body));
      } catch (e) {
        print('Ошибка при парсинге ответа: $e');
        throw Exception('Ошибка при создании совместной базы: неверный формат ответа');
      }
    } else {
      print('Ошибка создания совместной базы: ${response.statusCode} - ${response.body}');
      throw Exception('Ошибка создания совместной базы: ${response.statusCode}');
    }
  }

  Future<List<SharedDatabase>> importSharedDatabase(String databaseId) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    print('Импорт базы данных с ID: $databaseId');
    print('URL: $_baseUrl/shareddatabase/$databaseId/import');

    final response = await http.post(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId/import'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Ответ сервера: ${response.statusCode}');
    print('Тело ответа: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('Ошибка импорта совместной базы: ${response.statusCode} - ${response.body}');
    }

    // Проверяем успешность импорта
    final importedDatabase = SharedDatabase.fromJson(json.decode(response.body));
    if (!importedDatabase.collaborators.contains(_authService.currentUser?.id)) {
      throw Exception('Ошибка импорта: пользователь не добавлен в список коллабораторов');
    }

    // После успешного импорта получаем обновленный список баз данных
    print('Получение обновленного списка баз после импорта...');
    final databases = await getSharedDatabases();
    print('Получено баз после импорта: ${databases.length}');
    return databases;
  }

  Future<void> deleteSharedDatabase(String databaseId) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.delete(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      print('Ошибка удаления совместной базы: ${response.statusCode} - ${response.body}');
      throw Exception('Ошибка удаления совместной базы: ${response.statusCode}');
    }
  }

  Future<void> leaveSharedDatabase(String databaseId) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.post(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId/leave'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 204) {
      throw Exception('Ошибка выхода из совместной базы');
    }
  }

  Future<void> saveDatabaseBackup(String databaseId, BackupData backupData) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.post(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId/backup'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(backupData.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка сохранения резервной копии: ${response.statusCode}');
    }
  }

  Future<BackupData> getDatabaseBackup(String databaseId) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.get(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId/backup'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return BackupData.fromJson(json.decode(response.body));
    } else {
      throw Exception('Ошибка получения резервной копии: ${response.statusCode}');
    }
  }
} 