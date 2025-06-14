import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/backup_data.dart';
import '../models/enhanced_collaborative_database.dart';
import '../db/database_helper.dart';
import 'auth_service.dart';
import 'dart:math' as math;
import '../services/server_config_service.dart';

enum SyncStatus {
  idle,
  syncing,
  conflict,
  error,
  success
}

class SyncConflict {
  final String id;
  final String type; // 'note', 'folder', 'schedule_entry', etc.
  final Map<String, dynamic> localData;
  final Map<String, dynamic> serverData;
  final DateTime conflictTime;

  SyncConflict({
    required this.id,
    required this.type,
    required this.localData,
    required this.serverData,
    required this.conflictTime,
  });
}

class SyncResult {
  final SyncStatus status;
  final List<SyncConflict> conflicts;
  final String? error;
  final int itemsSynced;
  final DateTime syncTime;

  SyncResult({
    required this.status,
    this.conflicts = const [],
    this.error,
    this.itemsSynced = 0,
    required this.syncTime,
  });
}

class EnhancedSyncService {
  final AuthService _authService;
  final DatabaseHelper _dbHelper;
  final Dio _dio;
  
  static const Duration _syncInterval = Duration(minutes: 5);
  static const String _lastSyncKey = 'enhanced_last_sync_time';
  static const String _syncVersionKey = 'sync_version';
  
  Timer? _syncTimer;
  bool _isSyncing = false;
  String? _currentDatabaseId;
  final StreamController<SyncResult> _syncResultController = StreamController<SyncResult>.broadcast();
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();

