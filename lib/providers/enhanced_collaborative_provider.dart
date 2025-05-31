import 'package:flutter/material.dart';
import 'dart:async';
import '../models/enhanced_collaborative_database.dart';
import '../models/collaborative_database_role.dart';
import '../services/collaborative_role_service.dart';
import '../services/enhanced_sync_service.dart';
import '../services/auth_service.dart';
import '../services/server_health_service.dart';
import '../db/database_helper.dart';
import '../utils/toast_utils.dart';
import 'database_provider.dart';
import 'package:oktoast/oktoast.dart';
import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';

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
  
  // Защита от повторных операций
  bool _isSwitchingDatabase = false;
  bool _isSyncing = false;
  
  // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Защита от автоматической синхронизации после переключения базы
  bool _isJustSwitchedToSharedDatabase = false;
  DateTime? _lastDatabaseSwitchTime;
  
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
        showCustomToastWithIcon(
          'Ошибка синхронизации: ${result.error}',
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
      } else if (result.status == SyncStatus.success) {
        showCustomToastWithIcon(
          'Синхронизация завершена успешно',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
        _databaseProvider?.notifyListeners();
      } else if (result.status == SyncStatus.conflict) {
        showCustomToastWithIcon(
          'Обнаружены конфликты синхронизации',
          accentColor: Colors.orange,
          fontSize: 14.0,
          icon: const Icon(Icons.warning, size: 20, color: Colors.orange),
        );
      }
      
      notifyListeners();
    });

    _syncStatusSubscription = _syncService.syncStatus.listen((status) {
      _syncStatus = status;
      notifyListeners();
    });
  }

  Future<void> _initServerHealthCheck() async {
    // Используем ServerHealthService вместо собственной реализации
    final serverHealthService = ServerHealthService();
    
    // Добавляем слушатель изменений статуса сервера
    serverHealthService.addStatusListener((status) {
      final wasAvailable = _isServerAvailable;
      _isServerAvailable = status == ServerStatus.online;
      
      // Уведомляем об изменении только если статус действительно изменился
      if (wasAvailable != _isServerAvailable) {
        notifyListeners();
        print('🏥 HEALTH: Статус сервера изменен в EnhancedCollaborativeProvider: ${_isServerAvailable ? "Онлайн" : "Офлайн"}');
      }
    });
    
    // Устанавливаем начальный статус
    _isServerAvailable = serverHealthService.isOnline;
    
    print('🏥 HEALTH: EnhancedCollaborativeProvider интегрирован с ServerHealthService');
  }

  Future<void> loadDatabases() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Загружаем базы данных
      final databases = await _loadDatabasesFromServer();
      _databases = databases;
      
      // ✅ ИСПРАВЛЕНИЕ: Загружаем пользователей для каждой базы и обновляем модели
      for (int i = 0; i < _databases.length; i++) {
        final db = _databases[i];
        await _loadDatabaseUsers(db.id);
        await _loadUserRole(db.id);
        await _loadPermissions(db.id);
        
        // Обновляем модель базы данных с загруженными пользователями
        final users = _databaseUsers[db.id] ?? [];
        _databases[i] = db.copyWith(users: users);
        print('✅ Загружено ${users.length} пользователей для базы ${db.name} (${db.id})');
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
      notifyListeners();

      print('Переключение на базу данных: $databaseId');
      
      // ИСПРАВЛЕНИЕ: Выполняем все операции в background
      await _performDatabaseSwitch(databaseId);
      
      print('✅ Переключение на совместную базу $databaseId завершено успешно');
      
      // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Принудительное обновление UI в самом конце
      print('ШАГ 5: Принудительное обновление экрана заметок...');
      if (_databaseProvider != null) {
        // Устанавливаем флаг принудительного обновления
        _databaseProvider!.setNeedsUpdate(true);
        _databaseProvider!.notifyUpdate();
        print('✅ Экран заметок принудительно обновлен');
      }
      
    } catch (e) {
      _error = e.toString();
      print('❌ Ошибка при переключении на базу данных: $e');
      
      // Откатываем флаги при ошибке
      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      _syncService.setCurrentDatabase(null);
    } finally {
      _isSwitchingDatabase = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ИСПРАВЛЕНИЕ: Выносим тяжелые операции в отдельный метод без notifyListeners
  Future<void> _performDatabaseSwitch(String databaseId) async {
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Блокируем ВСЕ операции с базой данных во время переключения
    if (_databaseProvider != null) {
      print('🚫 БЛОКИРОВКА: Блокируем все операции с базой данных на время переключения');
      _databaseProvider!.setIsBlocked(true);
    }
    
    try {
      // ШАГ 1: Отправка бэкапа пользовательских данных (БЫСТРО)
      if (_databaseProvider != null) {
        print('ШАГ 1: Создание и сохранение резервной копии личных данных...');
        try {
          final personalBackup = await _databaseProvider!.createBackup(null);
          await _databaseProvider!.savePersonalBackup(personalBackup);
          print('✅ Личные данные успешно сохранены в резервную копию');
        } catch (e) {
          print('❌ Ошибка сохранения личных данных: $e');
          throw Exception('Не удалось сохранить личные данные: $e');
        }
      }
      
      // ШАГ 2: ИСПРАВЛЕНИЕ - БЫСТРАЯ очистка только кеша, БЕЗ очистки таблиц базы данных
      print('ШАГ 2: Очистка только кеша локальной базы данных...');
      try {
        await _dbHelper.closeDatabase();
        await _dbHelper.clearCache();
        
        // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Очищаем кеш изображений Flutter
        print('ШАГ 2.1: Очистка кеша изображений Flutter...');
        try {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          print('✅ Кеш изображений Flutter очищен');
        } catch (e) {
          print('⚠️ Ошибка при очистке кеша изображений Flutter: $e');
        }
        
        print('✅ Кеш базы данных очищен');
      } catch (e) {
        print('❌ Ошибка при очистке кеша: $e');
        // Продолжаем, это не критично
      }
      
      // Устанавливаем флаги
      _currentDatabaseId = databaseId;
      _isUsingSharedDatabase = true;
      _syncService.setCurrentDatabase(databaseId);
      
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Устанавливаем защиту от автоматической синхронизации
      _isJustSwitchedToSharedDatabase = true;
      _lastDatabaseSwitchTime = DateTime.now();
      print('🛡️ ЗАЩИТА: Синхронизация заблокирована на 30 секунд после переключения на совместную базу');
      
      // Инициализируем совместную базу (БЕЗ UI БЛОКИРОВКИ)
      print('ШАГ 3: Инициализация совместной базы данных: $databaseId');
      await _dbHelper.initializeSharedDatabase(databaseId);
      
      if (_databaseProvider != null) {
        await _databaseProvider!.switchToDatabase(databaseId);
      }
         
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Разблокируем операции ПЕРЕД импортом данных
      if (_databaseProvider != null) {
        print('✅ РАЗБЛОКИРОВКА: Разрешаем операции с базой данных перед импортом');
        _databaseProvider!.setIsBlocked(false);
      }
      
      // ШАГ 4: ЗАГРУЗКА данных совместной базы С сервера (В BACKGROUND, БЕЗ БЛОКИРОВКИ)
      print('ШАГ 4: Загрузка данных совместной базы с сервера...');
      await _loadDataFromServerInBackground(databaseId);
      
    } catch (e) {
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Разблокируем операции в случае ошибки
      if (_databaseProvider != null) {
        print('❌ РАЗБЛОКИРОВКА: Разрешаем операции при ошибке: $e');
        _databaseProvider!.setIsBlocked(false);
      }
      rethrow;
    }
  }

  // ИСПРАВЛЕНИЕ: Отдельный метод для загрузки данных без блокировки UI
  Future<void> _loadDataFromServerInBackground(String databaseId) async {
    try {
      // ИСПРАВЛЕНИЕ: Устанавливаем блокировку загрузки данных экранами
      if (_databaseProvider != null) {
        _databaseProvider!.setIsBlocked(true);
        print('🚫 БЛОКИРОВКА: Экраны заблокированы на время загрузки данных с сервера');
      }
      
      final token = await _authService.getToken();
      if (token != null) {
        final response = await _dio.get(
          '/api/collaboration/databases/$databaseId/data',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            validateStatus: (status) => status != null && status < 500,
            receiveTimeout: Duration(seconds: 10), // ИСПРАВЛЕНИЕ: Добавляем timeout
            sendTimeout: Duration(seconds: 10),
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final serverData = response.data;
          print('✅ Данные получены с сервера: заметок - ${serverData['notes']?.length ?? 0}, ' +
                'папок - ${serverData['folders']?.length ?? 0}, ' +
                'записей расписания - ${serverData['scheduleEntries']?.length ?? 0}, ' +
                'элементов доски - ${serverData['pinboardNotes']?.length ?? 0}');
          
          // ИСПРАВЛЕНИЕ: Импортируем данные с улучшенным импортом БЕЗ дополнительной очистки
          await _dbHelper.importDatabaseOptimized(databaseId, serverData);
          print('✅ Данные совместной базы успешно загружены с сервера');
          
          // ИСПРАВЛЕНИЕ: Разблокируем ДО уведомления об обновлении
          if (_databaseProvider != null) {
            _databaseProvider!.setIsBlocked(false);
            print('✅ РАЗБЛОКИРОВКА: Экраны разблокированы после загрузки данных');
            
            // Теперь безопасно уведомляем об обновлении
            _databaseProvider!.setNeedsUpdate(true);
            _databaseProvider!.notifyUpdate();
            print('🔄 ОБНОВЛЕНИЕ: UI обновлен после импорта данных');
          }
        } else {
          print('⚠️ Сервер вернул пустые данные или ошибку: ${response.statusCode}');
          // ИСПРАВЛЕНИЕ: Разблокируем в случае ошибки
          if (_databaseProvider != null) {
            _databaseProvider!.setIsBlocked(false);
            print('🚫 РАЗБЛОКИРОВКА: Экраны разблокированы после ошибки сервера');
          }
        }
      } else {
        // ИСПРАВЛЕНИЕ: Разблокируем в случае ошибки
        if (_databaseProvider != null) {
          _databaseProvider!.setIsBlocked(false);
          print('🚫 РАЗБЛОКИРОВКА: Экраны разблокированы - токен не найден');
        }
        throw Exception('Токен авторизации не найден');
      }
    } catch (e) {
      print('❌ Ошибка при загрузке данных с сервера: $e');
      // ИСПРАВЛЕНИЕ: ОБЯЗАТЕЛЬНО разблокируем в случае ошибки
      if (_databaseProvider != null) {
        _databaseProvider!.setIsBlocked(false);
        print('🚫 РАЗБЛОКИРОВКА: Экраны разблокированы после ошибки: $e');
      }
      // НЕ прерываем процесс, база может быть пустой
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
      notifyListeners();
      
      print('Переключение на личную базу данных');
      
      // ИСПРАВЛЕНИЕ: Выносим тяжелые операции в отдельный метод без notifyListeners
      await _performPersonalSwitch();
      
      print('✅ Переключение на личную базу завершено успешно');
      
      // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Принудительное обновление UI в самом конце
      print('ШАГ 3: Принудительное обновление экрана заметок...');
      if (_databaseProvider != null) {
        // Устанавливаем флаг принудительного обновления
        _databaseProvider!.setNeedsUpdate(true);
        _databaseProvider!.notifyUpdate();
        print('✅ Экран заметок принудительно обновлен после переключения на личную базу');
      }
      
    } catch (e) {
      _error = e.toString();
      print('❌ Ошибка при переключении на личную базу данных: $e');
    } finally {
      _isSwitchingDatabase = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ИСПРАВЛЕНИЕ: Выносим тяжелые операции в отдельный метод без notifyListeners
  Future<void> _performPersonalSwitch() async {
    try {
      // ШАГ 1: Синхронизация (отправка данных совместной базы на сервер)
      if (_currentDatabaseId != null && _isUsingSharedDatabase) {
        print('ШАГ 1: Синхронизация - отправка данных совместной базы на сервер...');
        try {
          await _syncService.forceSync();
          print('✅ Данные совместной базы отправлены на сервер');
        } catch (e) {
          print('❌ Ошибка при синхронизации: $e');
          // Продолжаем процесс, синхронизация не критична
        }
      }
      
      // Останавливаем синхронизацию и устанавливаем флаги
      _syncService.setCurrentDatabase(null);
      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Снимаем защиту от синхронизации при переходе на личную базу
      _isJustSwitchedToSharedDatabase = false;
      _lastDatabaseSwitchTime = null;
      print('🛡️ ЗАЩИТА: Блокировка синхронизации снята при переходе на личную базу');
      
      // Очищаем кеш
      await _dbHelper.clearCache();
      
      // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Очищаем кеш изображений Flutter
      print('ШАГ 2.1: Очистка кеша изображений Flutter...');
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        print('✅ Кеш изображений Flutter очищен');
      } catch (e) {
        print('⚠️ Ошибка при очистке кеша изображений Flutter: $e');
      }
      
      print('База данных очищена');
      
      // Инициализируем личную базу
      await _dbHelper.database; // Получаем личную базу
      print('Личная база данных инициализирована');
      
      // Уведомляем DatabaseProvider о переключении
      if (_databaseProvider != null) {
        await _databaseProvider!.switchToDatabase(null);
        print('DatabaseProvider переключен на личную базу');
      }
      
      // ШАГ 2: ЗАГРУЗКА бэкапа пользовательских данных
      if (_databaseProvider != null) {
        print('ШАГ 2: Загрузка резервной копии личных данных...');
        try {
          final personalBackup = await _databaseProvider!.getPersonalBackup();
          if (personalBackup != null) {
            await _databaseProvider!.restoreFromBackup(personalBackup, null);
            print('✅ Личные данные успешно восстановлены из резервной копии');
            
            // ИСПРАВЛЕНИЕ: Немедленно обновляем UI после восстановления бэкапа
            _databaseProvider!.setNeedsUpdate(true);
            _databaseProvider!.notifyUpdate();
          } else {
            print('⚠️ Резервная копия личных данных не найдена');
          }
        } catch (e) {
          print('❌ Ошибка при восстановлении личных данных: $e');
          // Не критично, база может быть пустой
        }
      }
      
      print('✅ Переключение на личную базу завершено успешно');
      
    } catch (e) {
      print('❌ Ошибка в _performPersonalSwitch: $e');
      rethrow;
    }
  }

  // Методы для работы с пользователями
  Future<void> inviteUser(String databaseId, String email, CollaborativeDatabaseRole role) async {
    try {
      await _roleService.inviteUser(databaseId, email, role);
      await _loadDatabaseUsers(databaseId);
      showCustomToastWithIcon(
        'Приглашение отправлено',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка отправки приглашения: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      notifyListeners();
    }
  }

  Future<void> updateUserRole(String databaseId, String userId, CollaborativeDatabaseRole newRole) async {
    try {
      await _roleService.updateUserRole(databaseId, userId, newRole);
      await _loadDatabaseUsers(databaseId);
      showCustomToastWithIcon(
        'Роль пользователя обновлена',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка обновления роли: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      notifyListeners();
    }
  }

  Future<void> removeUser(String databaseId, String userId) async {
    try {
      await _roleService.removeUser(databaseId, userId);
      await _loadDatabaseUsers(databaseId);
      showCustomToastWithIcon(
        'Пользователь удален из базы данных',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка удаления пользователя: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
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
      
      showCustomToastWithIcon(
        'Вы покинули базу данных',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка при выходе из базы данных: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
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
        
        showCustomToastWithIcon(
          'База данных удалена',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
      } else {
        throw Exception('Ошибка при удалении базы данных: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка удаления базы данных: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
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
      showCustomToastWithIcon(
        'Приглашение принято',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка принятия приглашения: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      notifyListeners();
    }
  }

  Future<void> declineInvitation(String invitationId) async {
    try {
      await _roleService.declineInvitation(invitationId);
      await _loadPendingInvitations();
      showCustomToastWithIcon(
        'Приглашение отклонено',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка отклонения приглашения: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      notifyListeners();
    }
  }

  // Методы для работы с синхронизацией
  Future<void> syncDatabase() async {
    if (_currentDatabaseId == null || !_isUsingSharedDatabase) {
      print('Синхронизация невозможна: нет активной совместной базы данных');
      return;
    }
    
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Защита от синхронизации сразу после переключения базы
    if (_isJustSwitchedToSharedDatabase && _lastDatabaseSwitchTime != null) {
      final timeSinceSwitch = DateTime.now().difference(_lastDatabaseSwitchTime!);
      if (timeSinceSwitch.inSeconds < 30) {
        print('БЛОКИРОВКА: Синхронизация заблокирована на ${30 - timeSinceSwitch.inSeconds} секунд после переключения базы');
        return;
      } else {
        // Снимаем блокировку после истечения времени
        _isJustSwitchedToSharedDatabase = false;
        _lastDatabaseSwitchTime = null;
      }
    }
    
    // Защита от параллельных операций синхронизации
    if (_isSyncing) {
      print('Операция синхронизации уже выполняется, пропускаем');
      return;
    }
    
    try {
      _isSyncing = true;
      print('ШАГ СИНХРОНИЗАЦИЯ: Отправка данных совместной базы $_currentDatabaseId НА сервер...');
      
      await _syncService.forceSync();
      
      showCustomToastWithIcon(
        'Синхронизация завершена успешно',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      print('✅ Данные совместной базы отправлены на сервер');
      
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка синхронизации: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      print('❌ Ошибка синхронизации: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> resolveConflict(SyncConflict conflict, bool useLocal) async {
    try {
      await _syncService.resolveConflict(conflict, useLocal);
      _pendingConflicts.removeWhere((c) => c.id == conflict.id);
      showCustomToastWithIcon(
        'Конфликт разрешен',
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      showCustomToastWithIcon(
        'Ошибка разрешения конфликта: $e',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
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