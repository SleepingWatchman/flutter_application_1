import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shared_database.dart';
import 'auth_service.dart';

class SharedDatabaseService {
  final String _baseUrl;
  final AuthService _authService;

  SharedDatabaseService(this._authService, {String? baseUrl})
      : _baseUrl = baseUrl ?? 'http://localhost:5294/api';

  Future<List<SharedDatabase>> getSharedDatabases() async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.get(
      Uri.parse('$_baseUrl/shareddatabase'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => SharedDatabase.fromJson(json)).toList();
    } else {
      throw Exception('Ошибка загрузки совместных баз');
    }
  }

  Future<SharedDatabase> createSharedDatabase(String name) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.post(
      Uri.parse('$_baseUrl/SharedDatabase'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode({'name': name}),
    );

    if (response.statusCode == 201) {
      return SharedDatabase.fromJson(json.decode(response.body));
    } else {
      print('Ошибка создания совместной базы: ${response.statusCode} - ${response.body}');
      throw Exception('Ошибка создания совместной базы: ${response.statusCode}');
    }
  }

  Future<void> importSharedDatabase(String databaseId) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.post(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId/import'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка импорта совместной базы');
    }
  }

  Future<void> deleteSharedDatabase(String databaseId) async {
    final token = _authService.token;
    if (token == null) throw Exception('Не авторизован');

    final response = await http.delete(
      Uri.parse('$_baseUrl/shareddatabase/$databaseId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 204) {
      throw Exception('Ошибка удаления совместной базы');
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
} 