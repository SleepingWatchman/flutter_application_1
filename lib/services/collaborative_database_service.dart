import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:typed_data';
import '../models/collaborative_database.dart';
import '../models/backup_data.dart';
import 'auth_service.dart';
import '../db/database_helper.dart';
import 'dart:async';
import 'dart:math' as math;

class CollaborativeDatabaseService {
  final AuthService _authService;
  final DatabaseHelper _dbHelper;
  final String _baseUrl;
  final String _serverBaseUrl;
  final Dio _dio;

  CollaborativeDatabaseService(this._authService, this._dbHelper)
      : _baseUrl = 'http://localhost:5294/api/CollaborativeDatabase',
        _serverBaseUrl = 'http://localhost:5294/api',
        _dio = Dio() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _authService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioError error, handler) {
        print('Ошибка запроса к серверу: ${error.message}');
        // При ошибках связи или таймаутах не останавливаем приложение
        if (error.type == DioErrorType.connectionTimeout ||
            error.type == DioErrorType.receiveTimeout ||
            error.type == DioErrorType.sendTimeout ||
            error.type == DioErrorType.connectionError) {
          print('Проблема с подключением к серверу: ${error.message}');
        }
        return handler.next(error);
      }
    ));
    
    // Настраиваем таймауты для всех запросов
    _dio.options.connectTimeout = Duration(seconds: 5);
    _dio.options.receiveTimeout = Duration(seconds: 15);
    _dio.options.sendTimeout = Duration(seconds: 15);
  }

  Future<String?> _getToken() async {
    return await _authService.getToken();
  }

  Future<List<CollaborativeDatabase>> getDatabases() async {
    try {
      final response = await _dio.get('$_baseUrl/databases');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => CollaborativeDatabase.fromJson(json)).toList();
      }
      
      throw Exception('Ошибка при получении списка баз данных: ${response.statusCode}');
    } catch (e) {
      print('Ошибка в getDatabases: $e');
      rethrow;
    }
  }

  Future<CollaborativeDatabase> createDatabase(String name) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/databases',
        data: {'name': name},
      );

      if (response.statusCode == 201) {
        return CollaborativeDatabase.fromJson(response.data);
      }

      throw Exception('Ошибка при создании базы данных: ${response.statusCode}');
    } catch (e) {
      print('Ошибка в createDatabase: $e');
      rethrow;
    }
  }

  Future<void> deleteDatabase(String databaseId) async {
    try {
      final response = await _dio.delete('$_baseUrl/databases/$databaseId');

      if (response.statusCode != 204) {
        throw Exception('Ошибка при удалении базы данных: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в deleteDatabase: $e');
      rethrow;
    }
  }

  Future<void> leaveDatabase(String databaseId) async {
    try {
      final response = await _dio.post('$_baseUrl/databases/$databaseId/leave');

      if (response.statusCode != 204) {
        throw Exception('Ошибка при выходе из базы данных: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в leaveDatabase: $e');
      rethrow;
    }
  }

  Future<void> addCollaborator(String databaseId, String userId) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/databases/$databaseId/collaborators',
        data: {'userId': userId},
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка при добавлении соавтора: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в addCollaborator: $e');
      rethrow;
    }
  }

  Future<void> removeCollaborator(String databaseId, String userId) async {
    try {
      final response = await _dio.delete(
        '$_baseUrl/databases/$databaseId/collaborators/$userId',
      );

      if (response.statusCode != 204) {
        throw Exception('Ошибка при удалении соавтора: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в removeCollaborator: $e');
      rethrow;
    }
  }

  Future<void> syncDatabase(String databaseId) async {
    try {
      print('Начало синхронизации базы $databaseId');
      
      // Получаем количество записей расписания до синхронизации
      List<Map<String, dynamic>> scheduleEntriesBefore = [];
      try {
        final db = await _dbHelper.database;
        scheduleEntriesBefore = await db.query(
          'schedule_entries',
          where: 'database_id = ?',
          whereArgs: [databaseId],
        );
        print('До синхронизации в базе $databaseId найдено ${scheduleEntriesBefore.length} записей расписания');
      } catch (e) {
        print('Ошибка при получении записей расписания перед синхронизацией: $e');
      }
      
      // Используем семафор для предотвращения блокировок базы данных
      final completer = Completer<void>();
      bool isLocked = false;
      
      // Запускаем таймер для отслеживания возможной блокировки
      Timer lockTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (!completer.isCompleted) {
          print('Синхронизация базы $databaseId в процессе: ${timer.tick * 5} секунд');
          if (timer.tick > 5) {
            isLocked = true;
            print('Возможная блокировка базы данных при синхронизации');
            // Не отменяем операцию, просто логируем
          }
          
          // Принудительно завершаем синхронизацию после 30 секунд ожидания
          if (timer.tick > 6) {
            print('Таймаут при синхронизации базы $databaseId');
            if (!completer.isCompleted) {
              completer.complete();
            }
            timer.cancel();
          }
        } else {
          timer.cancel();
        }
      });
      
      // Создаем резервную копию локальной базы с таймаутом
      BackupData localBackup;
      try {
        final backupFuture = _dbHelper.createBackup(databaseId)
            .timeout(Duration(seconds: 15), onTimeout: () {
          print('Таймаут при создании резервной копии базы $databaseId');
          // Возвращаем пустую резервную копию
          return BackupData(
            folders: [],
            notes: [],
            scheduleEntries: [],
            pinboardNotes: [],
            connections: [],
            noteImages: []
          );
        });
        
        localBackup = await backupFuture;
      } catch (e) {
        print('Ошибка при создании резервной копии: $e');
        localBackup = BackupData(
          folders: [],
          notes: [],
          scheduleEntries: [],
          pinboardNotes: [],
          connections: [],
          noteImages: []
        );
      }
      
      // Проверяем, есть ли данные для синхронизации
      bool hasData = localBackup.folders.isNotEmpty || 
                     localBackup.notes.isNotEmpty || 
                     localBackup.scheduleEntries.isNotEmpty || 
                     localBackup.pinboardNotes.isNotEmpty || 
                     localBackup.connections.isNotEmpty || 
                     localBackup.noteImages.isNotEmpty;
                     
      if (!hasData) {
        print('Нет данных для синхронизации, пробуем загрузить данные с сервера');
        
        // Попытка загрузить данные с сервера с таймаутом
        try {
          final getResponse = await _dio.get(
            '$_serverBaseUrl/Database/$databaseId',
            options: Options(
              validateStatus: (status) => status != null && status < 500,
              receiveTimeout: const Duration(seconds: 10),
            ),
          ).timeout(Duration(seconds: 15), onTimeout: () {
            print('Таймаут при получении данных с сервера для базы $databaseId');
            throw TimeoutException('Таймаут при получении данных с сервера');
          });
          
          if (getResponse.statusCode == 200) {
            final serverData = getResponse.data;
            if (serverData != null && serverData is Map && serverData.isNotEmpty) {
              // Закрываем и вновь открываем базу данных для предотвращения блокировок
              try {
                await _dbHelper.closeDatabase();
                print('База данных закрыта перед восстановлением из резервной копии');
              } catch (closeError) {
                print('Ошибка при закрытии базы данных: $closeError');
              }
              
              final serverBackup = BackupData.fromJson(Map<String, dynamic>.from(serverData));
              
              try {
                await _dbHelper.restoreFromBackup(serverBackup, databaseId)
                    .timeout(Duration(seconds: 15), onTimeout: () {
                  print('Таймаут при восстановлении данных для базы $databaseId');
                  throw TimeoutException('Таймаут при восстановлении данных');
                });
                
                print('Данные успешно загружены с сервера');
                lockTimer.cancel();
                completer.complete();
                return;
              } catch (e) {
                print('Ошибка при восстановлении из резервной копии: $e');
                // Продолжаем попытку синхронизации без выбрасывания исключения
              }
            }
          }
        } catch (e) {
          print('Ошибка при попытке загрузить данные с сервера: $e');
        }
        
        // Завершаем синхронизацию, если нет данных для работы
        if (!completer.isCompleted) {
          lockTimer.cancel();
          completer.complete();
        }
        return;
      }
      
      // Подготавливаем данные для отправки на сервер
      Map<String, dynamic> jsonData;
      try {
        jsonData = localBackup.toJson();
      } catch (e) {
        print('Ошибка при преобразовании резервной копии в JSON: $e');
        lockTimer.cancel();
        completer.complete();
        return;
      }
      
      // Проверяем количество заметок в базе и возможных изображений
      final notesCount = localBackup.notes.length;
      final notesWithImages = localBackup.noteImages.map((img) => img['note_id']).toSet().length;
      print('База $databaseId содержит $notesCount заметок, из них $notesWithImages с изображениями');
      
      // Проверяем данные изображений и очищаем, если есть проблемы
      List<Map<String, dynamic>> validImages = [];
      int imageErrors = 0;
      
      for (var image in localBackup.noteImages) {
        if (!image.containsKey('note_id') || !image.containsKey('file_name') || !image.containsKey('image_data')) {
          imageErrors++;
          print('Ошибка в структуре данных изображения: отсутствуют обязательные поля');
          continue;
        }
        
        if (image['image_data'] == null || 
            (image['image_data'] is Uint8List && (image['image_data'] as Uint8List).isEmpty)) {
          imageErrors++;
          print('Ошибка в данных изображения ${image['file_name']}: пустые данные');
          continue;
        }
        
        validImages.add(image);
      }
      
      if (imageErrors > 0) {
        print('Пропущено $imageErrors проблемных изображений при синхронизации');
      }
      
      // Проверяем и подготавливаем данные, делая их совместимыми с сервером
      final preparedData = {
        'databaseId': databaseId,
        'folders': jsonData['folders'] ?? [],
        'notes': jsonData['notes'] ?? [],
        'scheduleEntries': jsonData['scheduleEntries'] ?? [],
        'pinboardNotes': jsonData['pinboardNotes'] ?? [],
        'connections': jsonData['connections'] ?? [],
        'images': jsonData['images'] ?? [], // Важно использовать тот же ключ, что и в методе BackupData.toJson()
        'lastModified': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'userId': _authService.getCurrentUserId() ?? "unknown",
      };
      
      print('Отправка данных на сервер: ${preparedData['notes'].length} заметок, ${preparedData['images'].length} изображений');
      print('Отправка записей расписания: ${preparedData['scheduleEntries'].length}');

      // Отправляем изменения на сервер с таймаутом
      try {
        final response = await _dio.post(
          '$_serverBaseUrl/CollaborativeDatabase/databases/$databaseId/sync',
          data: preparedData,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
            },
            validateStatus: (status) => status != null && status < 500,
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
          ),
        ).timeout(Duration(seconds: 20), onTimeout: () {
          print('Таймаут при отправке данных на сервер для синхронизации базы $databaseId');
          throw TimeoutException('Таймаут при отправке данных на сервер');
        });

        if (response.statusCode == 200) {
          print('Получен ответ от сервера со статусом 200');
          // Получаем обновленные данные с сервера
          if (response.data != null) {
            print('Тип данных ответа: ${response.data.runtimeType}');
            try {
              // Закрываем и вновь открываем базу данных для предотвращения блокировок
              try {
                await _dbHelper.closeDatabase();
                print('База данных закрыта перед восстановлением из резервной копии');
              } catch (closeError) {
                print('Ошибка при закрытии базы данных: $closeError');
              }
              
              BackupData serverBackup;
              
              // Проверяем, имеем ли мы дело с данными бекапа или с другой структурой
              if (response.data is Map && 
                 (response.data['notes'] != null || response.data['folders'] != null)) {
                // Если это бекап с данными, используем его
                Map<String, dynamic> responseData = Map<String, dynamic>.from(response.data);
                
                // Проверяем наличие записей расписания в ответе сервера
                bool hasScheduleEntries = (responseData['scheduleEntries'] != null && 
                                        responseData['scheduleEntries'] is List && 
                                        (responseData['scheduleEntries'] as List).isNotEmpty);
                
                if (!hasScheduleEntries && scheduleEntriesBefore.isNotEmpty) {
                  print('ВНИМАНИЕ: Сервер вернул ответ без записей расписания, хотя они были в локальной базе. Добавляем их в ответ.');
                  // Добавляем локальные записи расписания в ответ сервера
                  responseData['scheduleEntries'] = scheduleEntriesBefore;
                }
                
                serverBackup = BackupData.fromJson(responseData);
              } else {
                // Если это не бекап или пустой объект, используем наши локальные данные
                print('Сервер вернул данные другого формата или пустые данные. Используем локальную копию.');
                serverBackup = localBackup;
              }
              
              try {
                await _dbHelper.restoreFromBackup(serverBackup, databaseId)
                    .timeout(Duration(seconds: 15), onTimeout: () {
                  print('Таймаут при восстановлении данных после синхронизации базы $databaseId');
                  throw TimeoutException('Таймаут при восстановлении данных');
                });
                
                // Проверяем количество записей расписания после синхронизации
                try {
                  final db = await _dbHelper.database;
                  final scheduleEntriesAfter = await db.query(
                    'schedule_entries',
                    where: 'database_id = ?',
                    whereArgs: [databaseId],
                  );
                  
                  print('После синхронизации в базе $databaseId найдено ${scheduleEntriesAfter.length} записей расписания');
                  
                  // Если записи расписания были потеряны, восстанавливаем их
                  if (scheduleEntriesAfter.isEmpty && scheduleEntriesBefore.isNotEmpty) {
                    print('ВОССТАНОВЛЕНИЕ: Записи расписания потеряны при синхронизации. Восстанавливаем их.');
                    
                    await _dbHelper.executeTransaction((txn) async {
                      for (var entry in scheduleEntriesBefore) {
                        await txn.insert('schedule_entries', entry);
                      }
                    });
                    
                    print('Восстановлено ${scheduleEntriesBefore.length} записей расписания');
                  }
                } catch (e) {
                  print('Ошибка при проверке записей расписания после синхронизации: $e');
                }
                
                print('Синхронизация успешно выполнена');
              } catch (e) {
                print('Ошибка при восстановлении данных после синхронизации: $e');
              }
            } catch (e) {
              print('Ошибка при обработке ответа сервера: $e');
            }
          } else {
            print('Сервер вернул пустые данные. Пропускаем обновление локальной базы.');
          }
        } else if (response.statusCode == 400) {
          // В случае ошибки 400 получаем детали ошибки
          final errorMessage = response.data is Map 
              ? response.data['message'] ?? 'Неизвестная ошибка сервера' 
              : 'Неизвестная ошибка сервера';
          print('Ошибка 400 при синхронизации: $errorMessage');
          
          // Пытаемся восстановить данные с сервера
          try {
            await _getAndRestoreServerData(databaseId);
          } catch (e) {
            print('Ошибка при восстановлении данных с сервера: $e');
          }
        } else {
          print('Ошибка при синхронизации: ${response.statusCode}');
          // Пытаемся восстановить данные с сервера
          try {
            await _getAndRestoreServerData(databaseId);
          } catch (e) {
            print('Ошибка при восстановлении данных с сервера: $e');
          }
        }
      } catch (e) {
        if (e is TimeoutException) {
          print('Таймаут при синхронизации базы $databaseId: $e');
        } else {
          print('Ошибка при отправке данных на сервер: $e');
        }
        
        // Пытаемся восстановить данные с сервера при любой ошибке
        try {
          await _getAndRestoreServerData(databaseId);
        } catch (e) {
          print('Ошибка при восстановлении данных с сервера: $e');
        }
      }
      
      lockTimer.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    } catch (e) {
      print('Ошибка в syncDatabase: $e');
      // Не перебрасываем исключение дальше, чтобы не прерывать работу приложения
    }
  }
  
  /// Вспомогательный метод для получения и восстановления данных с сервера
  Future<void> _getAndRestoreServerData(String databaseId) async {
    try {
      final getResponse = await _dio.get(
        '$_serverBaseUrl/Database/$databaseId',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 10),
        ),
      ).timeout(Duration(seconds: 15), onTimeout: () {
        print('Таймаут при получении данных для восстановления базы $databaseId');
        throw TimeoutException('Таймаут при получении данных');
      });
      
      if (getResponse.statusCode == 200) {
        final serverData = getResponse.data;
        if (serverData != null && serverData is Map && serverData.isNotEmpty) {
          // Закрываем и вновь открываем базу данных для предотвращения блокировок
          try {
            await _dbHelper.closeDatabase();
            print('База данных закрыта перед восстановлением из резервной копии');
          } catch (closeError) {
            print('Ошибка при закрытии базы данных: $closeError');
          }
          
          final serverBackup = BackupData.fromJson(Map<String, dynamic>.from(serverData));
          
          try {
            await _dbHelper.restoreFromBackup(serverBackup, databaseId)
                .timeout(Duration(seconds: 15), onTimeout: () {
              print('Таймаут при восстановлении данных после ошибки синхронизации базы $databaseId');
              throw TimeoutException('Таймаут при восстановлении данных');
            });
            
            print('Данные успешно восстановлены с сервера после ошибки синхронизации');
            return;
          } catch (e) {
            print('Ошибка при восстановлении данных: $e');
            throw e;
          }
        } else {
          print('Сервер вернул пустые данные при попытке восстановления после ошибки');
          throw Exception('Сервер вернул пустые данные');
        }
      } else {
        print('Не удалось получить данные для восстановления: ${getResponse.statusCode}');
        throw Exception('Ошибка при получении данных с сервера: ${getResponse.statusCode}');
      }
    } catch (e) {
      print('Ошибка при попытке восстановить данные после ошибки синхронизации: $e');
      throw e;
    }
  }

  Future<CollaborativeDatabase> importDatabase(String databaseId) async {
    try {
      // Сначала проверяем, существует ли база данных на сервере
      try {
        final checkResponse = await _dio.get(
          '$_serverBaseUrl/CollaborativeDatabase/databases/$databaseId',
          options: Options(
            validateStatus: (status) => status != null && status < 500,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        
        if (checkResponse.statusCode == 200 && checkResponse.data != null) {
          print('База данных $databaseId существует на сервере');
        } else {
          print('База данных $databaseId не найдена или пуста. Создаем только локальную копию.');
          return _createDefaultCollaborativeDatabase(databaseId);
        }
      } catch (checkError) {
        print('Ошибка при проверке существования базы данных: $checkError');
      }

      final response = await _dio.post(
        '$_serverBaseUrl/CollaborativeDatabase/databases/import',
        data: {'databaseId': databaseId},
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        
        // Преобразуем числовые значения в строки
        final processedData = Map<String, dynamic>.from(data);
        if (processedData['id'] is int) {
          processedData['id'] = processedData['id'].toString();
        }
        if (processedData['ownerId'] is int) {
          processedData['ownerId'] = processedData['ownerId'].toString();
        }
        if (processedData['version'] is int) {
          processedData['version'] = processedData['version'].toString();
        }

        // Обрабатываем даты
        if (processedData['createdAt'] is String) {
          processedData['createdAt'] = DateTime.parse(processedData['createdAt']).toIso8601String();
        }
        if (processedData['lastModified'] is String) {
          processedData['lastModified'] = DateTime.parse(processedData['lastModified']).toIso8601String();
        }
        if (processedData['lastSync'] is String) {
          processedData['lastSync'] = DateTime.parse(processedData['lastSync']).toIso8601String();
        }
        if (processedData['lastSyncTime'] is String) {
          processedData['lastSyncTime'] = DateTime.parse(processedData['lastSyncTime']).toIso8601String();
        }

        // Обрабатываем collaborators
        if (processedData['collaborators'] is Map) {
          final collaborators = Map<String, dynamic>.from(processedData['collaborators']);
          final processedCollaborators = <String, String>{};
          collaborators.forEach((key, value) {
            processedCollaborators[key.toString()] = value.toString();
          });
          processedData['collaborators'] = processedCollaborators;
        }

        return CollaborativeDatabase.fromJson(processedData);
      } else {
        print('Ошибка при импорте базы данных, код: ${response.statusCode}');
        return _createDefaultCollaborativeDatabase(databaseId);
      }
    } catch (e) {
      print('Ошибка при импорте базы данных: $e');
      return _createDefaultCollaborativeDatabase(databaseId);
    }
  }

  // Вспомогательный метод для создания базовой структуры совместной базы данных
  CollaborativeDatabase _createDefaultCollaborativeDatabase(String databaseId) {
    return CollaborativeDatabase(
      id: databaseId,
      name: 'Shared Database $databaseId',
      ownerId: 'unknown',
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      collaborators: {},
      version: '1',
      lastSync: DateTime.now(),
    );
  }

  Future<void> exportDatabase(String databaseId) async {
    try {
      final response = await _dio.get(
        '$_serverBaseUrl/CollaborativeDatabase/databases/$databaseId/export',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        // Получаем данные для экспорта
        final exportData = response.data;
        
        // Сохраняем данные локально
        await _dbHelper.saveExportData(databaseId, exportData);
      } else if (response.statusCode == 400) {
        final errorMessage = response.data is Map 
            ? response.data['message'] ?? 'Неизвестная ошибка сервера'
            : 'Неизвестная ошибка сервера';
        
        throw Exception('Ошибка при экспорте базы данных: $errorMessage');
      } else {
        throw Exception('Ошибка при экспорте базы данных: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка в exportDatabase: $e');
      rethrow;
    }
  }
  
  // Метод для сохранения резервной копии базы данных на сервере
  Future<void> saveBackup(String databaseId, BackupData backupData) async {
    try {
      // Подготавливаем данные для отправки
      final jsonData = backupData.toJson();
      print('Подготовка данных для резервной копии базы $databaseId: ' +
            '${jsonData['notes']?.length ?? 0} заметок, ' +
            '${jsonData['images']?.length ?? 0} изображений');
            
      final preparedData = {
        'databaseId': databaseId,
        'folders': jsonData['folders'] ?? [],
        'notes': jsonData['notes'] ?? [],
        'scheduleEntries': jsonData['scheduleEntries'] ?? [],
        'pinboardNotes': jsonData['pinboardNotes'] ?? [],
        'connections': jsonData['connections'] ?? [],
        'images': jsonData['images'] ?? [], // Используем тот же ключ 'images', что и в toJson
        'lastModified': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'userId': _authService.getCurrentUserId() ?? "unknown",
      };
      
      // Отправляем данные на сервер
      final response = await _dio.post(
        '$_serverBaseUrl/Database/$databaseId/backup',
        data: preparedData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Резервная копия базы данных успешно сохранена на сервере');
      } else {
        print('Ошибка при сохранении резервной копии: ${response.statusCode}');
        // Не выбрасываем исключение, чтобы не прерывать работу приложения
      }
    } catch (e) {
      print('Ошибка при сохранении резервной копии базы данных: $e');
      // Не перебрасываем исключение, чтобы не прерывать работу приложения
    }
  }

  /// Проверяет, доступен ли сервер
  Future<bool> isServerAvailable() async {
    // Выполняем до 3 попыток проверки с интервалом 1 секунда
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        // При повторных попытках ждем немного перед запросом
        if (attempt > 1) {
          await Future.delayed(Duration(seconds: 1));
        }
        
        final response = await _dio.get(
          '$_serverBaseUrl/Service/status',
          options: Options(
            validateStatus: (status) => true,
            receiveTimeout: const Duration(seconds: 3),
            sendTimeout: const Duration(seconds: 2),
          ),
        ).timeout(Duration(seconds: 3), onTimeout: () {
          throw TimeoutException('Таймаут при проверке доступности сервера');
        });
        
        if (response.statusCode == 200) {
          // Проверяем, есть ли ответ и содержит ли он ожидаемые данные
          final data = response.data;
          if (data != null && 
             (data is Map && data.containsKey('status') || 
              data is String && data.contains('available'))) {
            print('Сервер доступен (попытка $attempt)');
            return true;
          } 
          
          print('Сервер вернул неожиданный формат данных (попытка $attempt)');
          
          // Если полученный ответ не соответствует ожидаемому формату, 
          // но статус код правильный, считаем сервер доступным
          if (attempt == 3) {
            print('Считаем сервер доступным, несмотря на неожиданный формат данных');
            return true;
          }
        } else {
          print('Сервер вернул неверный статус ${response.statusCode} (попытка $attempt)');
        }
        
        // Если получен недопустимый статус, пробуем еще попытку
        if (attempt < 3) continue;
        
        return false;
      } catch (e) {
        print('Ошибка при проверке доступности сервера (попытка $attempt): $e');
        
        // На последней попытке возвращаем false
        if (attempt == 3) {
          return false;
        }
        
        // При ошибках соединения или таймаутах пробуем еще раз
        if (e is DioException) {
          // Увеличиваем таймаут для следующей попытки
          _dio.options.receiveTimeout = Duration(seconds: 4 + attempt);
          _dio.options.connectTimeout = Duration(seconds: 3 + attempt);
        }
      }
    }
    
    // Если все попытки не удались, считаем сервер недоступным
    return false;
  }

  /// Метод для периодической проверки состояния сервера
  Future<void> startServerHealthCheck({
    Duration interval = const Duration(minutes: 5),
    Function(bool)? onStatusChanged,
  }) async {
    // Отменяем существующий таймер, если он был
    _stopServerHealthCheck();
    
    // Инициализируем последний статус
    bool lastStatus;
    try {
      lastStatus = await isServerAvailable()
          .timeout(Duration(seconds: 5), onTimeout: () => false);
    } catch (e) {
      print('Ошибка при начальной проверке состояния сервера: $e');
      lastStatus = false;
    }
    
    // Уведомляем о начальном статусе
    if (onStatusChanged != null) {
      try {
        onStatusChanged(lastStatus);
      } catch (e) {
        print('Ошибка при вызове обработчика изменения статуса: $e');
      }
    }
    
    int consecutiveFailures = 0;
    
    // Создаем новый таймер для проверки состояния сервера и сохраняем его
    _healthCheckTimer = Timer.periodic(interval, (timer) async {
      try {
        bool currentStatus = await isServerAvailable()
            .timeout(Duration(seconds: 5), onTimeout: () {
          print('Таймаут при проверке состояния сервера в периодической проверке');
          return false;
        });
        
        // Сбрасываем счетчик при успешной проверке
        if (currentStatus) {
          consecutiveFailures = 0;
        } else {
          // Увеличиваем счетчик для неудачных проверок
          consecutiveFailures++;
        }
        
        // Если статус изменился, уведомляем слушателя
        if (currentStatus != lastStatus && onStatusChanged != null) {
          try {
            onStatusChanged(currentStatus);
          } catch (callbackError) {
            print('Ошибка при вызове обработчика изменения статуса: $callbackError');
          }
        }
        
        lastStatus = currentStatus;
        
        // Адаптируем интервал проверки в зависимости от состояния
        // Если сервер долго недоступен, уменьшаем частоту проверок
        if (!currentStatus && consecutiveFailures > 5) {
          // Если таймер еще активен, останавливаем его и создаем новый с большим интервалом
          if (_healthCheckTimer != null && _healthCheckTimer!.isActive) {
            _healthCheckTimer!.cancel();
            _healthCheckTimer = Timer.periodic(
              Duration(minutes: math.min(20, 5 + consecutiveFailures)), 
              (t) async {
                // Выполняем ту же проверку, что и в основном таймере
                try {
                  bool status = await isServerAvailable()
                      .timeout(Duration(seconds: 5), onTimeout: () => false);
                  
                  if (status != lastStatus && onStatusChanged != null) {
                    try {
                      onStatusChanged(status);
                    } catch (e) {
                      print('Ошибка при вызове обработчика изменения статуса: $e');
                    }
                  }
                  
                  lastStatus = status;
                  
                  if (status) {
                    // Возвращаемся к стандартному интервалу при восстановлении соединения
                    consecutiveFailures = 0;
                    _healthCheckTimer!.cancel();
                    _healthCheckTimer = Timer.periodic(interval, (t) async {
                      try {
                        bool status = await isServerAvailable()
                            .timeout(Duration(seconds: 5), onTimeout: () => false);
                        
                        if (status != lastStatus && onStatusChanged != null) {
                          try {
                            onStatusChanged(status);
                          } catch (e) {
                            print('Ошибка при вызове обработчика изменения статуса: $e');
                          }
                        }
                        
                        lastStatus = status;
                      } catch (e) {
                        print('Ошибка при проверке состояния сервера: $e');
                      }
                    });
                    print('Интервал проверки возвращен к стандартному');
                  }
                } catch (e) {
                  print('Ошибка при проверке состояния сервера: $e');
                }
              }
            );
            print('Интервал проверки увеличен из-за недоступности сервера');
          }
        }
      } catch (e) {
        print('Ошибка при проверке состояния сервера: $e');
        
        // Увеличиваем счетчик ошибок
        consecutiveFailures++;
        
        // Если произошла ошибка, считаем, что сервер недоступен только после нескольких 
        // последовательных неудачных попыток, чтобы исключить временные проблемы с сетью
        if (lastStatus && consecutiveFailures > 2 && onStatusChanged != null) {
          try {
            lastStatus = false;
            onStatusChanged(false);
          } catch (callbackError) {
            print('Ошибка при вызове обработчика изменения статуса после ошибки: $callbackError');
          }
        }
      }
    });
  }
  
  // Переменная для хранения таймера проверки состояния сервера
  Timer? _healthCheckTimer;
  
  /// Остановить периодическую проверку состояния сервера
  void _stopServerHealthCheck() {
    if (_healthCheckTimer != null && _healthCheckTimer!.isActive) {
      _healthCheckTimer!.cancel();
      _healthCheckTimer = null;
    }
  }
  
  /// Деструктор для освобождения ресурсов
  void dispose() {
    _stopServerHealthCheck();
  }
} 