  EnhancedSyncService(this._authService, this._dbHelper)
      : _dio = Dio() {
    _initBaseUrl();
    
    _dio.options.connectTimeout = Duration(seconds: 10);
    _dio.options.receiveTimeout = Duration(seconds: 30);
    _dio.options.sendTimeout = Duration(seconds: 30);
    
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _authService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException error, handler) {
        print('Ошибка запроса к серверу синхронизации: ${error.message}');
        return handler.next(error);
      }
    ));
  }

  Stream<SyncResult> get syncResults => _syncResultController.stream;
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  Future<void> initialize() async {
    // Временно отключаем периодическую синхронизацию
    // _startPeriodicSync();
    print('EnhancedSyncService инициализирован без периодической синхронизации');
  }

  void _startPeriodicSync() {
    // Временно отключено для отладки
    // _syncTimer?.cancel();
    // _syncTimer = Timer.periodic(_syncInterval, (_) => syncIfNeeded());
    print('Периодическая синхронизация отключена');
  }

  void setCurrentDatabase(String? databaseId) {
    _currentDatabaseId = databaseId;
    if (databaseId == null) {
      print('EnhancedSyncService: переключен на личную базу данных (синхронизация отключена)');
    } else {
      print('EnhancedSyncService: переключен на совместную базу данных $databaseId');
    }
  }

  Future<void> syncIfNeeded() async {
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Не синхронизируем личную базу
    if (_isSyncing || _currentDatabaseId == null || _currentDatabaseId == '') {
      print('syncIfNeeded пропущен: _isSyncing=$_isSyncing, _currentDatabaseId=$_currentDatabaseId');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTime = prefs.getInt('${_lastSyncKey}_${_currentDatabaseId}') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (now - lastSyncTime >= _syncInterval.inMilliseconds) {
        await performFullSync();
      }
    } catch (e) {
      print('Ошибка автоматической синхронизации: $e');
      _syncResultController.add(SyncResult(
        status: SyncStatus.error,
        error: e.toString(),
        syncTime: DateTime.now(),
      ));
    }
  }

  Future<SyncResult> performFullSync() async {
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Не синхронизируем личную базу
    if (_isSyncing || _currentDatabaseId == null || _currentDatabaseId == '') {
      print('performFullSync пропущен: _isSyncing=$_isSyncing, _currentDatabaseId=$_currentDatabaseId');
      return SyncResult(
        status: SyncStatus.error,
        error: 'Синхронизация уже выполняется или база данных не выбрана',
        syncTime: DateTime.now(),
      );
    }

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      print('Начало полной синхронизации для базы $_currentDatabaseId');
      print('Базовый URL Dio: ${_dio.options.baseUrl}');

      // 1. Получаем локальные изменения
      final localChanges = await _getLocalChanges();
      print('Локальных изменений: ${localChanges.length}');
      
      // 2. Получаем версию сервера
      final serverVersion = await _getServerVersion();
      final localVersion = await _getLocalVersion();
      print('Версия сервера: $serverVersion, локальная версия: $localVersion');

      // 3. Отправляем локальные изменения на сервер и получаем обновленные данные в ответе
      final uploadResult = await _uploadChanges(localChanges);
      print('Загружено изменений: $uploadResult');
      
      // 4. ИСПРАВЛЕНИЕ: Получаем данные с сервера только если локальных изменений не было
      List<Map<String, dynamic>> serverChanges = [];
      if (localChanges.isEmpty) {
        serverChanges = await _downloadChanges(localVersion);
        print('Получено изменений с сервера: ${serverChanges.length}');
      } else {
        print('Локальные изменения отправлены, получение данных с сервера не требуется');
      }
      
      // 5. Применяем изменения с сервера только если они есть
      List<SyncConflict> conflicts = [];
      if (serverChanges.isNotEmpty) {
        conflicts = await _applyServerChanges(serverChanges);
        print('Конфликтов при применении: ${conflicts.length}');
      } else {
        print('Изменений с сервера нет, применение не требуется');
      }
      
      // 6. Обновляем версию и время синхронизации
      await _updateSyncMetadata(serverVersion);

      final result = SyncResult(
        status: conflicts.isEmpty ? SyncStatus.success : SyncStatus.conflict,
        conflicts: conflicts,
        itemsSynced: uploadResult + serverChanges.length,
        syncTime: DateTime.now(),
      );

      _syncResultController.add(result);
      _syncStatusController.add(result.status);

      print('Синхронизация завершена: ${result.itemsSynced} элементов, ${conflicts.length} конфликтов');
      
      return result;
    } catch (e) {
      print('Ошибка при синхронизации: $e');
      final result = SyncResult(
        status: SyncStatus.error,
        error: e.toString(),
        syncTime: DateTime.now(),
      );
      
      _syncResultController.add(result);
      _syncStatusController.add(SyncStatus.error);
      
      return result;
    } finally {
      _isSyncing = false;
      print('Синхронизация завершена, _isSyncing установлен в false');
    }
  }

  Future<List<Map<String, dynamic>>> _getLocalChanges() async {
    final db = await _dbHelper.database;
    final changes = <Map<String, dynamic>>[];

    try {
      // ИСПРАВЛЕНИЕ: Если _currentDatabaseId null, значит мы в личной базе - не синхронизируем
      if (_currentDatabaseId == null) {
        print('Личная база данных - синхронизация не требуется');
        return changes;
      }

      // ИСПРАВЛЕНИЕ: Для совместной базы загружаем ТОЛЬКО данные с соответствующим database_id
      // Убираем загрузку данных без database_id, так как это личные данные
      
      // Папки - только для текущей совместной базы
      final folders = await db.query(
        'folders', 
        where: 'database_id = ?', 
        whereArgs: [_currentDatabaseId]
      );
      for (final folder in folders) {
        final folderData = Map<String, dynamic>.from(folder);
        changes.add({...folderData, 'type': 'folder'});
      }

      // Заметки - только для текущей совместной базы
      final notes = await db.query(
        'notes', 
        where: 'database_id = ?', 
        whereArgs: [_currentDatabaseId]
      );
      for (final note in notes) {
        final noteData = Map<String, dynamic>.from(note);
        changes.add({...noteData, 'type': 'note'});
      }

      // Записи расписания - только для текущей совместной базы
      final scheduleEntries = await db.query(
        'schedule_entries', 
        where: 'database_id = ?', 
        whereArgs: [_currentDatabaseId]
      );
      for (final entry in scheduleEntries) {
        final entryData = Map<String, dynamic>.from(entry);
        changes.add({...entryData, 'type': 'schedule_entry'});
      }

      // Заметки доски - только для текущей совместной базы
      final pinboardNotes = await db.query(
        'pinboard_notes', 
        where: 'database_id = ?', 
        whereArgs: [_currentDatabaseId]
      );
      for (final note in pinboardNotes) {
        final noteData = Map<String, dynamic>.from(note);
        changes.add({...noteData, 'type': 'pinboard_note'});
      }

      // Соединения - только для текущей совместной базы
      final connections = await db.query(
        'connections', 
        where: 'database_id = ?', 
        whereArgs: [_currentDatabaseId]
      );
      for (final connection in connections) {
        final connectionData = Map<String, dynamic>.from(connection);
        changes.add({...connectionData, 'type': 'connection'});
      }

      // Изображения заметок - только для заметок из текущей совместной базы
      final noteIds = notes.map((note) => note['id']).where((id) => id != null).toList();
      if (noteIds.isNotEmpty) {
        final placeholders = List.filled(noteIds.length, '?').join(',');
        final noteImages = await db.query(
          'note_images', 
          where: 'note_id IN ($placeholders)', 
          whereArgs: noteIds
        );
        
        for (final image in noteImages) {
          var imageData = Map<String, dynamic>.from(image);
          
          // Проверяем корректность note_id перед добавлением
          final noteId = imageData['note_id'];
          if (noteId != null && noteId != 0) {
            // Загружаем бинарные данные изображения
            if (imageData['id'] != null) {
              try {
                final imageBytes = await _dbHelper.getImageData(imageData['id'] as int);
                if (imageBytes != null && imageBytes.isNotEmpty) {
                  imageData['image_data'] = imageBytes;
                  imageData['database_id'] = _currentDatabaseId; // Убеждаемся, что database_id установлен
                  print('Загружены данные изображения ${imageData['id']}: ${imageBytes.length} байт');
                } else {
                  print('Предупреждение: Пустые данные для изображения ${imageData['id']}');
                  continue; // Пропускаем изображения без данных
                }
              } catch (e) {
                print('Ошибка загрузки данных изображения ${imageData['id']}: $e');
                continue; // Пропускаем проблемные изображения
              }
            }
            
            changes.add({...imageData, 'type': 'note_image'});
          }
        }
      }

      print('Получено локальных изменений для совместной базы $_currentDatabaseId: ${changes.length}');
    } catch (e) {
      print('Ошибка получения локальных изменений: $e');
    }

    return changes;
  }

  Future<String> _getServerVersion() async {
    try {
      final response = await _dio.get('/api/collaboration/databases/$_currentDatabaseId/version');
      if (response.statusCode == 200) {
        return response.data['version']?.toString() ?? '1';
      }
    } catch (e) {
      print('Ошибка получения версии сервера: $e');
    }
    return '1';
  }

  Future<String> _getLocalVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_syncVersionKey}_${_currentDatabaseId}') ?? '1';
  }

  Future<int> _uploadChanges(List<Map<String, dynamic>> changes) async {
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: НЕ отправляем пустые данные на сервер
    if (changes.isEmpty) {
      print('Локальных изменений нет, пропускаем отправку на сервер');
      return 0;
    }

    try {
      print('Начинаем загрузку ${changes.length} изменений на сервер');
      
      // Группируем изменения по типам для отправки в формате, который ожидает сервер
      final notes = <Map<String, dynamic>>[];
      final folders = <Map<String, dynamic>>[];
      final scheduleEntries = <Map<String, dynamic>>[];
      final pinboardNotes = <Map<String, dynamic>>[];
      final connections = <Map<String, dynamic>>[];
      final noteImages = <Map<String, dynamic>>[];

      for (final change in changes) {
        final type = change['type'];
        final data = Map<String, dynamic>.from(change);
        data.remove('type'); // Убираем служебное поле
        
        // Преобразуем данные в формат, ожидаемый сервером
        final serverData = _convertToServerFormat(data, type);
        
        switch (type) {
          case 'note':
            notes.add(serverData);
            break;
          case 'folder':
            folders.add(serverData);
            break;
          case 'schedule_entry':
            scheduleEntries.add(serverData);
            break;
          case 'pinboard_note':
            pinboardNotes.add(serverData);
            break;
          case 'connection':
            connections.add(serverData);
            break;
          case 'note_image':
            noteImages.add(serverData);
            break;
        }
      }

      // ИСПРАВЛЕНИЕ: Проверяем, что есть хотя бы какие-то данные для отправки
      final totalItems = notes.length + folders.length + scheduleEntries.length + 
                        pinboardNotes.length + connections.length + noteImages.length;
      
      if (totalItems == 0) {
        print('После группировки данных для отправки не оказалось, пропускаем синхронизацию');
        return 0;
      }

      print('Группировка: notes=${notes.length}, folders=${folders.length}, schedule_entries=${scheduleEntries.length}, pinboard_notes=${pinboardNotes.length}, connections=${connections.length}, note_images=${noteImages.length}');

      final response = await _dio.post(
        '/api/sync/$_currentDatabaseId',
        data: {
          'notes': notes,
          'folders': folders,
          'schedule_entries': scheduleEntries,
          'pinboard_notes': pinboardNotes,
          'connections': connections,
          'note_images': noteImages,
        },
      );

      print('Ответ сервера на загрузку: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        return changes.length;
      }
    } catch (e) {
      print('Ошибка загрузки изменений: $e');
      rethrow;
    }
    
    return 0;
  }

  Future<List<Map<String, dynamic>>> _downloadChanges(String localVersion) async {
    try {
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Используем GET запрос для получения данных с сервера
      // вместо POST с пустыми данными, который вызывает удаление всех данных
      print('Получение данных с сервера для базы $_currentDatabaseId...');
      
      final response = await _dio.get('/api/collaboration/databases/$_currentDatabaseId/data');

      if (response.statusCode == 200) {
        final data = response.data;
        final changes = <Map<String, dynamic>>[];
        
        // Обрабатываем ответ сервера
        if (data['notes'] is List) {
          for (final note in data['notes']) {
            changes.add({...note, 'type': 'note'});
          }
        }
        
        if (data['folders'] is List) {
          for (final folder in data['folders']) {
            changes.add({...folder, 'type': 'folder'});
          }
        }
        
        if (data['schedule_entries'] is List) {
          for (final entry in data['schedule_entries']) {
            changes.add({...entry, 'type': 'schedule_entry'});
          }
        }
        
        if (data['pinboard_notes'] is List) {
          for (final note in data['pinboard_notes']) {
            changes.add({...note, 'type': 'pinboard_note'});
          }
        }
        
        if (data['connections'] is List) {
          for (final connection in data['connections']) {
            changes.add({...connection, 'type': 'connection'});
          }
        }
        
        if (data['images'] is List) {
          for (final image in data['images']) {
            changes.add({...image, 'type': 'note_image'});
          }
        }
        
        print('Получено данных с сервера: ${changes.length}');
        return changes;
      } else {
        print('Ошибка получения данных с сервера: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Ошибка загрузки изменений с сервера: $e');
      // Если сервер не поддерживает GET endpoint, возвращаем пустой список
      // вместо отправки пустых данных через POST
      return [];
    }
  }

  Future<List<SyncConflict>> _applyServerChanges(List<Map<String, dynamic>> serverChanges) async {
    final conflicts = <SyncConflict>[];
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // Сначала очищаем все данные в локальной базе
      await txn.delete('notes');
      await txn.delete('folders');
      await txn.delete('schedule_entries');
      await txn.delete('pinboard_notes');
      await txn.delete('connections');
      await txn.delete('note_images');
      
      // Затем вставляем данные с сервера
      for (final change in serverChanges) {
        try {
          await _applyChange(txn, change);
        } catch (e) {
          print('Ошибка применения изменения: $e');
        }
      }
    });

    return conflicts;
  }

  Future<Map<String, dynamic>?> _getLocalRecord(dynamic txn, String type, dynamic id) async {
    final tableName = _getTableName(type);
    if (tableName == null) return null;

    try {
      final results = await txn.query(
        tableName,
        where: 'id = ? AND database_id = ?',
        whereArgs: [id, _currentDatabaseId],
        limit: 1,
      );
      
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print('Ошибка получения локальной записи: $e');
      return null;
    }
  }

  String? _getTableName(String type) {
    switch (type) {
      case 'note':
        return 'notes';
      case 'folder':
        return 'folders';
      case 'schedule_entry':
        return 'schedule_entries';
      case 'pinboard_note':
        return 'pinboard_notes';
      case 'connection':
        return 'connections';
      case 'note_image':
        return 'note_images';
      default:
        return null;
    }
  }

  Future<void> _applyChange(dynamic txn, Map<String, dynamic> change) async {
    final type = change['type'] as String;
    final tableName = _getTableName(type);
    if (tableName == null) return;

    final data = Map<String, dynamic>.from(change);
    data.remove('type');
    
    // Не устанавливаем database_id для совместных баз данных
    // так как данные уже приходят с сервера с правильными ID

    try {
      await txn.insert(
        tableName,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Ошибка применения изменения в таблицу $tableName: $e');
      print('Данные: $data');
    }
  }

  Future<void> _updateSyncMetadata(String serverVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await prefs.setInt('${_lastSyncKey}_${_currentDatabaseId}', now);
    await prefs.setString('${_syncVersionKey}_${_currentDatabaseId}', serverVersion);
  }

  Future<void> resolveConflict(SyncConflict conflict, bool useLocal) async {
    final db = await _dbHelper.database;
    final tableName = _getTableName(conflict.type);
    if (tableName == null) return;

    final dataToUse = useLocal ? conflict.localData : conflict.serverData;
    dataToUse['database_id'] = _currentDatabaseId;

    await db.insert(
      tableName,
      dataToUse,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Если выбрали серверную версию, отправляем её обратно на сервер
    if (!useLocal) {
      try {
        await _dio.post(
          '/sync/$_currentDatabaseId/resolve',
          data: {
            'conflict_id': conflict.id,
            'resolution': 'server',
            'data': dataToUse,
          },
        );
      } catch (e) {
        print('Ошибка отправки разрешения конфликта: $e');
      }
    }
  }

  Future<void> forceSync() async {
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Не синхронизируем личную базу
    if (_isSyncing) {
      print('forceSync: синхронизация уже выполняется, пропускаем');
      return;
    }
    
    if (_currentDatabaseId == null || _currentDatabaseId == '') {
      print('forceSync: пропущен для личной базы данных (_currentDatabaseId=$_currentDatabaseId)');
      return;
    }
    
    print('forceSync: запуск принудительной синхронизации для базы $_currentDatabaseId');
    await performFullSync();
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncResultController.close();
    _syncStatusController.close();
  }

  Map<String, dynamic> _convertToServerFormat(Map<String, dynamic> data, String type) {
    final serverData = Map<String, dynamic>.from(data);
    
    switch (type) {
      case 'note':
        // Преобразуем поля заметки
        if (serverData.containsKey('folder_id')) {
          serverData['folder_id'] = serverData['folder_id'];
        }
        if (serverData.containsKey('database_id')) {
          serverData['database_id'] = int.tryParse(serverData['database_id']?.toString() ?? '') ?? int.parse(_currentDatabaseId!);
        } else {
          serverData['database_id'] = int.parse(_currentDatabaseId!);
        }
        // Преобразуем даты в правильный формат ISO 8601 с часовым поясом
        if (serverData.containsKey('created_at') && serverData['created_at'] is String) {
          serverData['created_at'] = _formatDateTimeForServer(serverData['created_at']);
        }
        if (serverData.containsKey('updated_at') && serverData['updated_at'] is String) {
          serverData['updated_at'] = _formatDateTimeForServer(serverData['updated_at']);
        }
        break;
        
      case 'folder':
        // Преобразуем поля папки
        if (serverData.containsKey('database_id')) {
          serverData['database_id'] = int.tryParse(serverData['database_id']?.toString() ?? '') ?? int.parse(_currentDatabaseId!);
        } else {
          serverData['database_id'] = int.parse(_currentDatabaseId!);
        }
        if (serverData.containsKey('parent_id')) {
          serverData['parent_id'] = serverData['parent_id'];
        }
        if (serverData.containsKey('created_at') && serverData['created_at'] is String) {
          serverData['created_at'] = _formatDateTimeForServer(serverData['created_at']);
        }
        if (serverData.containsKey('updated_at') && serverData['updated_at'] is String) {
          serverData['updated_at'] = _formatDateTimeForServer(serverData['updated_at']);
        }
        break;
        
      case 'schedule_entry':
        // Преобразуем поля записи расписания
        if (serverData.containsKey('database_id')) {
          serverData['database_id'] = int.tryParse(serverData['database_id']?.toString() ?? '') ?? int.parse(_currentDatabaseId!);
        } else {
          serverData['database_id'] = int.parse(_currentDatabaseId!);
        }
        if (serverData.containsKey('created_at') && serverData['created_at'] is String) {
          serverData['created_at'] = _formatDateTimeForServer(serverData['created_at']);
        }
        if (serverData.containsKey('updated_at') && serverData['updated_at'] is String) {
          serverData['updated_at'] = _formatDateTimeForServer(serverData['updated_at']);
        }
        // ИСПРАВЛЕНИЕ: Обрабатываем поле tags_json для записей расписания
        if (serverData.containsKey('tags_json')) {
          // Убеждаемся, что tags_json передается корректно
          print('Обработка tags_json для записи расписания: ${serverData['tags_json']}');
        }
        break;
        
      case 'pinboard_note':
        // Преобразуем поля заметки доски
        if (serverData.containsKey('database_id')) {
          serverData['database_id'] = int.tryParse(serverData['database_id']?.toString() ?? '') ?? int.parse(_currentDatabaseId!);
        } else {
          serverData['database_id'] = int.parse(_currentDatabaseId!);
        }
        if (serverData.containsKey('created_at') && serverData['created_at'] is String) {
          serverData['created_at'] = _formatDateTimeForServer(serverData['created_at']);
        }
        if (serverData.containsKey('updated_at') && serverData['updated_at'] is String) {
          serverData['updated_at'] = _formatDateTimeForServer(serverData['updated_at']);
        }
        break;
        
      case 'connection':
        // Преобразуем поля соединения
        if (serverData.containsKey('database_id')) {
          serverData['database_id'] = int.tryParse(serverData['database_id']?.toString() ?? '') ?? int.parse(_currentDatabaseId!);
        } else {
          serverData['database_id'] = int.parse(_currentDatabaseId!);
        }
        break;
        
      case 'note_image':
        // Преобразуем поля изображения заметки
        if (serverData.containsKey('database_id')) {
          serverData['database_id'] = int.tryParse(serverData['database_id']?.toString() ?? '') ?? int.parse(_currentDatabaseId!);
        } else {
          serverData['database_id'] = int.parse(_currentDatabaseId!);
        }
        if (serverData.containsKey('note_id')) {
          serverData['note_id'] = serverData['note_id'];
        }
        
        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Кодируем image_data в base64 строку
        if (serverData.containsKey('image_data')) {
          final imageData = serverData['image_data'];
          if (imageData is Uint8List) {
            // Преобразуем бинарные данные в base64 строку
            serverData['image_data'] = base64.encode(imageData);
            print('Конвертировано изображение в base64, размер: ${imageData.length} байт');
          } else if (imageData is List<int>) {
            // Если это список байт, сначала преобразуем в Uint8List, затем в base64
            final bytes = Uint8List.fromList(imageData);
            serverData['image_data'] = base64.encode(bytes);
            print('Конвертировано изображение (List<int>) в base64, размер: ${bytes.length} байт');
          } else if (imageData is String) {
            // Если уже строка, проверяем, не нужно ли её кодировать
            if (imageData.isNotEmpty) {
              // Оставляем как есть, предполагая, что это уже base64
              print('Изображение уже в формате строки, размер: ${imageData.length} символов');
            }
          } else {
            print('Предупреждение: неизвестный формат image_data: ${imageData.runtimeType}');
          }
        }
        break;
    }
    
    return serverData;
  }

  String _formatDateTimeForServer(String dateTimeString) {
    try {
      // Парсим дату из строки
      final dateTime = DateTime.parse(dateTimeString);
      // Возвращаем в формате ISO 8601 с часовым поясом
      return dateTime.toUtc().toIso8601String();
    } catch (e) {
      print('Ошибка форматирования даты $dateTimeString: $e');
      // Возвращаем текущее время в случае ошибки
      return DateTime.now().toUtc().toIso8601String();
    }
  }

  Future<void> _initBaseUrl() async {
    try {
      final baseUrl = await ServerConfigService.getBaseUrl();
      _dio.options.baseUrl = baseUrl;
      print('Dio baseUrl установлен: $baseUrl');
    } catch (e) {
      print('Ошибка получения baseUrl: $e');
      // В крайнем случае используем ServerConfigService напрямую
      try {
        final fallbackBaseUrl = await ServerConfigService.getBaseUrl();
        _dio.options.baseUrl = fallbackBaseUrl;
        print('Dio baseUrl установлен через fallback: $fallbackBaseUrl');
      } catch (fallbackError) {
        print('Ошибка получения fallback baseUrl: $fallbackError');
        // В самом крайнем случае используем localhost
        _dio.options.baseUrl = 'http://localhost:8080';
        print('Ошибка получения baseUrl, используется по умолчанию: http://localhost:8080');
      }
    }
  }
} 