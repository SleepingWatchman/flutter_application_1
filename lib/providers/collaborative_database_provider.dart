import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/collaborative_database.dart';
import '../services/collaborative_database_service.dart';
import '../services/auth_service.dart';
import '../db/database_helper.dart';
import '../models/backup_data.dart';
import 'package:oktoast/oktoast.dart';
import 'database_provider.dart';
import 'package:provider/provider.dart';
import 'dart:async';

class CollaborativeDatabaseProvider extends ChangeNotifier {
  final CollaborativeDatabaseService _service;
  final DatabaseHelper _dbHelper;
  DatabaseProvider? _databaseProvider;
  List<CollaborativeDatabase> _databases = [];
  String? _currentDatabaseId;
  bool _isLoading = false;
  String? _error;
  bool _isUsingSharedDatabase = false;
  bool _isServerAvailable = false;

  CollaborativeDatabaseProvider(this._service, this._dbHelper) {
    // Запускаем проверку состояния сервера
    _initServerHealthCheck();
  }

  List<CollaborativeDatabase> get databases => _databases;
  String? get currentDatabaseId => _currentDatabaseId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isUsingSharedDatabase => _isUsingSharedDatabase;
  bool get isServerAvailable => _isServerAvailable;

  void setDatabaseProvider(DatabaseProvider provider) {
    _databaseProvider = provider;
  }

