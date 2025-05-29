import 'package:flutter/material.dart';
import 'dart:async';
import '../models/enhanced_collaborative_database.dart';
import '../models/collaborative_database_role.dart';
import '../services/collaborative_role_service.dart';
import '../services/enhanced_sync_service.dart';
import '../services/auth_service.dart';
import '../db/database_helper.dart';
import 'database_provider.dart';
import 'package:oktoast/oktoast.dart';
import 'package:dio/dio.dart';

class EnhancedCollaborativeProvider extends ChangeNotifier {
  final CollaborativeRoleService _roleService;
  final EnhancedSyncService _syncService;
  final AuthService _authService;
  final DatabaseHelper _dbHelper;
  final Dio _dio;
  
  DatabaseProvider? _databaseProvider;
  List<EnhancedCollaborativeDatabase> _databases = [];
  String? _currentDatabaseId;
  bool _isLoading = false;
  String? _error;
  bool _isUsingSharedDatabase = false;
  bool _isServerAvailable = false;
  bool _isServerOnline = false;
  
  // Защита от повторных операций
  bool _isSwitchingDatabase = false;
  bool _isSyncing = false;
  
  // Синхронизация
  SyncStatus _syncStatus = SyncStatus.idle;
  List<SyncConflict> _pendingConflicts = [];
  
  // Роли и пользователи
  Map<String, List<CollaborativeDatabaseUser>> _databaseUsers = {};
  Map<String, CollaborativeDatabaseRole?> _userRoles = {};
  Map<String, Map<String, bool>> _permissions = {};
  
  // Приглашения
  List<Map<String, dynamic>> _pendingInvitations = [];
  
  StreamSubscription<SyncResult>? _syncResultSubscription;
  StreamSubscription<SyncStatus>? _syncStatusSubscription;

