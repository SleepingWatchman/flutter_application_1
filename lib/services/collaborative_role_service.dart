import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import '../models/collaborative_database_role.dart';
import '../models/enhanced_collaborative_database.dart';
import 'auth_service.dart';
import 'dart:async';

class CollaborativeRoleService {
  final AuthService _authService;
  final String _baseUrl;
  final Dio dio;

  CollaborativeRoleService(this._authService)
      : _baseUrl = 'http://localhost:8080/api/collaboration',
        dio = Dio() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _authService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException error, handler) {
        print('Ошибка запроса к серверу управления ролями: ${error.message}');
        return handler.next(error);
      }
    ));
    
    dio.options.connectTimeout = Duration(seconds: 5);
    dio.options.receiveTimeout = Duration(seconds: 15);
    dio.options.sendTimeout = Duration(seconds: 15);
  }

  /// Получить список пользователей в совместной базе данных
  Future<List<CollaborativeDatabaseUser>> getDatabaseUsers(String databaseId) async {
    try {
      final response = await dio.get('$_baseUrl/databases/$databaseId/users');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => CollaborativeDatabaseUser.fromJson(json)).toList();
      }
      
      throw Exception('Ошибка при получении списка пользователей: ${response.statusCode}');
    } catch (e) {
      print('Ошибка в getDatabaseUsers: $e');
      rethrow;
    }
  }

  /// Пригласить пользователя в совместную базу данных
  Future<void> inviteUser(String databaseId, String userEmail, CollaborativeDatabaseRole role) async {
    try {
      final response = await dio.post(
        '$_baseUrl/databases/$databaseId/invite',
        data: {
          'email': userEmail,
          'role': role.value,
        },
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Ошибка при приглашении пользователя: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в inviteUser: $e');
      rethrow;
    }
  }

  /// Добавить пользователя по ID
  Future<void> addUserById(String databaseId, String userId, CollaborativeDatabaseRole role) async {
    try {
      final response = await dio.post(
        '$_baseUrl/databases/$databaseId/users',
        data: {
          'user_id': int.parse(userId),
          'role': role.value,
        },
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Ошибка при добавлении пользователя: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в addUserById: $e');
      rethrow;
    }
  }

  /// Изменить роль пользователя
  Future<void> updateUserRole(String databaseId, String userId, CollaborativeDatabaseRole newRole) async {
    try {
      final response = await dio.put(
        '$_baseUrl/databases/$databaseId/users/$userId',
        data: {
          'role': newRole.value,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при изменении роли пользователя: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в updateUserRole: $e');
      rethrow;
    }
  }

  /// Удалить пользователя из совместной базы данных
  Future<void> removeUser(String databaseId, String userId) async {
    try {
      final response = await dio.delete('$_baseUrl/databases/$databaseId/users/$userId');

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Ошибка при удалении пользователя: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в removeUser: $e');
      rethrow;
    }
  }

  /// Покинуть совместную базу данных
  Future<void> leaveDatabase(String databaseId) async {
    try {
      final response = await dio.post('$_baseUrl/databases/$databaseId/leave');

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Ошибка при выходе из базы данных: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в leaveDatabase: $e');
      rethrow;
    }
  }

  /// Получить роль текущего пользователя в базе данных
  Future<CollaborativeDatabaseRole?> getCurrentUserRole(String databaseId) async {
    try {
      final response = await dio.get('$_baseUrl/databases/$databaseId/my-role');
      
      if (response.statusCode == 200) {
        final roleString = response.data['role'] as String?;
        if (roleString != null) {
          return CollaborativeDatabaseRole.fromString(roleString);
        }
      }
      
      return null;
    } catch (e) {
      print('Ошибка в getCurrentUserRole: $e');
      return null;
    }
  }

  /// Проверить права доступа пользователя
  Future<Map<String, bool>> checkPermissions(String databaseId) async {
    try {
      final response = await dio.get('$_baseUrl/databases/$databaseId/permissions');
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return {
          'canEdit': data['can_edit'] as bool? ?? false,
          'canDelete': data['can_delete'] as bool? ?? false,
          'canManageUsers': data['can_manage_users'] as bool? ?? false,
          'canInviteUsers': data['can_invite_users'] as bool? ?? false,
          'canLeave': data['can_leave'] as bool? ?? false,
        };
      }
      
      return {
        'canEdit': false,
        'canDelete': false,
        'canManageUsers': false,
        'canInviteUsers': false,
        'canLeave': false,
      };
    } catch (e) {
      print('Ошибка в checkPermissions: $e');
      return {
        'canEdit': false,
        'canDelete': false,
        'canManageUsers': false,
        'canInviteUsers': false,
        'canLeave': false,
      };
    }
  }

  /// Найти пользователя по email
  Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    try {
      final response = await dio.get('$_baseUrl/users/search?email=$email');
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>?;
      }
      
      return null;
    } catch (e) {
      print('Ошибка в findUserByEmail: $e');
      return null;
    }
  }

  /// Получить приглашения для текущего пользователя
  Future<List<Map<String, dynamic>>> getPendingInvitations() async {
    try {
      final response = await dio.get('$_baseUrl/invitations');
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } catch (e) {
      print('Ошибка в getPendingInvitations: $e');
      return [];
    }
  }

  /// Принять приглашение
  Future<void> acceptInvitation(String invitationId) async {
    try {
      final response = await dio.post('$_baseUrl/invitations/$invitationId/accept');

      if (response.statusCode != 200) {
        throw Exception('Ошибка при принятии приглашения: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в acceptInvitation: $e');
      rethrow;
    }
  }

  /// Отклонить приглашение
  Future<void> declineInvitation(String invitationId) async {
    try {
      final response = await dio.post('$_baseUrl/invitations/$invitationId/decline');

      if (response.statusCode != 200) {
        throw Exception('Ошибка при отклонении приглашения: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в declineInvitation: $e');
      rethrow;
    }
  }

  /// Получить статистику по базе данных
  Future<Map<String, dynamic>> getDatabaseStats(String databaseId) async {
    try {
      final response = await dio.get('$_baseUrl/databases/$databaseId/stats');
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      
      return {};
    } catch (e) {
      print('Ошибка в getDatabaseStats: $e');
      return {};
    }
  }
} 