import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_provider.dart';

class CollaborationProvider with ChangeNotifier {
  final AuthProvider _authProvider;
  bool _isLoading = false;
  List<Map<String, dynamic>> _databases = [];
  final String _baseUrl = 'http://127.0.0.1:5294/api/collaboration';

  CollaborationProvider(this._authProvider);

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get databases => _databases;

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

      // После создания новой базы данных, обновляем список
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

  Future<void> uploadDatabase(int databaseId, Map<String, dynamic> backupData) async {
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
} 