  Future<void> loadDatabases() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _databases = await _service.getDatabases();
    } catch (e) {
      _error = e.toString();
      print('Ошибка при загрузке баз данных: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createDatabase(String name) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final newDatabase = await _service.createDatabase(name);
      _databases.add(newDatabase);
      
      // Инициализируем локальную копию базы
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

  Future<void> deleteDatabase(String databaseId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _service.deleteDatabase(databaseId);
      _databases.removeWhere((db) => db.id == databaseId);
      
      if (_currentDatabaseId == databaseId) {
        await switchToPersonalDatabase();
      }
    } catch (e) {
      _error = e.toString();
      print('Ошибка при удалении базы данных: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> leaveDatabase(String databaseId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _service.leaveDatabase(databaseId);
      _databases.removeWhere((db) => db.id == databaseId);
      
      if (_currentDatabaseId == databaseId) {
        await switchToPersonalDatabase();
      }
    } catch (e) {
      _error = e.toString();
      print('Ошибка при выходе из базы данных: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addCollaborator(String databaseId, String userId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _service.addCollaborator(databaseId, userId);
      await loadDatabases(); // Обновляем список баз для отражения изменений
    } catch (e) {
      _error = e.toString();
      print('Ошибка при добавлении соавтора: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeCollaborator(String databaseId, String userId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _service.removeCollaborator(databaseId, userId);
      await loadDatabases(); // Обновляем список баз для отражения изменений
    } catch (e) {
      _error = e.toString();
      print('Ошибка при удалении соавтора: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchToDatabase(String databaseId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('Переключение на базу данных: $databaseId');
      
      // Проверяем доступность сервера перед продолжением
      bool isServerAvailable = await _service.isServerAvailable();
      if (!isServerAvailable) {
        // Даже при недоступности сервера, мы можем продолжить работу
        // с локальной копией базы данных, поэтому просто показываем
        // предупреждение, но не прерываем операцию.
        showToast('Сервер недоступен. Будет использована локальная копия без синхронизации.');
        print('Сервер недоступен, продолжаем с локальной копией');
      }
      
      // Устанавливаем таймаут на инициализацию
      bool initComplete = false;
      
      // Запускаем таймер, который отменит операцию, если она займет слишком много времени
      Timer timeoutTimer = Timer(Duration(seconds: 30), () {
        if (!initComplete) {
          print('Превышен таймаут инициализации базы $databaseId, отмена операции');
          _isLoading = false;
          _error = 'Превышен таймаут инициализации базы';
          notifyListeners();
        }
      });
      
      // Предварительно устанавливаем значение, чтобы DatabaseProvider мог использовать
      // правильный идентификатор базы данных при выполнении операций
      _currentDatabaseId = databaseId;
      _isUsingSharedDatabase = true;
      
      // Закрываем текущее подключение к базе данных, чтобы избежать блокировок
      try {
        await _dbHelper.closeDatabase();
        print('База данных закрыта перед переключением на $databaseId');
        
        // Важно: добавляем небольшую задержку, чтобы дать системе время освободить ресурсы
        await Future.delayed(Duration(milliseconds: 500));
      } catch (e) {
        print('Ошибка при закрытии базы данных: $e');
        // Продолжаем работу даже при ошибке
      }
      
      // Инициализируем локальную копию базы в отдельном блоке try/catch
      bool databaseInitialized = false;
      try {
        // Сначала пробуем заново открыть базу данных
        await _dbHelper.reopenDatabase();
        
        await _dbHelper.initializeSharedDatabase(databaseId)
            .timeout(Duration(seconds: 15), onTimeout: () {
          print('Таймаут при инициализации базы данных $databaseId');
          return;
        });
        
        // Добавляем небольшую задержку для стабилизации соединения
        await Future.delayed(Duration(milliseconds: 500));
        databaseInitialized = true;
      } catch (e) {
        print('Ошибка при инициализации базы $databaseId: $e');
        // Пробуем заново открыть базу данных после ошибки
        try {
          await _dbHelper.reopenDatabase();
          await Future.delayed(Duration(milliseconds: 500));
        } catch (reopenError) {
          print('Ошибка при повторном открытии базы данных: $reopenError');
        }
      }
      
      // Если не удалось инициализировать базу, пробуем еще раз с большим таймаутом
      if (!databaseInitialized) {
        try {
          print('Повторная попытка инициализации базы данных $databaseId');
          await _dbHelper.initializeSharedDatabase(databaseId)
              .timeout(Duration(seconds: 30), onTimeout: () {
            print('Таймаут при повторной инициализации базы данных $databaseId');
            throw TimeoutException('Таймаут при инициализации базы данных');
          });
          databaseInitialized = true;
        } catch (e) {
          print('Повторная ошибка при инициализации базы $databaseId: $e');
          // Если снова произошла ошибка, возвращаемся к локальной базе
          if (_error == null) {
            _error = 'Не удалось инициализировать базу данных: $e';
          }
          
          _isUsingSharedDatabase = false;
          _currentDatabaseId = null;
          
          // Пытаемся открыть локальную базу и уведомляем пользователя
          try {
            await _dbHelper.reopenDatabase();
            showToast('Не удалось переключиться на совместную базу. Используется локальная база.');
          } catch (reopenError) {
            print('Критическая ошибка при открытии локальной базы: $reopenError');
            showToast('Критическая ошибка базы данных. Перезапустите приложение.');
          }
          
          // Завершаем операцию с ошибкой
          _isLoading = false;
          timeoutTimer.cancel();
          notifyListeners();
          return;
        }
      }
      
      // Синхронизируем с DatabaseProvider только если база была инициализирована
      if (databaseInitialized && _databaseProvider != null) {
        try {
          await _databaseProvider!.switchToDatabase(databaseId)
              .timeout(Duration(seconds: 15), onTimeout: () {
            print('Таймаут при переключении DatabaseProvider на базу $databaseId');
            return;
          });
        } catch (e) {
          print('Ошибка при синхронизации с DatabaseProvider: $e');
          // Продолжаем процесс даже при ошибке
        }
      }
      
      // Отмечаем, что инициализация завершена
      initComplete = true;
      timeoutTimer.cancel();
      
      // Пытаемся импортировать данные новой базы
      try {
        // Запускаем индикатор загрузки
        bool importComplete = false;
        
        Timer? progressTimer = Timer.periodic(Duration(seconds: 2), (timer) {
          if (!importComplete) {
            print('Импорт данных в процессе...');
            notifyListeners(); // Обновляем UI для индикации
          } else {
            timer.cancel();
          }
        });
        
        try {
          await _service.importDatabase(databaseId)
              .timeout(Duration(seconds: 20), onTimeout: () {
            print('Таймаут при импорте данных для базы $databaseId');
            throw TimeoutException('Таймаут при импорте данных');
          });
          
          // Проверяем, есть ли какие-то данные после импорта
          // Даем небольшую задержку перед запросом данных
          await Future.delayed(Duration(milliseconds: 500));
          
          // Проверяем существующие данные в асинхронном блоке с таймаутом
          List notes = [];
          List folders = [];
          List pinboardNotes = [];
          List scheduleEntries = [];
          
          try {
            await Future.wait([
              _dbHelper.getAllNotes(databaseId).then((value) => notes = value),
              _dbHelper.getFolders(databaseId).then((value) => folders = value),
              _dbHelper.getPinboardNotes(databaseId).then((value) => pinboardNotes = value),
              _dbHelper.getScheduleEntries(databaseId).then((value) => scheduleEntries = value),
            ]).timeout(Duration(seconds: 15), onTimeout: () {
              print('Таймаут при проверке данных в базе $databaseId');
              return [];
            });
          } catch (e) {
            print('Ошибка при проверке данных базы: $e');
            // Продолжаем работу
          }
          
          bool hasData = notes.isNotEmpty || folders.isNotEmpty || 
                        pinboardNotes.isNotEmpty || scheduleEntries.isNotEmpty;
                        
          print('После импорта база $databaseId содержит заметок: ${notes.length}, папок: ${folders.length}');
          
          // Завершаем индикацию
          importComplete = true;
          progressTimer?.cancel();
          progressTimer = null;
          
          // Если данных нет или их мало, запускаем синхронизацию
          if (!hasData || notes.length < 3) {
            try {
              print('Запуск синхронизации для базы $databaseId после импорта');
              await syncDatabase()
                  .timeout(Duration(seconds: 20), onTimeout: () {
                print('Таймаут при синхронизации базы $databaseId после импорта');
                return;
              });
              
              // Добавляем небольшую задержку перед запросом данных
              await Future.delayed(Duration(milliseconds: 500));
              
              // Проверяем еще раз после синхронизации
              if (!hasData) {
                // Снова проверяем в асинхронном блоке с таймаутом
                List notesAfterSync = [];
                List foldersAfterSync = [];
                
                try {
                  await Future.wait([
                    _dbHelper.getAllNotes(databaseId).then((value) => notesAfterSync = value),
                    _dbHelper.getFolders(databaseId).then((value) => foldersAfterSync = value),
                  ]).timeout(Duration(seconds: 10), onTimeout: () {
                    print('Таймаут при проверке данных после синхронизации');
                    return [];
                  });
                  
                  hasData = notesAfterSync.isNotEmpty || foldersAfterSync.isNotEmpty;
                  print('После синхронизации база $databaseId содержит заметок: ${notesAfterSync.length}');
                } catch (e) {
                  print('Ошибка при проверке данных после синхронизации: $e');
                  // Продолжаем работу
                }
              }
              
              // Если данных все еще нет, создадим демо-данные
              if (!hasData) {
                print('Создание демо-данных после неудачной синхронизации');
                await _createDemoData(databaseId);
              }
            } catch (syncError) {
              print('Ошибка при первичной синхронизации базы: $syncError');
              // Создаем демо-данные, если синхронизация не удалась
              if (!hasData) {
                await _createDemoData(databaseId);
              }
            }
          } else {
            print('База уже содержит данные, пропускаем начальную синхронизацию');
          }
        } catch (e) {
          // Завершаем индикацию при ошибке
          importComplete = true;
          progressTimer?.cancel();
          progressTimer = null;
          
          print('Ошибка при импорте базы данных: $e');
          // При ошибке импорта создаем демо-данные
          await _createDemoData(databaseId);
        }
        
        // Убедимся, что DatabaseProvider знает о необходимости обновить интерфейс
        if (_databaseProvider != null) {
          _databaseProvider!.setNeedsUpdate(true);
          // Принудительно вызываем обновление
          _databaseProvider!.notifyAllListeners();
        }
        
        // Вызываем notifyListeners несколько раз с небольшой задержкой,
        // чтобы гарантировать обновление интерфейса
        notifyListeners();
        await Future.delayed(Duration(milliseconds: 150));
        notifyListeners();
        await Future.delayed(Duration(milliseconds: 300));
        notifyListeners();
        
        // Показываем уведомление пользователю
        showToast('Успешно переключено на совместную базу данных');
      } catch (e) {
        print('Ошибка при работе с базой данных: $e');
        _error = e.toString();
        
        // Даже если были ошибки, пытаемся продолжить работу с созданной базой
        showToast('Произошла ошибка, создана минимальная база для работы');
        
        // Создаем демо-данные
        await _createDemoData(databaseId);
        
        if (_databaseProvider != null) {
          _databaseProvider!.setNeedsUpdate(true);
          _databaseProvider!.notifyAllListeners();
        }
        
        // Принудительное обновление интерфейса
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      print('Ошибка при переключении на базу данных: $e');
      showToast('Ошибка при переключении на базу данных: ${e.toString().substring(0, math.min(100, e.toString().length))}');
      
      // В случае критической ошибки пытаемся вернуться к локальной базе
      try {
        _isUsingSharedDatabase = false;
        _currentDatabaseId = null;
        
        await switchToPersonalDatabase()
            .timeout(Duration(seconds: 15), onTimeout: () {
          print('Таймаут при возврате к локальной базе');
          return;
        });
      } catch (rollbackError) {
        print('Не удалось вернуться к локальной базе: $rollbackError');
        // Принудительно выставляем флаги для работы с локальной базой
        _isUsingSharedDatabase = false;
        _currentDatabaseId = null;
        
        // Последняя попытка открыть локальную базу
        try {
          await _dbHelper.reopenDatabase();
          if (_databaseProvider != null) {
            await _databaseProvider!.switchToDatabase(null);
          }
        } catch (finalError) {
          print('Критическая ошибка при переключении на локальную базу: $finalError');
          showToast('Критическая ошибка базы данных. Перезапустите приложение.');
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchToPersonalDatabase() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('Переключение на базу данных: локальную');
      
      // Устанавливаем таймаут на инициализацию
      bool initComplete = false;
      
      // Запускаем таймер, который отменит операцию, если она займет слишком много времени
      Timer timeoutTimer = Timer(Duration(seconds: 30), () {
        if (!initComplete) {
          print('Превышен таймаут при переключении на локальную базу, отмена операции');
          _isLoading = false;
          notifyListeners();
        }
      });
      
      // Запоминаем текущий идентификатор базы данных для создания резервной копии
      String? previousDatabaseId = _currentDatabaseId;
      bool wasSharingEnabled = _isUsingSharedDatabase;
      
      // Предварительно устанавливаем значения, чтобы метод завершился корректно даже с ошибкой
      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
      
      // Если есть текущая совместная база, сохраняем ее данные перед переключением
      if (previousDatabaseId != null && wasSharingEnabled) {
        try {
          // Запускаем индикатор процесса создания резервной копии
          bool backupComplete = false;
          
          Timer? progressTimer = Timer.periodic(Duration(seconds: 1), (timer) {
            if (!backupComplete) {
              print('Создание резервной копии в процессе...');
              notifyListeners(); // Обновляем UI для индикации
            } else {
              timer.cancel();
            }
          });
          
          try {
            // Создаем резервную копию текущих данных с таймаутом
            BackupData? backupData;
            try {
              backupData = await _dbHelper.createBackup(previousDatabaseId)
                  .timeout(Duration(seconds: 20), onTimeout: () {
                print('Таймаут при создании резервной копии для базы $previousDatabaseId');
                // Возвращаем пустую резервную копию, чтобы не блокировать процесс
                return BackupData(
                  folders: [],
                  notes: [],
                  scheduleEntries: [],
                  pinboardNotes: [],
                  connections: [],
                  noteImages: []
                );
              });
              print('Резервная копия для базы $previousDatabaseId создана');
            } catch (backupError) {
              print('Ошибка при создании резервной копии: $backupError');
              
              // В случае ошибки создаём пустую резервную копию
              backupData = BackupData(
                folders: [],
                notes: [],
                scheduleEntries: [],
                pinboardNotes: [],
                connections: [],
                noteImages: []
              );
            }
            
            // Прекращаем индикацию процесса
            backupComplete = true;
            progressTimer?.cancel();
            progressTimer = null;
            
            // Проверяем, есть ли данные в резервной копии
            bool hasData = backupData.folders.isNotEmpty || 
                          backupData.notes.isNotEmpty || 
                          backupData.scheduleEntries.isNotEmpty || 
                          backupData.pinboardNotes.isNotEmpty;
            
            // Сохраняем копию на сервере только если он доступен и есть данные
            if (_isServerAvailable && hasData) {
              try {
                await _service.saveBackup(previousDatabaseId, backupData)
                    .timeout(Duration(seconds: 15), onTimeout: () {
                  print('Таймаут при сохранении резервной копии на сервере');
                  return;
                });
                print('Резервная копия успешно сохранена на сервере');
              } catch (e) {
                print('Ошибка при сохранении резервной копии на сервере: $e');
                // Не прерываем процесс при ошибке сохранения
              }
            } else {
              if (!_isServerAvailable) {
                print('Сервер недоступен, пропускаем сохранение резервной копии на сервере');
              }
              if (!hasData) {
                print('Нет данных для сохранения в резервной копии');
              }
            }
            
            // Сохраняем персональную резервную копию локально с таймаутом
            if (hasData && _databaseProvider != null) {
              try {
                await _databaseProvider!.savePersonalBackup(backupData)
                    .timeout(Duration(seconds: 15), onTimeout: () {
                  print('Таймаут при сохранении персональной резервной копии');
                  return;
                });
                print('Персональная резервная копия успешно сохранена');
              } catch (e) {
                print('Ошибка при сохранении персональной резервной копии: $e');
                // Не прерываем процесс при ошибке сохранения
              }
            } else {
              print('Пропускаем сохранение пустой персональной резервной копии');
            }
          } catch (e) {
            // Прекращаем индикацию при ошибке
            backupComplete = true;
            progressTimer?.cancel();
            progressTimer = null;
            
            print('Ошибка при создании резервной копии: $e');
            // Продолжаем процесс даже если сохранение не удалось
          }
        } catch (e) {
          print('Ошибка при сохранении данных перед переключением: $e');
          // Продолжаем процесс даже если сохранение не удалось
        }
      }

      // Закрываем текущее подключение к базе данных, чтобы избежать блокировок
      try {
        await _dbHelper.closeDatabase();
        print('База данных закрыта перед переключением на локальную');
        
        // Добавляем небольшую задержку, чтобы дать системе время освободить ресурсы
        await Future.delayed(Duration(milliseconds: 500));
      } catch (e) {
        print('Ошибка при закрытии базы данных: $e');
        // Продолжаем работу даже при ошибке
      }

      // Отмечаем, что основной процесс завершен
      initComplete = true;
      timeoutTimer.cancel();

      // Переключаемся на личную базу - по умолчанию используем основную базу данных
      bool databaseInitialized = false;
      try {
        // Сначала пробуем заново открыть базу данных
        await _dbHelper.reopenDatabase();
        
        // Инициализируем основную базу данных
        await _dbHelper.database.timeout(Duration(seconds: 10));
        
        // Добавляем небольшую задержку для стабилизации соединения
        await Future.delayed(Duration(milliseconds: 500));
        databaseInitialized = true;
      } catch (e) {
        print('Ошибка при инициализации основной базы данных: $e');
        // Пробуем заново открыть базу данных после ошибки
        try {
          await _dbHelper.reopenDatabase();
          await Future.delayed(Duration(milliseconds: 500));
          
          // Еще одна попытка
          await _dbHelper.database.timeout(Duration(seconds: 15));
          databaseInitialized = true;
        } catch (reopenError) {
          print('Ошибка при повторном открытии базы данных: $reopenError');
          // Отправляем критическую ошибку
          _error = 'Критическая ошибка при переключении на локальную базу: $reopenError';
          showToast('Критическая ошибка базы данных. Перезапустите приложение.');
        }
      }
      
      if (databaseInitialized) {
        // Проверяем, не были ли значения сброшены в другом потоке
        _currentDatabaseId = null;
        _isUsingSharedDatabase = false;
        
        // Синхронизируем с DatabaseProvider с таймаутом
        if (_databaseProvider != null) {
          try {
            await _databaseProvider!.switchToDatabase(null)
                .timeout(Duration(seconds: 15), onTimeout: () {
              print('Таймаут при переключении DatabaseProvider на локальную базу');
              return;
            });
            _databaseProvider!.setNeedsUpdate(true);
            // Принудительно вызываем обновление
            _databaseProvider!.notifyAllListeners();
          } catch (e) {
            print('Ошибка при синхронизации с DatabaseProvider: $e');
            // Не выбрасываем исключение, чтобы завершить переключение
          }
        }
        
        // Пытаемся восстановить данные из резервной копии, если база была пуста
        try {
          // Проверяем, есть ли данные в локальной базе
          final notes = await _dbHelper.getAllNotes(null)
              .timeout(Duration(seconds: 5), onTimeout: () => []);
          
          final folders = await _dbHelper.getFolders(null)
              .timeout(Duration(seconds: 5), onTimeout: () => []);
              
          final hasData = notes.isNotEmpty || folders.isNotEmpty;
          
          // Если база пуста, пытаемся восстановить из персональной резервной копии
          if (!hasData && _databaseProvider != null) {
            try {
              print('Локальная база пуста, пытаемся восстановить из резервной копии');
              
              final backup = await _databaseProvider!.getPersonalBackup()
                  .timeout(Duration(seconds: 10), onTimeout: () => null);
                  
              if (backup != null && 
                (backup.notes.isNotEmpty || backup.folders.isNotEmpty || 
                 backup.scheduleEntries.isNotEmpty || backup.pinboardNotes.isNotEmpty)) {
                
                print('Найдена резервная копия, восстанавливаем данные');
                await _databaseProvider!.restoreFromBackup(backup)
                    .timeout(Duration(seconds: 20), onTimeout: () {
                  print('Таймаут при восстановлении из резервной копии');
                  return;
                });
                
                print('Данные успешно восстановлены из резервной копии');
              } else {
                print('Резервная копия не найдена или пуста');
              }
            } catch (e) {
              print('Ошибка при восстановлении из резервной копии: $e');
              // Не прерываем процесс при ошибке восстановления
            }
          }
        } catch (e) {
          print('Ошибка при проверке данных локальной базы: $e');
          // Не прерываем процесс
        }
        
        // Принудительное обновление интерфейса с небольшой задержкой
        notifyListeners();
        await Future.delayed(Duration(milliseconds: 150));
        notifyListeners();
        await Future.delayed(Duration(milliseconds: 300));
        notifyListeners();
        
        showToast('Переключено на личную базу данных');
      }
    } catch (e) {
      _error = e.toString();
      print('Ошибка при переключении на личную базу: $e');
      showToast('Ошибка при переключении на личную базу: ${e.toString().substring(0, math.min(100, e.toString().length))}');
      
      // Гарантируем, что мы находимся в режиме личной базы
      _currentDatabaseId = null;
      _isUsingSharedDatabase = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncDatabase() async {
    if (!_isUsingSharedDatabase || _currentDatabaseId == null) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('Начинаем синхронизацию базы данных: $_currentDatabaseId');
      
      // Устанавливаем таймаут на синхронизацию
      bool syncComplete = false;
      
      // Запускаем таймер для индикации пользователю
      Timer? progressTimer = Timer.periodic(Duration(seconds: 2), (timer) {
        if (!syncComplete) {
          print('Синхронизация в процессе...');
          notifyListeners(); // Обновляем UI для отображения индикатора загрузки
        } else {
          timer.cancel();
        }
      });
      
      try {
        // Проверяем доступность сервера перед синхронизацией
        bool serverAvailable = await _service.isServerAvailable()
            .timeout(Duration(seconds: 5), onTimeout: () => false);
        
        if (!serverAvailable) {
          throw Exception('Сервер недоступен для синхронизации');
        }
        
        // Сохраняем количество записей расписания до синхронизации
        List<dynamic> scheduleEntriesBefore = [];
        try {
          scheduleEntriesBefore = await _dbHelper.getScheduleEntries(_currentDatabaseId)
              .timeout(Duration(seconds: 5), onTimeout: () => []);
          print('До синхронизации база $_currentDatabaseId содержит ${scheduleEntriesBefore.length} записей расписания');
        } catch (e) {
          print('Ошибка при получении записей расписания до синхронизации: $e');
        }
        
        // Добавляем небольшую задержку для стабилизации состояния
        await Future.delayed(Duration(milliseconds: 300));
        
        // Создаем локальную резервную копию перед синхронизацией
        BackupData? backupBeforeSync;
        try {
          backupBeforeSync = await _dbHelper.createBackup(_currentDatabaseId)
              .timeout(Duration(seconds: 15), onTimeout: () => BackupData(folders: [], notes: [], scheduleEntries: [], pinboardNotes: [], connections: [], noteImages: []));
          if (backupBeforeSync != null) {
            print('Создана резервная копия перед синхронизацией: ${backupBeforeSync.notes.length} заметок, ${backupBeforeSync.scheduleEntries.length} записей расписания');
          }
        } catch (e) {
          print('Ошибка при создании резервной копии перед синхронизацией: $e');
        }
        
        // Первая попытка синхронизации с таймаутом
        bool syncSuccessful = false;
        try {
          // Вызываем метод синхронизации с таймаутом
          await _service.syncDatabase(_currentDatabaseId!)
              .timeout(Duration(seconds: 30), onTimeout: () {
            print('Превышено время синхронизации базы $_currentDatabaseId');
            throw TimeoutException('Превышено время синхронизации');
          });
          
          syncSuccessful = true;
        } catch (e) {
          print('Ошибка при первой попытке синхронизации: $e');
          
          // Если первая попытка не удалась, пробуем еще раз после небольшой паузы
          try {
            await Future.delayed(Duration(seconds: 2));
            print('Повторная попытка синхронизации базы $_currentDatabaseId');
            
            // Попытка закрыть и заново открыть базу данных для избежания блокировок
            try {
              await _dbHelper.closeDatabase();
              await Future.delayed(Duration(milliseconds: 500));
              await _dbHelper.reopenDatabase();
              await Future.delayed(Duration(milliseconds: 500));
            } catch (dbError) {
              print('Ошибка при перезапуске базы данных: $dbError');
              // Продолжаем синхронизацию
            }
            
            await _service.syncDatabase(_currentDatabaseId!)
                .timeout(Duration(seconds: 45), onTimeout: () {
              print('Превышено время повторной синхронизации базы $_currentDatabaseId');
              throw TimeoutException('Превышено время повторной синхронизации');
            });
            
            syncSuccessful = true;
          } catch (retryError) {
            print('Ошибка при повторной попытке синхронизации: $retryError');
            throw retryError; // Пробрасываем ошибку во внешний блок
          }
        }
        
        // Помечаем синхронизацию как успешную
        syncComplete = true;
        progressTimer?.cancel();
        progressTimer = null;
        
        // Проверяем данные после синхронизации
        if (syncSuccessful) {
          try {
            final notes = await _dbHelper.getAllNotes(_currentDatabaseId!)
                .timeout(Duration(seconds: 5), onTimeout: () => []);
            
            final folders = await _dbHelper.getFolders(_currentDatabaseId!)
                .timeout(Duration(seconds: 5), onTimeout: () => []);
            
            final scheduleEntriesAfter = await _dbHelper.getScheduleEntries(_currentDatabaseId!)
                .timeout(Duration(seconds: 5), onTimeout: () => []);
            
            print('После синхронизации база $_currentDatabaseId содержит заметок: ${notes.length}, папок: ${folders.length}, записей расписания: ${scheduleEntriesAfter.length}');
            
            // Проверяем, не потерялись ли записи расписания при синхронизации
            if (scheduleEntriesAfter.isEmpty && scheduleEntriesBefore.isNotEmpty && backupBeforeSync != null) {
              print('ВНИМАНИЕ: Записи расписания потеряны после синхронизации! Восстанавливаем из резервной копии.');
              
              // Пробуем восстановить только записи расписания из локальной резервной копии
              try {
                // Закрываем базу, чтобы избежать блокировок
                await _dbHelper.closeDatabase();
                await Future.delayed(Duration(milliseconds: 500));
                await _dbHelper.reopenDatabase();
                
                // Восстанавливаем только записи расписания
                await _dbHelper.executeTransaction((txn) async {
                  // Очищаем существующие записи расписания
                  await txn.delete(
                    'schedule_entries',
                    where: 'database_id = ?',
                    whereArgs: [_currentDatabaseId],
                  );
                  
                  // Восстанавливаем записи расписания из резервной копии
                  if (backupBeforeSync != null && backupBeforeSync.scheduleEntries.isNotEmpty) {
                    for (var entry in backupBeforeSync.scheduleEntries) {
                      entry['database_id'] = _currentDatabaseId;
                      await _dbHelper.insertScheduleEntryForBackup(entry, txn);
                    }
                    print('Восстановлено ${backupBeforeSync.scheduleEntries.length} записей расписания из резервной копии');
                  } else {
                    print('Нет записей расписания в резервной копии для восстановления.');
                  }
                });
              } catch (e) {
                print('Ошибка при восстановлении записей расписания: $e');
              }
            }
            
            // Если после синхронизации данных нет, возможно, что-то пошло не так
            if (notes.isEmpty && folders.isEmpty) {
              print('Предупреждение: после синхронизации данных нет');
              
              // Пытаемся восстановить из резервной копии, если она есть
              if (backupBeforeSync != null && (backupBeforeSync.notes.isNotEmpty || backupBeforeSync.folders.isNotEmpty)) {
                print('Восстанавливаем данные из резервной копии после неудачной синхронизации');
                try {
                  // Закрываем базу, чтобы избежать блокировок
                  await _dbHelper.closeDatabase();
                  await Future.delayed(Duration(milliseconds: 500));
                  await _dbHelper.reopenDatabase();
                  
                  // Восстанавливаем полностью из резервной копии
                  await _dbHelper.restoreFromBackup(backupBeforeSync, _currentDatabaseId!)
                      .timeout(Duration(seconds: 15), onTimeout: () {
                    print('Таймаут при восстановлении из резервной копии');
                    return;
                  });
                  
                  print('Данные успешно восстановлены из резервной копии');
                } catch (e) {
                  print('Ошибка при восстановлении из резервной копии: $e');
                }
              }
            }
          } catch (checkError) {
            print('Ошибка при проверке данных после синхронизации: $checkError');
            // Не прерываем процесс из-за ошибки проверки
          }
        }
        
        // Принудительно обновляем UI после синхронизации
        if (_databaseProvider != null) {
          _databaseProvider!.setNeedsUpdate(true);
          _databaseProvider!.notifyAllListeners();
        }
        
        print('Синхронизация базы $_currentDatabaseId успешно завершена');
        showToast('Синхронизация успешно завершена');
      } catch (e) {
        print('Ошибка при синхронизации базы $_currentDatabaseId: $e');
        _error = e.toString();
        
        // Останавливаем таймер независимо от результата
        syncComplete = true;
        progressTimer?.cancel();
        progressTimer = null;
        
        // При ошибке синхронизации также обновляем UI
        if (_databaseProvider != null) {
          _databaseProvider!.setNeedsUpdate(true);
          _databaseProvider!.notifyAllListeners();
        }
        
        // Проверяем доступность сервера после ошибки
        try {
          bool serverAvailable = await _service.isServerAvailable()
              .timeout(Duration(seconds: 5), onTimeout: () => false);
          
          _isServerAvailable = serverAvailable;
          
          if (!serverAvailable) {
            showToast('Сервер недоступен. Синхронизация невозможна.');
          } else {
            // Показываем уведомление о проблеме
            showToast('Не удалось синхронизировать базу данных: ${e.toString().substring(0, math.min(100, e.toString().length))}');
          }
        } catch (serverCheckError) {
          print('Ошибка при проверке сервера после синхронизации: $serverCheckError');
          showToast('Не удалось синхронизировать базу данных. Проверьте подключение к сети.');
        }
      }
    } catch (e) {
      _error = e.toString();
      print('Критическая ошибка при синхронизации базы данных: $e');
      showToast('Критическая ошибка при синхронизации: ${e.toString().substring(0, math.min(50, e.toString().length))}');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> exportDatabase(String databaseId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _service.exportDatabase(databaseId);
    } catch (e) {
      _error = e.toString();
      print('Ошибка при экспорте базы данных: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importDatabase(String databaseId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Проверяем доступность сервера перед выполнением операции
      bool isServerAvailable = await _service.isServerAvailable();
      if (!isServerAvailable) {
        _error = 'Сервер недоступен. Операция отменена.';
        showToast('Сервер недоступен. Пожалуйста, проверьте соединение с сетью.');
        notifyListeners();
        return;
      }

      // Проверяем, не импортирована ли уже эта база
      if (_databases.any((db) => db.id == databaseId)) {
        throw Exception('База данных уже импортирована');
      }

      final database = await _service.importDatabase(databaseId);
      
      // Инициализируем локальную копию базы
      await _dbHelper.initializeSharedDatabase(databaseId);
      
      _databases.add(database);
      
      // Показываем уведомление об успешном импорте
      showToast('База данных успешно импортирована');
      
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      // Показываем уведомление об ошибке
      showToast('Ошибка при импорте базы данных: ${e.toString().substring(0, math.min(100, e.toString().length))}');
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool canEditDatabase(String databaseId, String userId) {
    final database = _databases.firstWhere((db) => db.id == databaseId);
    return database.canEdit(userId);
  }

  bool isDatabaseOwner(String databaseId, String userId) {
    final database = _databases.firstWhere((db) => db.id == databaseId);
    return database.isOwner(userId);
  }

  // Вспомогательный метод для создания демонстрационных данных
  Future<void> _createDemoData(String databaseId) async {
    try {
      print('Начало создания демонстрационных данных для базы $databaseId');
      
      // Используем транзакцию для обеспечения целостности данных
      await _dbHelper.executeTransaction((txn) async {
        try {
          // Создаем папки
          final mainFolderId = await _dbHelper.insertFolder({
            'name': 'Демо папка',
            'color': Colors.blue.value,
            'is_expanded': 1,
            'database_id': databaseId,
          });
          
          final secondFolderId = await _dbHelper.insertFolder({
            'name': 'Важные заметки',
            'color': Colors.red.value,
            'is_expanded': 1,
            'database_id': databaseId,
          });
          
          // Текущая дата и время
          final now = DateTime.now();
          final yesterday = now.subtract(Duration(days: 1));
          final tomorrow = now.add(Duration(days: 1));
          
          // Создаем заметки в первой папке
          await _dbHelper.insertNote({
            'title': 'Демо заметка',
            'content': 'Это демонстрационная заметка, созданная автоматически.\n\n'
                      'В этой базе данных можно создавать новые заметки, организовывать их по папкам, '
                      'использовать расписание и делиться данными.',
            'folder_id': mainFolderId,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'database_id': databaseId,
          });
          
          await _dbHelper.insertNote({
            'title': 'Как использовать совместную работу',
            'content': 'Для совместной работы необходимо:\n\n'
                      '1. Создать новую базу данных на экране "Совместная работа"\n'
                      '2. Пригласить соавторов, указав их идентификаторы\n'
                      '3. Соавторы должны принять приглашение\n\n'
                      'После этого все участники могут одновременно работать с общими данными.',
            'folder_id': mainFolderId,
            'created_at': yesterday.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'database_id': databaseId,
          });
          
          // Создаем заметки во второй папке
          await _dbHelper.insertNote({
            'title': 'Важная информация',
            'content': 'Эта заметка содержит важную информацию, которую необходимо сохранить.\n\n'
                      'Вы можете добавить любую информацию в эту заметку.',
            'folder_id': secondFolderId,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'database_id': databaseId,
          });
          
          // Создаем записи в расписании
          await _dbHelper.insertScheduleEntry({
            'date': now.toIso8601String().split('T')[0],
            'time': '${now.hour}:${now.minute}',
            'note': 'Демо событие (сегодня)',
            'database_id': databaseId,
          });
          
          await _dbHelper.insertScheduleEntry({
            'date': tomorrow.toIso8601String().split('T')[0],
            'time': '10:00',
            'note': 'Важная встреча (завтра)',
            'database_id': databaseId,
          });
          
          // Создаем заметку на доске
          await _dbHelper.insertPinboardNote({
            'title': 'Важная задача',
            'content': 'Не забыть выполнить эту задачу до конца недели',
            'position_x': 100,
            'position_y': 100,
            'color': Colors.amber.value,
            'database_id': databaseId,
          });
          
          // Добавляем еще одну заметку на доске
          await _dbHelper.insertPinboardNote({
            'title': 'Идея для проекта',
            'content': 'Создать новую функцию для...',
            'position_x': 300,
            'position_y': 200,
            'color': Colors.lightGreen.value,
            'database_id': databaseId,
          });
          
          print('Демонстрационные данные успешно созданы для базы $databaseId');
        } catch (e) {
          print('Ошибка в транзакции при создании демо-данных: $e');
          // В контексте транзакции пробрасываем ошибку для отката
          rethrow;
        }
      });
    } catch (e) {
      print('Ошибка при создании демонстрационных данных: $e');
      
      // При сбое в основной транзакции пробуем создать хотя бы минимальные данные
      try {
        print('Попытка создания минимальных демо-данных после ошибки');
        
        // Создаем хотя бы одну папку и заметку
        final folderId = await _dbHelper.insertFolder({
          'name': 'Демо папка',
          'color': Colors.grey.value,
          'is_expanded': 1,
          'database_id': databaseId,
        });
        
        final now = DateTime.now();
        await _dbHelper.insertNote({
          'title': 'Демо заметка',
          'content': 'Это минимальная демонстрационная заметка.',
          'folder_id': folderId,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'database_id': databaseId,
        });
        
        print('Минимальные демо-данные созданы успешно');
      } catch (fallbackError) {
        print('Критическая ошибка при создании минимальных данных: $fallbackError');
      }
    }
  }

  // Вспомогательные методы для работы с текущей базой данных
  
  // Метод для проверки, находимся ли мы в указанной базе данных
  bool isInDatabase(String databaseId) {
    return _isUsingSharedDatabase && _currentDatabaseId == databaseId;
  }
  
  // Метод для проверки, находимся ли мы в локальной базе данных
  bool isInPersonalDatabase() {
    return !_isUsingSharedDatabase;
  }
  
  // Метод для преобразования объекта для текущей базы данных
  Map<String, dynamic> prepareForCurrentDatabase(Map<String, dynamic> data) {
    if (_isUsingSharedDatabase && _currentDatabaseId != null) {
      data['database_id'] = _currentDatabaseId;
    } else {
      data.remove('database_id');
    }
    return data;
  }
  
  // Метод для проверки и добавления database_id к запросам
  Future<List<dynamic>> queryWithCurrentDatabase(
    Future<List<dynamic>> Function(String? databaseId) queryFunction
  ) async {
    return await queryFunction(_isUsingSharedDatabase ? _currentDatabaseId : null);
  }

  // Инициализируем проверку состояния сервера
  void _initServerHealthCheck() {
    // Сначала выполним проверку немедленно
    _service.isServerAvailable().then((status) {
      _isServerAvailable = status;
      print('Начальный статус сервера: ${status ? "доступен" : "недоступен"}');
      notifyListeners();
    }).catchError((error) {
      print('Ошибка при начальной проверке сервера: $error');
      _isServerAvailable = false;
      notifyListeners();
    });
    
    // Затем настроим периодическую проверку с более надежным обработчиком ошибок
    _service.startServerHealthCheck(
      // Проверка каждую минуту
      interval: const Duration(minutes: 1),
      onStatusChanged: (status) {
        try {
          // Проверяем, изменился ли статус
          bool statusChanged = _isServerAvailable != status;
          _isServerAvailable = status;
          
          if (statusChanged) {
            print('Статус сервера изменен: ${status ? "доступен" : "недоступен"}');
            
            // ОТКЛЮЧАЕМ автоматическую синхронизацию при восстановлении соединения
            // Синхронизация будет запускаться только вручную пользователем
            // if (status && _isUsingSharedDatabase && _currentDatabaseId != null) {
            //   // Запускаем синхронизацию с небольшой задержкой и защитой от ошибок
            //   Future.delayed(Duration(seconds: 1), () {
            //     try {
            //       syncDatabase().timeout(Duration(seconds: 20), onTimeout: () {
            //         print('Таймаут при автоматической синхронизации');
            //         return;
            //       }).catchError((e) {
            //         print('Ошибка автоматической синхронизации: $e');
            //       });
            //     } catch (e) {
            //       print('Непредвиденная ошибка при автоматической синхронизации: $e');
            //     }
            //   });
            // }
            
            notifyListeners();
          }
        } catch (e) {
          print('Ошибка при обработке изменения статуса сервера: $e');
        }
      },
    );
  }
} 