  EnhancedCollaborativeProvider(
    this._roleService,
    this._syncService,
    this._authService,
    this._dbHelper,
    this._dio,
  ) {
    // Настраиваем Dio
    _dio.options.baseUrl = 'http://localhost:8080';
    _dio.options.connectTimeout = Duration(seconds: 5);
    _dio.options.receiveTimeout = Duration(seconds: 15);
    _dio.options.sendTimeout = Duration(seconds: 15);
    
    // Добавляем интерцептор для авторизации
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _authService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException error, handler) {
        print('Ошибка запроса к серверу: ${error.message}');
        if (error.response?.statusCode == 401) {
          // Токен истек, нужно обновить авторизацию
          _authService.signOut();
        }
        return handler.next(error);
      },
    ));
    
    _initializeSubscriptions();
    _initServerHealthCheck();
  }

  // Геттеры
  List<EnhancedCollaborativeDatabase> get databases => _databases;
  String? get currentDatabaseId => _currentDatabaseId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isUsingSharedDatabase => _isUsingSharedDatabase;
  bool get isServerAvailable => _isServerAvailable;
  SyncStatus get syncStatus => _syncStatus;
  List<SyncConflict> get pendingConflicts => _pendingConflicts;
  List<Map<String, dynamic>> get pendingInvitations => _pendingInvitations;

  void setDatabaseProvider(DatabaseProvider provider) {
    _databaseProvider = provider;
  }

  void _initializeSubscriptions() {
    _syncResultSubscription = _syncService.syncResults.listen((result) {
      _syncStatus = result.status;
      _pendingConflicts = result.conflicts;
      
      if (result.status == SyncStatus.error && result.error != null) {
        _error = result.error;
        showToast('Ошибка синхронизации: ${result.error}');
      } else if (result.status == SyncStatus.success) {
        showToast('Синхронизация завершена успешно');
        _databaseProvider?.notifyListeners();
      } else if (result.status == SyncStatus.conflict) {
        showToast('Обнаружены конфликты синхронизации');
      }
      
      notifyListeners();
    });

    _syncStatusSubscription = _syncService.syncStatus.listen((status) {
      _syncStatus = status;
      notifyListeners();
    });
  }

  Future<void> _initServerHealthCheck() async {
    Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        final wasAvailable = _isServerAvailable;
        _isServerAvailable = await _checkServerHealth();
        
        if (wasAvailable != _isServerAvailable) {
          notifyListeners();
          if (_isServerAvailable) {
            showToast('Соединение с сервером восстановлено');
          } else {
            showToast('Соединение с сервером потеряно');
          }
        }
      } catch (e) {
        print('Ошибка проверки состояния сервера: $e');
      }
    });
  }

  Future<bool> _checkServerHealth() async {
    try {
      final response = await _dio.get('/api/Service/status');
      _isServerOnline = response.statusCode == 200;
    } catch (e) {
      _isServerOnline = false;
      print('Ошибка проверки состояния сервера: $e');
    }
    return _isServerOnline;
  }

  Future<void> loadDatabases() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Загружаем базы данных
      final databases = await _loadDatabasesFromServer();
      _databases = databases;
      
      // Загружаем пользователей для каждой базы
      for (final db in _databases) {
        await _loadDatabaseUsers(db.id);
        await _loadUserRole(db.id);
        await _loadPermissions(db.id);
      }
      
      // Загружаем приглашения
      await _loadPendingInvitations();
      
    } catch (e) {
      _error = e.toString();
      print('Ошибка при загрузке баз данных: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<EnhancedCollaborativeDatabase>> _loadDatabasesFromServer() async {
    try {
      final response = await _dio.get('/api/collaboration/databases');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => EnhancedCollaborativeDatabase.fromJson(json)).toList();
      }
      
      throw Exception('Ошибка при загрузке баз данных: ${response.statusCode}');
    } catch (e) {
      print('Ошибка в _loadDatabasesFromServer: $e');
      rethrow;
    }
  }

  Future<void> _loadDatabaseUsers(String databaseId) async {
    try {
      final users = await getDatabaseUsers(databaseId);
      _databaseUsers[databaseId] = users;
    } catch (e) {
      print('Ошибка загрузки пользователей для базы $databaseId: $e');
    }
  }

  Future<void> _loadUserRole(String databaseId) async {
    try {
      final role = await _roleService.getCurrentUserRole(databaseId);
      _userRoles[databaseId] = role;
    } catch (e) {
      print('Ошибка загрузки роли для базы $databaseId: $e');
    }
  }

  Future<void> _loadPermissions(String databaseId) async {
    try {
      final permissions = await _roleService.checkPermissions(databaseId);
      _permissions[databaseId] = permissions;
    } catch (e) {
      print('Ошибка загрузки разрешений для базы $databaseId: $e');
    }
  }

  Future<void> _loadPendingInvitations() async {
    try {
      _pendingInvitations = await _roleService.getPendingInvitations();
    } catch (e) {
      print('Ошибка загрузки приглашений: $e');
    }
  }

  Future<void> createDatabase(String name) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Создаем базу данных на сервере
      final newDatabase = await _createDatabaseOnServer(name);
      _databases.add(newDatabase);
      
      // Инициализируем локальную копию
      await _dbHelper.initializeSharedDatabase(newDatabase.id);
      
      // Автоматически переключаемся на новую базу
      await switchToDatabase(newDatabase.id);
      
    } catch (e) {
      _error = e.toString();
      print('Ошибка при создании базы данных: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<EnhancedCollaborativeDatabase> _createDatabaseOnServer(String name) async {
    try {
      final response = await _dio.post(
        '/api/collaboration/databases',
        data: {
          'name': name,
        },
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return EnhancedCollaborativeDatabase.fromJson(response.data);
      }
      
      throw Exception('Ошибка при создании базы данных: ${response.statusCode}');
    } catch (e) {
      print('Ошибка в _createDatabaseOnServer: $e');
      rethrow;
    }
  }

  Future<void> switchToDatabase(String databaseId) async {
    // Защита от повторного переключения на ту же базу
    if (_currentDatabaseId == databaseId && _isUsingSharedDatabase) {
      print('База данных $databaseId уже активна, пропускаем переключение');
      return;
    }
    
    // Защита от параллельных операций переключения
    if (_isSwitchingDatabase) {
      print('Операция переключения базы данных уже выполняется, пропускаем');
      return;
    }
    
    try {
      _isSwitchingDatabase = true;
      _isLoading = true;
      _error = null;
      
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Устанавливаем флаги НЕМЕДЛЕННО
      _currentDatabaseId = databaseId;
      _isUsingSharedDatabase = true;
      
      // Уведомляем об изменении СРАЗУ
      notifyListeners();

      print('Переключение на базу данных: $databaseId');
      
      // ИСПРАВЛЕНИЕ: ВСЕГДА сохраняем личные данные при переключении на совместную базу
      try {
        if (_databaseProvider != null) {
          print('Создание резервной копии личных данных перед переключением...');
          final personalBackup = await _databaseProvider!.createBackup(null);
          await _databaseProvider!.savePersonalBackup(personalBackup);
          print('Личные данные сохранены в резервную копию');
        }
      } catch (e) {
        print('Ошибка сохранения личных данных: $e');
        // Не прерываем процесс
      }
      
      // ИСПРАВЛЕНИЕ: Быстрое закрытие и переоткрытие базы
      try {
        await _dbHelper.closeDatabase();
        print('База данных закрыта');
        
        // УБИРАЕМ длительную задержку
        await Future.delayed(Duration(milliseconds: 100));
        
        // Принудительно очищаем кеш
        await _dbHelper.clearCache();
        print('Кеш очищен');
      } catch (e) {
        print('Предупреждение при закрытии базы: $e');
      }
      
      // ИСПРАВЛЕНИЕ: Настраиваем синхронизацию ДО инициализации
      _syncService.setCurrentDatabase(databaseId);
      
      // ИСПРАВЛЕНИЕ: Упрощенная инициализация БЕЗ долгих транзакций
      print('Инициализация совместной базы данных: $databaseId');
      try {
        // Инициализируем базу в DatabaseHelper напрямую
        await _dbHelper.initializeSharedDatabase(databaseId);
        print('Совместная база данных инициализирована в DatabaseHelper');
      } catch (e) {
        print('Ошибка инициализации в DatabaseHelper: $e');
        // Продолжаем работу даже при ошибке
      }
      
      // ИСПРАВЛЕНИЕ: Устанавливаем базу в DatabaseProvider БЕЗ повторных операций
      if (_databaseProvider != null) {
        try {
          await _databaseProvider!.switchToDatabase(databaseId);
          print('DatabaseProvider настроен для базы $databaseId');
        } catch (e) {
          print('Ошибка настройки DatabaseProvider: $e');
        }
      }
      
      // ИСПРАВЛЕНИЕ: Проверяем статус сервера БЕЗ блокирующих операций
      _checkServerHealth().then((available) {
        _isServerAvailable = available;
        if (available) {
          print('Сервер доступен после переключения на совместную базу');
        } else {
          print('Предупреждение: Сервер недоступен после переключения на совместную базу');
        }
        notifyListeners();
      }).catchError((e) {
        print('Ошибка проверки статуса сервера: $e');
      });
      
      print('Переключение на базу данных $databaseId завершено успешно');
      
    } catch (e) {
      _error = e.toString();
      print('Ошибка при переключении на базу данных: $e');
    } finally {
      _isSwitchingDatabase = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchToPersonalDatabase() async {
    // Защита от повторного переключения на личную базу
    if (!_isUsingSharedDatabase && _currentDatabaseId == null) {
      print('Личная база данных уже активна, пропускаем переключение');
      return;
    }
    
    // Защита от параллельных операций переключения
    if (_isSwitchingDatabase) {
      print('Операция переключения базы данных уже выполняется, пропускаем');
      return;
    }
    
    try {
      _isSwitchingDatabase = true;
      _isLoading = true;
      _error = null;
      
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Устанавливаем флаги НЕМЕДЛЕННО
      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Останавливаем синхронизацию ДО переключения
      _syncService.setCurrentDatabase(null);
      print('Сервис синхронизации остановлен для личной базы');
      
      // Уведомляем об изменении СРАЗУ один раз
      notifyListeners();
      
      print('Переключение на личную базу данных');
      
      // Очищаем кеш
      await _dbHelper.clearCache();
      print('Кеш очищен');
      
      // Инициализируем личную базу
      await _dbHelper.database; // Просто получаем базу
      print('Личная база данных инициализирована');
      
      // Уведомляем DatabaseProvider о переключении
      if (_databaseProvider != null) {
        await _databaseProvider!.switchToDatabase(null);
        print('DatabaseProvider переключен на личную базу');
      }
      
      // ИСПРАВЛЕНИЕ: УБИРАЕМ автоматическое восстановление из резервной копии
      // Это вызывало вторую синхронизацию с пустыми данными
      print('Переключение на личную базу завершено без восстановления данных');
      
    } catch (e) {
      _error = e.toString();
      print('Ошибка при переключении на личную базу данных: $e');
    } finally {
      _isSwitchingDatabase = false;
      _isLoading = false;
      // ИСПРАВЛЕНИЕ: Финальное уведомление только один раз
      notifyListeners();
    }
  }

  // Методы для работы с пользователями
  Future<void> inviteUser(String databaseId, String email, CollaborativeDatabaseRole role) async {
    try {
      await _roleService.inviteUser(databaseId, email, role);
      await _loadDatabaseUsers(databaseId);
      showToast('Приглашение отправлено');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка отправки приглашения: $e');
      notifyListeners();
    }
  }

  Future<void> updateUserRole(String databaseId, String userId, CollaborativeDatabaseRole newRole) async {
    try {
      await _roleService.updateUserRole(databaseId, userId, newRole);
      await _loadDatabaseUsers(databaseId);
      showToast('Роль пользователя обновлена');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка обновления роли: $e');
      notifyListeners();
    }
  }

  Future<void> removeUser(String databaseId, String userId) async {
    try {
      await _roleService.removeUser(databaseId, userId);
      await _loadDatabaseUsers(databaseId);
      showToast('Пользователь удален из базы данных');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка удаления пользователя: $e');
      notifyListeners();
    }
  }

  Future<void> leaveDatabase(String databaseId) async {
    try {
      await _roleService.leaveDatabase(databaseId);
      _databases.removeWhere((db) => db.id == databaseId);
      
      if (_currentDatabaseId == databaseId) {
        await switchToPersonalDatabase();
      }
      
      showToast('Вы покинули базу данных');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка при выходе из базы данных: $e');
      notifyListeners();
    }
  }

  Future<void> deleteDatabase(String databaseId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _dio.delete('/api/collaboration/databases/$databaseId');
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        _databases.removeWhere((db) => db.id == databaseId);
        
        if (_currentDatabaseId == databaseId) {
          await switchToPersonalDatabase();
        }
        
        showToast('База данных удалена');
      } else {
        throw Exception('Ошибка при удалении базы данных: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка удаления базы данных: $e');
      print('Ошибка в deleteDatabase: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Методы для работы с приглашениями
  Future<void> acceptInvitation(String invitationId) async {
    try {
      await _roleService.acceptInvitation(invitationId);
      await loadDatabases(); // Перезагружаем все данные
      showToast('Приглашение принято');
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка принятия приглашения: $e');
      notifyListeners();
    }
  }

  Future<void> declineInvitation(String invitationId) async {
    try {
      await _roleService.declineInvitation(invitationId);
      await _loadPendingInvitations();
      showToast('Приглашение отклонено');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка отклонения приглашения: $e');
      notifyListeners();
    }
  }

  // Методы для работы с синхронизацией
  Future<void> syncDatabase() async {
    if (_currentDatabaseId == null || !_isUsingSharedDatabase) {
      print('Синхронизация невозможна: нет активной совместной базы данных');
      return;
    }
    
    // Защита от параллельных операций синхронизации
    if (_isSyncing) {
      print('Операция синхронизации уже выполняется, пропускаем');
      return;
    }
    
    try {
      _isSyncing = true;
      print('Начинаем ручную синхронизацию базы данных: $_currentDatabaseId');
      
      await _syncService.forceSync();
      
      // Уведомляем о необходимости обновления данных
      if (_databaseProvider != null) {
        _databaseProvider!.setNeedsUpdate(true);
      }
      
      showToast('Синхронизация завершена успешно');
      print('Ручная синхронизация завершена успешно');
      
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка синхронизации: $e');
      print('Ошибка ручной синхронизации: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> resolveConflict(SyncConflict conflict, bool useLocal) async {
    try {
      await _syncService.resolveConflict(conflict, useLocal);
      _pendingConflicts.removeWhere((c) => c.id == conflict.id);
      showToast('Конфликт разрешен');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showToast('Ошибка разрешения конфликта: $e');
      notifyListeners();
    }
  }

  // Вспомогательные методы
  Future<List<CollaborativeDatabaseUser>> getDatabaseUsers(String databaseId) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        throw Exception('Пользователь не авторизован');
      }

      final users = await _roleService.getDatabaseUsers(databaseId);
      return users;
    } catch (e) {
      print('Ошибка получения пользователей БД: $e');
      rethrow;
    }
  }

  CollaborativeDatabaseRole? getUserRole(String databaseId) {
    return _userRoles[databaseId];
  }

  Map<String, bool> getPermissions(String databaseId) {
    return _permissions[databaseId] ?? {};
  }

  bool canEdit(String databaseId) {
    return getPermissions(databaseId)['canEdit'] ?? false;
  }

  bool canManageUsers(String databaseId) {
    return getPermissions(databaseId)['canManageUsers'] ?? false;
  }

  bool canDelete(String databaseId) {
    return getPermissions(databaseId)['canDelete'] ?? false;
  }

  @override
  void dispose() {
    _syncResultSubscription?.cancel();
    _syncStatusSubscription?.cancel();
    _syncService.dispose();
    super.dispose();
  }
} 