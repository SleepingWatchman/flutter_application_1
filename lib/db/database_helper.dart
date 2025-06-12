import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/schedule_entry.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import '../models/note_image.dart';
import '../models/backup_data.dart';
import '../models/shared_database.dart';
import '../models/collaborative_database.dart';
import '../providers/database_provider.dart';

/*
 * ⚠️ КРИТИЧЕСКИ ВАЖНО: ЛОКАЛЬНЫЕ МОДЕЛИ ИЗМЕНЯТЬ ЗАПРЕЩЕНО! ⚠️
 * 
 * ❌ НЕ ИЗМЕНЯЙТЕ локальные модели данных (Note, Folder, ScheduleEntry, PinboardNote, Connection)
 * ❌ НЕ ДОБАВЛЯЙТЕ новые поля в локальные модели без явного требования пользователя
 * ❌ НЕ ИЗМЕНЯЙТЕ структуру таблиц базы данных для добавления полей, которых нет в моделях
 * 
 * ✅ ВСЕГДА приводите методы к существующим локальным моделям
 * ✅ ИЗМЕНЯЙТЕ только серверные модели и методы импорта/экспорта
 * ✅ ФИЛЬТРУЙТЕ лишние поля при импорте данных с сервера
 * 
 * Это правило действует ДО ОСОБОГО РАСПОРЯЖЕНИЯ ПОЛЬЗОВАТЕЛЯ!
 */

// Класс Lock для синхронизации операций
class Lock {
  Completer<void>? _completer;
  
  Future<T> synchronized<T>(Future<T> Function() action) async {
    if (_completer != null) {
      await _completer!.future;
    }
    
    final completer = Completer<void>();
    _completer = completer;
    
    try {
      final result = await action();
      completer.complete();
      _completer = null;
      return result;
    } catch (e) {
      completer.complete();
      _completer = null;
      rethrow;
    }
  }
}

/// Класс для работы с базой данных, реализующий CRUD-операции для всех сущностей.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _dbName = 'notes.db';
  static const int _dbVersion = 6;
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Флаг для отслеживания состояния переключения между базами
  bool _isChangingDatabase = false;
  
  // Флаг для отслеживания состояния базы данных
  bool _isClosed = false;
  
  // Семафор для блокировки конкурентного доступа
  final _lock = Lock();

  Future<Database> get database async {
    if (_database != null && !_isClosed) {
      return _database!;
    }
    
    // Если база данных закрыта или еще не инициализирована, инициализируем ее
    try {
      _database = await _initDatabase();
      _isClosed = false;
      return _database!;
    } catch (e) {
      // Если инициализация не удалась, возвращаем ошибку
      print('Ошибка инициализации базы данных: $e');
      rethrow;
    }
  }

  // Безопасный метод выполнения операций с базой данных
  Future<T> _safeDbOperation<T>(Future<T> Function() operation) async {
    return await _lock.synchronized(() async {
      // Если база данных в процессе переключения, ждем небольшое время и проверяем снова
      if (_isChangingDatabase) {
        print('База данных в процессе переключения, ожидание...');
        await Future.delayed(Duration(milliseconds: 500));
        
        // Если после ожидания база все еще в процессе переключения, выбрасываем исключение
        if (_isChangingDatabase) {
          throw Exception('База данных в процессе переключения. Попробуйте позже.');
        }
      }
      
      // Проверяем, открыта ли база данных
      if (_isClosed) {
        print('База данных закрыта, открываем заново');
        await _initDatabase();
        _isClosed = false;
      }
      
      // Выполняем операцию
      try {
        final result = await operation();
        // ИСПРАВЛЕНО: Не проверяем на null для void операций (T может быть void)
        // void операции корректно возвращают null, это нормально
        return result;
      } catch (e) {
        print('Ошибка при выполнении операции с базой данных: $e');
        
        // Проверяем, является ли ошибка связанной с закрытой базой данных
        if (e.toString().contains('closed') || e.toString().contains('закрыт')) {
          print('База данных была закрыта, пытаемся переинициализировать');
          _isClosed = true;
          _database = null;
          
          // Пробуем заново инициализировать базу данных
          await Future.delayed(Duration(milliseconds: 500));
          await _initDatabase();
          _isClosed = false;
          
          // Повторяем операцию только один раз
          try {
            final result = await operation();
            // ИСПРАВЛЕНО: Не проверяем на null для void операций при повторе
            return result;
          } catch (retryError) {
            print('Ошибка при повторной попытке операции: $retryError');
            rethrow;
          }
        }
        
        rethrow;
      }
    });
  }

  Future<Database> _initDatabase() async {
    try {
      // Получаем путь к исполняемому файлу приложения
      final exePath = Platform.resolvedExecutable;
      final appDir = Directory(p.dirname(exePath));
      final dbDir = Directory(p.join(appDir.path, 'database'));
      
      // Создаем директорию для базы данных, если она не существует
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      
      final path = p.join(dbDir.path, _dbName);
      
      // Открываем базу данных
      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      print('Критическая ошибка при создании базы данных: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Создаем таблицу папок
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        is_expanded INTEGER NOT NULL DEFAULT 1,
        database_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // Создаем таблицу заметок со всеми необходимыми колонками
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT,
        folder_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        images TEXT,
        metadata TEXT,
        content_json TEXT,
        database_id TEXT,
        FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
      )
    ''');

    // Таблица расписания с колонками created_at и updated_at и tags_json
    await db.execute('''
      CREATE TABLE schedule_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT,
        date TEXT,
        note TEXT,
        dynamic_fields_json TEXT,
        recurrence_json TEXT,
        database_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        tags_json TEXT
      )
    ''');

    // Таблица заметок на доске
    await db.execute('''
      CREATE TABLE pinboard_notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        position_x REAL,
        position_y REAL,
        width REAL,
        height REAL,
        background_color INTEGER,
        icon INTEGER,
        database_id TEXT
      )
    ''');

    // Таблица соединений заметок
    await db.execute('''
      CREATE TABLE connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_note_id INTEGER,
        to_note_id INTEGER,
        type TEXT,
        name TEXT,
        connection_color INTEGER,
        database_id TEXT,
        FOREIGN KEY (from_note_id) REFERENCES pinboard_notes (id),
        FOREIGN KEY (to_note_id) REFERENCES pinboard_notes (id)
      )
    ''');

    await _createImagesTable(db);

    // Создаем таблицу для совместных баз данных
    await db.execute('''
      CREATE TABLE shared_databases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        collaborators TEXT NOT NULL,
        database_path TEXT NOT NULL,
        is_owner INTEGER NOT NULL DEFAULT 0,
        last_sync TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Добавляем колонки для заметок
      await db.execute('ALTER TABLE notes ADD COLUMN images TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN metadata TEXT');
    }
    
    if (oldVersion < 3) {
      // Добавляем колонку content_json
      await db.execute('ALTER TABLE notes ADD COLUMN content_json TEXT');
    }
    
    if (oldVersion < 4) {
      // Добавляем колонку database_id для всех таблиц
      await db.execute('ALTER TABLE notes ADD COLUMN database_id TEXT');
      await db.execute('ALTER TABLE folders ADD COLUMN database_id TEXT');
      await db.execute('ALTER TABLE schedule_entries ADD COLUMN database_id TEXT');
      await db.execute('ALTER TABLE pinboard_notes ADD COLUMN database_id TEXT');
      await db.execute('ALTER TABLE connections ADD COLUMN database_id TEXT');
      
      // Добавляем временные колонки для расписания
      await db.execute('ALTER TABLE schedule_entries ADD COLUMN created_at TEXT');
      await db.execute('ALTER TABLE schedule_entries ADD COLUMN updated_at TEXT');
      
      // Добавляем колонки для папок
      await db.execute('ALTER TABLE folders ADD COLUMN created_at TEXT');
      await db.execute('ALTER TABLE folders ADD COLUMN updated_at TEXT');
      
      // Создаем таблицу изображений
      await _createImagesTable(db);
      
      // Создаем таблицу для совместных баз данных
      await db.execute('''
        CREATE TABLE shared_databases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          server_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          owner_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          collaborators TEXT NOT NULL,
          database_path TEXT NOT NULL,
          is_owner INTEGER NOT NULL DEFAULT 0,
          last_sync TEXT NOT NULL
        )
      ''');
    }
    
    if (oldVersion < 5) {
      // Добавляем поддержку тегов для расписания
      await db.execute('ALTER TABLE schedule_entries ADD COLUMN tags_json TEXT');
    }
    
    if (oldVersion < 6) {
      // Убеждаемся, что все нужные изменения применены для поддержки тегов
      try {
        await db.execute('ALTER TABLE schedule_entries ADD COLUMN tags_json TEXT');
      } catch (e) {
        // Колонка уже существует, это нормально
        print('Колонка tags_json уже существует: $e');
      }
    }
  }

  Future<void> _cleanupDuplicateImages(Database db) async {
    try {
      // Находим и удаляем дублирующиеся изображения, оставляя только самые новые
      final duplicates = await db.rawQuery('''
        SELECT note_id, file_name, COUNT(*) as count
        FROM note_images
        GROUP BY note_id, file_name
        HAVING COUNT(*) > 1
      ''');
      
      print('Найдено ${duplicates.length} групп дублирующихся изображений');
      
      for (final duplicate in duplicates) {
        final noteId = duplicate['note_id'];
        final fileName = duplicate['file_name'];
        final count = duplicate['count'];
        
        print('Очистка дубликатов для заметки $noteId, файл $fileName (найдено $count копий)');
        
        // Удаляем все дубликаты, кроме самого нового (с максимальным id)
        await db.rawDelete('''
          DELETE FROM note_images
          WHERE note_id = ? AND file_name = ? AND id NOT IN (
            SELECT MAX(id) FROM note_images
            WHERE note_id = ? AND file_name = ?
          )
        ''', [noteId, fileName, noteId, fileName]);
      }
      
      // Проверяем результат
      final totalImages = await db.rawQuery('SELECT COUNT(*) as count FROM note_images');
      print('После очистки осталось ${totalImages.first['count']} изображений');
      
    } catch (e) {
      print('Ошибка при очистке дублирующихся изображений: $e');
    }
  }

  Future<void> _createImagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        image_data BLOB NOT NULL,
        database_id TEXT,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE,
        UNIQUE(note_id, file_name)
      )
    ''');
  }

  // Методы для работы с папками
  Future<List<Folder>> getFolders([String? databaseId]) async {
    try {
      return await _safeDbOperation(() async {
        final db = await database;
        if (databaseId != null) {
          final List<Map<String, dynamic>> maps = await db.query(
            'folders',
            where: 'database_id = ?',
            whereArgs: [databaseId],
          );
          return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
        }
        final List<Map<String, dynamic>> maps = await db.query(
          'folders',
          where: 'database_id IS NULL',
        );
        return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
      });
    } catch (e) {
      print('Ошибка при получении папок: $e');
      return <Folder>[]; // Возвращаем пустой список в случае ошибки
    }
  }

  Future<int> insertFolder(Map<String, dynamic> folder, [Transaction? txn]) async {
    if (txn != null) {
      return await txn.insert('folders', folder);
    }
    final db = await database;
    return await db.insert('folders', folder);
  }

  Future<void> updateFolder(Map<String, dynamic> folder) async {
    final db = await database;
    await db.update(
      'folders',
      folder,
      where: 'id = ?',
      whereArgs: [folder['id']],
    );
  }

  // Методы для работы с заметками
  Future<List<Note>> getAllNotes([String? databaseId]) async {
    try {
      return await _safeDbOperation(() async {
        final db = await database;
        if (databaseId != null) {
          final List<Map<String, dynamic>> maps = await db.query(
            'notes',
            where: 'database_id = ?',
            whereArgs: [databaseId],
          );
          return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
        }
        final List<Map<String, dynamic>> maps = await db.query(
          'notes',
          where: 'database_id IS NULL',
        );
        return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
      });
    } catch (e) {
      print('Ошибка при получении заметок: $e');
      return <Note>[]; // Возвращаем пустой список в случае ошибки
    }
  }

  Future<List<Note>> getNotesByFolder(int folderId, [String? databaseId]) async {
    final db = await database;
    
    // Получаем информацию о папке
    final folder = await db.query(
      'folders',
      where: 'id = ?',
      whereArgs: [folderId],
      limit: 1,
    );
    
    if (folder.isNotEmpty) {
      String? folderDatabaseId = folder.first['database_id'] as String?;
      
      // Проверяем, соответствует ли database_id папки текущему database_id
      if (databaseId != null && folderDatabaseId != databaseId) {
        print('Предупреждение: Запрос заметок для папки из другой базы данных');
        return [];
      }
      
      // Запрос заметок с учетом database_id
      List<Map<String, dynamic>> maps;
      if (databaseId != null) {
        maps = await db.query(
          'notes',
          where: 'folder_id = ? AND database_id = ?',
          whereArgs: [folderId, databaseId],
        );
      } else {
        maps = await db.query(
          'notes',
          where: 'folder_id = ? AND database_id IS NULL',
          whereArgs: [folderId],
        );
      }
      
      return List.generate(maps.length, (i) {
        final noteJson = maps[i]['content_json'];
        if (noteJson != null) {
          try {
            final note = Note.fromJson(noteJson);
            return note.copyWith(id: maps[i]['id']);
          } catch (e) {
            print('Ошибка десериализации заметки: $e');
            return Note.fromMap(maps[i]);
          }
        } else {
          return Note.fromMap(maps[i]);
        }
      });
    }
    
    return [];
  }

  Future<int> insertNote(Map<String, dynamic> note) async {
    final db = await database;
    // ИСПРАВЛЕНИЕ: НЕ удаляем database_id для совместных баз
    // Удаляем database_id только если он явно null (для личных данных)
    if (note['database_id'] == null) {
      note.remove('database_id');
    }
    final id = await db.insert('notes', note);
    _notifyDatabaseChanged();
    return id;
  }

  // Методы для работы с расписанием
  Future<List<ScheduleEntry>> getScheduleEntries([String? databaseId]) async {
    try {
      return await _safeDbOperation(() async {
        final db = await database;
        if (databaseId != null) {
          final List<Map<String, dynamic>> maps = await db.query(
            'schedule_entries',
            where: 'database_id = ?',
            whereArgs: [databaseId],
          );
          return List.generate(maps.length, (i) => ScheduleEntry.fromMap(maps[i]));
        }
        final List<Map<String, dynamic>> maps = await db.query(
          'schedule_entries',
          where: 'database_id IS NULL',
        );
        return List.generate(maps.length, (i) => ScheduleEntry.fromMap(maps[i]));
      });
    } catch (e) {
      print('Ошибка при получении записей расписания: $e');
      return <ScheduleEntry>[]; // Возвращаем пустой список в случае ошибки
    }
  }

  Future<int> insertScheduleEntry(Map<String, dynamic> entry, [Transaction? txn]) async {
    // ИСПРАВЛЕНИЕ: НЕ удаляем database_id для совместных баз
    // Удаляем database_id только если он явно null (для личных данных)
    if (entry['database_id'] == null) {
      entry.remove('database_id');
    }
    
    if (txn != null) {
      return await txn.insert('schedule_entries', entry);
    }
    final db = await database;
    final id = await db.insert('schedule_entries', entry);
    _notifyDatabaseChanged();
    return id;
  }
  
  Future<void> updateScheduleEntry(dynamic entry, [Transaction? txn]) async {
    // Проверяем тип параметра
    if (entry is ScheduleEntry) {
      if (entry.id == null) return;
      // Конвертируем ScheduleEntry в Map и вызываем основной метод
      return updateScheduleEntry(entry.toMap(), txn);
    } else if (entry is Map<String, dynamic>) {
      // ИСПРАВЛЕНИЕ: НЕ удаляем database_id для совместных баз
      // Удаляем database_id только если он явно null (для личных данных)
      if (entry['database_id'] == null) {
        entry.remove('database_id');
      }
      
      if (txn != null) {
        await txn.update(
          'schedule_entries',
          entry,
          where: 'id = ?',
          whereArgs: [entry['id']],
        );
        return;
      }
      final db = await database;
      await db.update(
        'schedule_entries',
        entry,
        where: 'id = ?',
        whereArgs: [entry['id']],
      );
      _notifyDatabaseChanged();
    } else {
      throw ArgumentError('Неверный тип параметра: ожидался ScheduleEntry или Map<String, dynamic>');
    }
  }
  
  Future<void> deleteScheduleEntry(int id, [Transaction? txn]) async {
    if (txn != null) {
      await txn.delete(
        'schedule_entries',
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    final db = await database;
    await db.delete(
      'schedule_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyDatabaseChanged();
  }

  // Методы для работы с заметками на доске
  Future<List<PinboardNoteDB>> getPinboardNotes([String? databaseId]) async {
    try {
      return await _safeDbOperation(() async {
        final db = await database;
        if (databaseId != null) {
          final List<Map<String, dynamic>> maps = await db.query(
            'pinboard_notes',
            where: 'database_id = ?',
            whereArgs: [databaseId],
          );
          return List.generate(maps.length, (i) => PinboardNoteDB.fromMap(maps[i]));
        }
        final List<Map<String, dynamic>> maps = await db.query(
          'pinboard_notes',
          where: 'database_id IS NULL',
        );
        return List.generate(maps.length, (i) => PinboardNoteDB.fromMap(maps[i]));
      });
    } catch (e) {
      print('Ошибка при получении заметок доски: $e');
      return <PinboardNoteDB>[]; // Возвращаем пустой список в случае ошибки
    }
  }

  Future<int> insertPinboardNote(Map<String, dynamic> note, [Transaction? txn]) async {
    // ИСПРАВЛЕНИЕ: НЕ удаляем database_id для совместных баз
    // Удаляем database_id только если он явно null (для личных данных)
    if (note['database_id'] == null) {
      note.remove('database_id');
    }
    
    if (txn != null) {
      return await txn.insert('pinboard_notes', note);
    }
    final db = await database;
    final id = await db.insert('pinboard_notes', note);
    _notifyDatabaseChanged();
    return id;
  }
  
  Future<void> updatePinboardNote(dynamic note, [Transaction? txn]) async {
    // Преобразуем в Map<String, dynamic>
    Map<String, dynamic> noteMap;
    
    if (note is PinboardNoteDB) {
      if (note.id == null) return;
      noteMap = note.toMap();
    } else if (note is Map<String, dynamic>) {
      noteMap = note;
      if (noteMap['id'] == null) return;
    } else {
      throw ArgumentError('Неверный тип параметра: ожидался PinboardNoteDB или Map<String, dynamic>');
    }
    
    // Удаляем database_id из карты, если это локальная заметка
    if (noteMap['database_id'] == null) {
      noteMap.remove('database_id');
    }
    
    if (txn != null) {
      await txn.update(
        'pinboard_notes',
        noteMap,
        where: 'id = ?',
        whereArgs: [noteMap['id']],
      );
      return;
    }
    final db = await database;
    await db.update(
      'pinboard_notes',
      noteMap,
      where: 'id = ?',
      whereArgs: [noteMap['id']],
    );
    _notifyDatabaseChanged();
  }
  
  Future<void> deletePinboardNote(int id, [Transaction? txn]) async {
    if (txn != null) {
      // Удаляем связи
      await txn.delete(
        'connections',
        where: 'from_note_id = ? OR to_note_id = ?',
        whereArgs: [id, id],
      );
      // Удаляем саму заметку
      await txn.delete(
        'pinboard_notes',
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    final db = await database;
    await db.transaction((txn) async {
      // Удаляем связи
      await txn.delete(
        'connections',
        where: 'from_note_id = ? OR to_note_id = ?',
        whereArgs: [id, id],
      );
      // Удаляем саму заметку
      await txn.delete(
        'pinboard_notes',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _notifyDatabaseChanged();
  }

  // Методы для работы с соединениями
  Future<List<ConnectionDB>> getConnectionsDB([String? databaseId]) async {
    try {
      return await _safeDbOperation(() async {
        final db = await database;
        if (databaseId != null) {
          final List<Map<String, dynamic>> maps = await db.query(
            'connections',
            where: 'database_id = ?',
            whereArgs: [databaseId],
          );
          return List.generate(maps.length, (i) => ConnectionDB.fromMap(maps[i]));
        }
        final List<Map<String, dynamic>> maps = await db.query(
          'connections',
          where: 'database_id IS NULL',
        );
        return List.generate(maps.length, (i) => ConnectionDB.fromMap(maps[i]));
      });
    } catch (e) {
      print('Ошибка при получении соединений: $e');
      return <ConnectionDB>[]; // Возвращаем пустой список в случае ошибки
    }
  }

  Future<int> insertConnection(Map<String, dynamic> connection, [Transaction? txn]) async {
    // Удаляем database_id из карты, если это локальное соединение
    if (connection['database_id'] == null) {
      connection.remove('database_id');
    }
    
    if (txn != null) {
      return await txn.insert('connections', connection);
    }
    final db = await database;
    final id = await db.insert('connections', connection);
    _notifyDatabaseChanged();
    return id;
  }
  
  Future<void> updateConnection(Map<String, dynamic> connection, [Transaction? txn]) async {
    // Удаляем database_id из карты, если это локальное соединение
    if (connection['database_id'] == null) {
      connection.remove('database_id');
    }
    
    if (txn != null) {
      await txn.update(
        'connections',
        connection,
        where: 'id = ?',
        whereArgs: [connection['id']],
      );
      return;
    }
    final db = await database;
    await db.update(
      'connections',
      connection,
      where: 'id = ?',
      whereArgs: [connection['id']],
    );
    _notifyDatabaseChanged();
  }
  
  Future<void> deleteConnection(int id, [Transaction? txn]) async {
    if (txn != null) {
      await txn.delete(
        'connections',
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    final db = await database;
    await db.delete(
      'connections',
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyDatabaseChanged();
  }

  // Методы для работы с изображениями
  Future<List<NoteImage>> getAllImages([String? databaseId]) async {
    final db = await database;
    
    if (databaseId != null) {
      // Сначала получаем ID заметок из текущей базы
      final notesFromCurrentDb = await db.query(
        'notes',
        columns: ['id'],
        where: 'database_id = ?',
        whereArgs: [databaseId],
      );
      
      if (notesFromCurrentDb.isEmpty) {
        return [];
      }
      
      // Собираем ID заметок
      final noteIds = notesFromCurrentDb
          .map((note) => note['id'].toString())
          .toList();
      
      // Создаем строку с плейсхолдерами для запроса
      final placeholders = List.filled(noteIds.length, '?').join(',');
      
      // Получаем изображения, связанные с заметками из текущей базы
      final List<Map<String, dynamic>> maps = await db.query(
        'note_images',
        where: 'note_id IN ($placeholders)',
        whereArgs: noteIds,
      );
      
      return List.generate(maps.length, (i) => NoteImage.fromMap(maps[i]));
    } else {
      // Для локальной базы данных
      final notesFromCurrentDb = await db.query(
        'notes',
        columns: ['id'],
        where: 'database_id IS NULL',
      );
      
      if (notesFromCurrentDb.isEmpty) {
        return [];
      }
      
      // Собираем ID заметок
      final noteIds = notesFromCurrentDb
          .map((note) => note['id'].toString())
          .toList();
      
      // Создаем строку с плейсхолдерами для запроса
      final placeholders = List.filled(noteIds.length, '?').join(',');
      
      // Получаем изображения, связанные с заметками из локальной базы
      final List<Map<String, dynamic>> maps = await db.query(
        'note_images',
        where: 'note_id IN ($placeholders)',
        whereArgs: noteIds,
      );
      
      return List.generate(maps.length, (i) => NoteImage.fromMap(maps[i]));
    }
  }

  Future<void> insertImage(int noteId, String fileName, Uint8List imageData, [Transaction? txn]) async {
    final data = {
      'note_id': noteId,
      'file_name': fileName,
      'image_data': imageData,
    };
    
    try {
      if (txn != null) {
        // Используем INSERT OR REPLACE для автоматической замены дубликатов
        await txn.rawInsert('''
          INSERT OR REPLACE INTO note_images (note_id, file_name, image_data)
          VALUES (?, ?, ?)
        ''', [noteId, fileName, imageData]);
      } else {
        final db = await database;
        await db.rawInsert('''
          INSERT OR REPLACE INTO note_images (note_id, file_name, image_data)
          VALUES (?, ?, ?)
        ''', [noteId, fileName, imageData]);
      }
    } catch (e) {
      print('Ошибка при вставке изображения $fileName для заметки $noteId: $e');
      rethrow;
    }
  }

  // Методы для транзакций
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  Future<void> clearAllTables(Transaction txn) async {
    await txn.delete('folders');
    await txn.delete('notes');
    await txn.delete('schedule_entries');
    await txn.delete('pinboard_notes');
    await txn.delete('connections');
    await txn.delete('note_images');
  }

  Future<void> clearDatabaseTables(String databaseId, [Transaction? transaction]) async {
    return await _safeDbOperation(() async {
      print('Начало очистки таблиц для базы данных: $databaseId');
      
      try {
        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: НЕ закрываем базу данных, просто очищаем таблицы
        // Закрытие базы приводит к блокировкам и конфликтам при параллельных запросах
        
        final db = await database;
        print('✅ База данных доступна для очистки');
        
        // ИСПРАВЛЕНИЕ: Добавляем таймаут для операций очистки
        await Future.any([
          _performClearOperation(db, databaseId, transaction),
          Future.delayed(Duration(seconds: 15), () => throw TimeoutException('Таймаут операции очистки базы данных'))
        ]);
        
        print('Очищены таблицы для базы $databaseId');
      } catch (e) {
        if (e is TimeoutException) {
          print('❌ ТАЙМАУТ: Операция очистки базы $databaseId превысила лимит времени');
          // Попробуем экстренную очистку без транзакций
          try {
            await _emergencyClearDatabase(databaseId);
          } catch (forceError) {
            print('❌ Ошибка экстренной очистки: $forceError');
          }
        } else {
          print('Ошибка при очистке таблиц для базы $databaseId: $e');
        }
        // Не выбрасываем исключение, чтобы не прерывать работу приложения
      }
    });
  }
  
  /// Выполнение операции очистки с проверками
  Future<void> _performClearOperation(Database db, String databaseId, Transaction? transaction) async {
    // Быстрая проверка наличия данных
    final hasDataCheck = await db.query(
      'notes',
      where: 'database_id = ?',
      whereArgs: [databaseId],
      limit: 1,
    );
    
    if (hasDataCheck.isEmpty) {
      // Проверяем другие таблицы
      final folderCheck = await db.query(
        'folders',
        where: 'database_id = ?',
        whereArgs: [databaseId],
        limit: 1,
      );
      
      if (folderCheck.isEmpty) {
        print('Таблицы для базы $databaseId уже пусты, пропускаем очистку');
        return;
      }
    }
    
    // ИСПРАВЛЕНИЕ: Используем только простые DELETE без вложенных транзакций
    if (transaction != null) {
      await _performTableClear(transaction, databaseId);
    } else {
      // Выполняем простые DELETE без транзакций для ускорения
      await _performSimpleClear(db, databaseId);
    }
  }
  
  /// Простая очистка без транзакций
  Future<void> _performSimpleClear(Database db, String databaseId) async {
    print('🗑️ ПРОСТАЯ ОЧИСТКА: Удаление без транзакций для базы $databaseId');
    
    // Удаляем в правильном порядке без транзакций
    await db.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
    print('🗑️ Удалены соединения');
    
    await db.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
    print('🗑️ Удалены заметки на доске');
    
    await db.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
    print('🗑️ Удалены записи расписания');
    
    await db.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
    print('🗑️ Удалены заметки');
    
    await db.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
    print('🗑️ Удалены папки');
    
    print('✅ ПРОСТАЯ ОЧИСТКА завершена для базы $databaseId');
  }
  
  /// Экстренная очистка базы данных при критических проблемах
  Future<void> _emergencyClearDatabase(String databaseId) async {
    print('🚨 ЭКСТРЕННАЯ ОЧИСТКА базы $databaseId');
    try {
      // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: НЕ закрываем базу данных для экстренной очистки
      // Просто выполняем простые DELETE запросы
      
      final db = await database; // Используем существующее соединение
      
      // Простые DELETE запросы без всех проверок
      try {
        await db.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
        await db.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
        await db.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
        await db.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
        await db.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
        print('✅ Экстренная очистка базы $databaseId завершена успешно');
      } catch (e) {
        print('❌ Ошибка экстренной очистки: $e');
        // В крайнем случае просто пропускаем очистку
        print('⚠️ Пропускаем очистку базы $databaseId из-за критических ошибок');
      }
    } catch (e) {
      print('❌ Критическая ошибка экстренной очистки: $e');
    }
  }
  
  /// Вспомогательный метод для выполнения очистки таблиц в транзакции (для обратной совместимости)
  Future<void> _performTableClear(Transaction txn, String databaseId) async {
    print('🗑️ ТРАНЗАКЦИЯ: Очистка в транзакции для базы $databaseId');
    
    try {
      // Простая очистка в рамках транзакции
      await txn.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
      await txn.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
      await txn.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
      await txn.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
      await txn.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
      
      print('✅ ТРАНЗАКЦИЯ: Очистка в транзакции завершена для базы $databaseId');
    } catch (e) {
      print('❌ ТРАНЗАКЦИЯ: Ошибка при очистке в транзакции: $e');
      throw e;
    }
  }

  Future<List<Map<String, dynamic>>> getNotesForDatabase([String? databaseId]) async {
    final db = await database;
    if (databaseId != null) {
      return await db.query('notes', where: 'database_id = ?', whereArgs: [databaseId]);
    }
    return await db.query('notes', where: 'database_id IS NULL');
  }

  Future<List<Map<String, dynamic>>> getFoldersForDatabase([String? databaseId]) async {
    final db = await database;
    if (databaseId != null) {
      return await db.query('folders', where: 'database_id = ?', whereArgs: [databaseId]);
    }
    return await db.query('folders', where: 'database_id IS NULL');
  }

  Future<List<Map<String, dynamic>>> getScheduleEntriesForDatabase([String? databaseId]) async {
    final db = await database;
    if (databaseId != null) {
      return await db.query('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
    }
    return await db.query('schedule_entries', where: 'database_id IS NULL');
  }

  Future<List<Map<String, dynamic>>> getPinboardNotesForDatabase([String? databaseId]) async {
    final db = await database;
    if (databaseId != null) {
      return await db.query('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
    }
    return await db.query('pinboard_notes', where: 'database_id IS NULL');
  }

  Future<List<Map<String, dynamic>>> getConnectionsForDatabase([String? databaseId]) async {
    final db = await database;
    if (databaseId != null) {
      return await db.query('connections', where: 'database_id = ?', whereArgs: [databaseId]);
    }
    return await db.query('connections', where: 'database_id IS NULL');
  }

  Future<void> updateNote(Note note) async {
    if (note.id == null) return;
    
    final db = await database;
    final Map<String, dynamic> noteMap = note.toMap();
    // ИСПРАВЛЕНИЕ: НЕ удаляем database_id для совместных баз
    // Удаляем database_id только если он явно null (для личных данных)
    if (noteMap['database_id'] == null) {
      noteMap.remove('database_id');
    }
    
    await db.update(
      'notes',
      noteMap,
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Folder>> getAllFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('folders');
    return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
  }

  // Методы для работы с изображениями
  Future<List<Map<String, dynamic>>> getImagesForNote(int id, [String? databaseId]) async {
    final db = await database;
    
    // ✅ ИСПРАВЛЕНИЕ: Правильный поиск изображений с учетом текущей базы данных
    try {
      // Для совместных баз данных используем правильную таблицу
      if (databaseId != null) {
        // Проверяем, есть ли заметка в указанной базе данных
        final noteCheck = await db.query(
          'notes',
          where: 'id = ? AND database_id = ?',
          whereArgs: [id, databaseId],
          limit: 1,
        );
        
        if (noteCheck.isEmpty) {
          print('Заметка $id не найдена в базе данных $databaseId');
          return [];
        }
        
        print('Поиск изображений для заметки $id в совместной базе $databaseId');
        
        // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Ищем изображения по note_id И database_id
        final images = await db.query(
          'note_images',
          where: 'note_id = ? AND (database_id = ? OR database_id IS NULL)',
          whereArgs: [id, databaseId],
        );
        
        print('Загружено изображений для заметки $id: ${images.length}');
        return images;
      } else {
        // Для личной базы данных (databaseId == null)
        // Проверяем, что заметка принадлежит личной базе
        final noteCheck = await db.query(
          'notes',
          where: 'id = ? AND database_id IS NULL',
          whereArgs: [id],
          limit: 1,
        );
        
        if (noteCheck.isEmpty) {
          print('Заметка $id не найдена в личной базе данных');
          return [];
        }
        
        print('Поиск изображений для заметки $id в личной базе данных');
        
        final images = await db.query(
          'note_images',
          where: 'note_id = ? AND database_id IS NULL',
          whereArgs: [id],
        );
        
        print('Загружено изображений для заметки $id: ${images.length}');
        return images;
      }
    } catch (e) {
      print('Ошибка при поиске изображений для заметки $id в базе $databaseId: $e');
      return [];
    }
  }

  Future<void> deleteImage(int id) async {
    final db = await database;
    await db.delete(
      'note_images',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteImagesForNote(int id) async {
    final db = await database;
    await db.delete(
      'note_images',
      where: 'note_id = ?',
      whereArgs: [id],
    );
  }

  Future<Uint8List?> getImageData(int imageId) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'note_images',
      columns: ['image_data'],
      where: 'id = ?',
      whereArgs: [imageId],
    );
    
    if (result.isEmpty) return null;
    return result.first['image_data'] as Uint8List;
  }

  Future<Uint8List?> getImageDataByPath(String imagePath) async {
    final db = await database;
    try {
      // Извлекаем имя файла из пути
      final fileName = imagePath.split('/').last;
      
      // Сначала ищем в текущей базе
      final List<Map<String, dynamic>> result = await db.query(
        'note_images',
        where: 'file_name = ?',
        whereArgs: [fileName],
      );
      
      if (result.isNotEmpty) {
        return result.first['image_data'] as Uint8List?;
      }
      
      // Если изображение не найдено, попробуем найти его во всех базах
      print('Изображение $fileName не найдено в основной таблице, ищем в других базах...');
      return await findImageInAllDatabases(fileName);
    } catch (e) {
      print('Ошибка при получении данных изображения: $e');
      return null;
    }
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.delete('notes');
    await db.delete('folders');
    await db.delete('note_images');
    await db.delete('pinboard_notes');
    await db.delete('connections');
    await db.delete('schedule_entries');
  }

  // Методы для резервного копирования
  Future<List<Map<String, dynamic>>> getFoldersForBackup() async {
    final db = await database;
    return await db.query('folders');
  }

  Future<List<Map<String, dynamic>>> getScheduleEntriesForBackup() async {
    final db = await database;
    return await db.query('schedule_entries');
  }

  Future<List<Map<String, dynamic>>> getPinboardNotesForBackup() async {
    final db = await database;
    return await db.query('pinboard_notes');
  }

  Future<List<Map<String, dynamic>>> getConnectionsForBackup() async {
    final db = await database;
    return await db.query('connections');
  }

  Future<List<Map<String, dynamic>>> getAllImagesForBackup() async {
    final db = await database;
    return await db.query('note_images');
  }

  Future<void> clearAllTablesForBackup(Transaction txn) async {
    await txn.delete('folders');
    await txn.delete('notes');
    await txn.delete('schedule_entries');
    await txn.delete('pinboard_notes');
    await txn.delete('connections');
    await txn.delete('note_images');
  }

  Future<void> clearDatabaseTablesForBackup(String databaseId, Transaction txn) async {
    await txn.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
    print('Таблицы для базы $databaseId успешно очищены');
  }

  Future<List<Map<String, dynamic>>> getNotesForBackup() async {
    final db = await database;
    return await db.query('notes');
  }

  Future<T> executeTransaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  Future<void> insertFolderForBackup(Map<String, dynamic> folder, [Transaction? txn]) async {
    // ⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Фильтруем поля согласно локальной модели Folder 
    // (БЕЗ created_at и updated_at которые отсутствуют в клиентской схеме)
    final filteredFolder = <String, dynamic>{
      'id': folder['id'],
      'name': folder['name'],
      'color': folder['color'],
      'is_expanded': folder['is_expanded'],
      'database_id': folder['database_id'],
    };
    
    final preparedFolder = BackupData.prepareForSqlite(filteredFolder);
    
    try {
      if (txn != null) {
        await txn.insert('folders', preparedFolder);
      } else {
        final db = await database;
        await db.insert('folders', preparedFolder);
      }
    } catch (e) {
      // Обрабатываем ошибки уникальных ограничений
      if (e.toString().contains('UNIQUE constraint failed') || 
          e.toString().contains('UNIQUE') ||
          e.toString().contains('PRIMARY KEY')) {
        print('Конфликт уникальности при вставке папки: ${preparedFolder['name']}, пытаемся обновить');
        
        try {
          // Пытаемся обновить существующую запись
          if (preparedFolder['id'] != null) {
            if (txn != null) {
              await txn.update(
                'folders',
                preparedFolder,
                where: 'id = ?',
                whereArgs: [preparedFolder['id']],
              );
            } else {
              final db = await database;
              await db.update(
                'folders',
                preparedFolder,
                where: 'id = ?',
                whereArgs: [preparedFolder['id']],
              );
            }
            print('Папка успешно обновлена: ${preparedFolder['name']}');
          } else {
            print('Пропускаем папку без ID: ${preparedFolder['name']}');
          }
        } catch (updateError) {
          print('Ошибка при обновлении папки: $updateError');
        }
      } else {
        print('Ошибка при вставке папки: $e');
        rethrow;
      }
    }
  }

  Future<void> insertNoteForBackup(Map<String, dynamic> note, [Transaction? txn]) async {
    // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавляем обязательные поля created_at и updated_at если их нет
    final noteWithDefaults = Map<String, dynamic>.from(note);
    
    // Проверяем и добавляем created_at если отсутствует
    if (!noteWithDefaults.containsKey('created_at') || noteWithDefaults['created_at'] == null) {
      noteWithDefaults['created_at'] = DateTime.now().toIso8601String();
      print('✅ ИСПРАВЛЕНИЕ: Добавлен created_at для заметки ${noteWithDefaults['title']}');
    }
    
    // Проверяем и добавляем updated_at если отсутствует
    if (!noteWithDefaults.containsKey('updated_at') || noteWithDefaults['updated_at'] == null) {
      noteWithDefaults['updated_at'] = DateTime.now().toIso8601String();
      print('✅ ИСПРАВЛЕНИЕ: Добавлен updated_at для заметки ${noteWithDefaults['title']}');
    }
    
    final preparedNote = BackupData.prepareForSqlite(noteWithDefaults);
    
    try {
      if (txn != null) {
        await txn.insert('notes', preparedNote);
      } else {
        final db = await database;
        await db.insert('notes', preparedNote);
      }
    } catch (e) {
      // Обрабатываем ошибки уникальных ограничений
      if (e.toString().contains('UNIQUE constraint failed') || 
          e.toString().contains('UNIQUE') ||
          e.toString().contains('PRIMARY KEY')) {
        print('Конфликт уникальности при вставке заметки: ${preparedNote['title']}, пытаемся обновить');
        
        try {
          // Пытаемся обновить существующую запись
          if (preparedNote['id'] != null) {
            if (txn != null) {
              await txn.update(
                'notes',
                preparedNote,
                where: 'id = ?',
                whereArgs: [preparedNote['id']],
              );
            } else {
              final db = await database;
              await db.update(
                'notes',
                preparedNote,
                where: 'id = ?',
                whereArgs: [preparedNote['id']],
              );
            }
            print('Заметка успешно обновлена: ${preparedNote['title']}');
          } else {
            print('Пропускаем заметку без ID: ${preparedNote['title']}');
          }
        } catch (updateError) {
          print('Ошибка при обновлении заметки: $updateError');
        }
      } else if (e.toString().contains('FOREIGN KEY constraint failed')) {
        // Специальная обработка ошибок внешнего ключа только для критических случаев
        print('⚠️ FOREIGN KEY: Ошибка связи для заметки ${preparedNote['title']}, folder_id: ${preparedNote['folder_id']}');
        
        // Проверяем существование папки и создаем ее если нужно
        if (preparedNote['folder_id'] != null) {
          try {
            final db = txn != null ? txn : await database;
            final folderExists = await (db as dynamic).query(
              'folders',
              where: 'id = ? AND database_id = ?',
              whereArgs: [preparedNote['folder_id'], preparedNote['database_id']],
            );
            
            if (folderExists.isEmpty) {
              print('⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Создаем недостающую папку ${preparedNote['folder_id']}');
              await (db as dynamic).insert('folders', {
                'id': preparedNote['folder_id'],
                'name': 'Восстановленная папка ${preparedNote['folder_id']}',
                'color': 0xFF2196F3,
                'is_expanded': 1,
                'database_id': preparedNote['database_id'],
              });
              
              // Повторяем вставку заметки
              await (db as dynamic).insert('notes', preparedNote);
              print('✅ Заметка успешно вставлена после создания папки');
              return;
            }
          } catch (folderError) {
            print('❌ Ошибка создания папки: $folderError');
          }
        }
        
        // В крайнем случае обнуляем folder_id
        print('⚠️ ИСПРАВЛЕНИЕ: Обнуляем folder_id для заметки ${preparedNote['title']}');
        preparedNote['folder_id'] = null;
        
        try {
          if (txn != null) {
            await txn.insert('notes', preparedNote);
          } else {
            final db = await database;
            await db.insert('notes', preparedNote);
          }
          print('✅ Заметка вставлена без привязки к папке');
        } catch (retryError) {
          print('❌ Повторная ошибка при вставке заметки: $retryError');
          rethrow;
        }
      } else {
        print('Ошибка при вставке заметки: $e');
        rethrow;
      }
    }
  }

  Future<void> insertScheduleEntryForBackup(Map<String, dynamic> entry, [Transaction? txn]) async {
    // ⚠️ ВАЖНО: Фильтруем поля согласно локальной модели ScheduleEntry (БЕЗ created_at и updated_at)
    final filteredEntry = <String, dynamic>{
      'id': entry['id'],
      'time': entry['time'],
      'date': entry['date'],
      'note': entry['note'],
      'dynamic_fields_json': entry['dynamic_fields_json'],
      'recurrence_json': entry['recurrence_json'],
      'database_id': entry['database_id'],
      'tags_json': entry['tags_json'], // ИСПРАВЛЕНИЕ: Добавляем поле tags_json
    };
    
    final preparedEntry = BackupData.prepareForSqlite(filteredEntry);
    
    // Для персональных резервных копий database_id может быть null - это нормально
    // Пропускаем только если это явно пустая строка (что указывает на ошибку)
    if (preparedEntry['database_id'] == '') {
      print('Предупреждение: database_id установлен как пустая строка для записи расписания при восстановлении');
      return; // Пропускаем запись с пустым database_id
    }
    
    try {
      if (txn != null) {
        // Используем INSERT OR REPLACE для автоматической замены дубликатов
        await txn.rawInsert('''
          INSERT OR REPLACE INTO schedule_entries 
          (id, time, date, note, dynamic_fields_json, recurrence_json, database_id, tags_json)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          preparedEntry['id'],
          preparedEntry['time'],
          preparedEntry['date'],
          preparedEntry['note'],
          preparedEntry['dynamic_fields_json'],
          preparedEntry['recurrence_json'],
          preparedEntry['database_id'],
          preparedEntry['tags_json'],
        ]);
      } else {
        final db = await database;
        await db.rawInsert('''
          INSERT OR REPLACE INTO schedule_entries 
          (id, time, date, note, dynamic_fields_json, recurrence_json, database_id, tags_json)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          preparedEntry['id'],
          preparedEntry['time'],
          preparedEntry['date'],
          preparedEntry['note'],
          preparedEntry['dynamic_fields_json'],
          preparedEntry['recurrence_json'],
          preparedEntry['database_id'],
          preparedEntry['tags_json'],
        ]);
      }
    } catch (e) {
      print('Ошибка при вставке записи расписания: $e');
      print('Данные записи: ${preparedEntry.toString()}');
      
      // Пробуем более безопасный способ вставки без ID (автоинкремент)
      try {
        final safeEntry = Map<String, dynamic>.from(preparedEntry);
        safeEntry.remove('id'); // Убираем ID для автоинкремента
        
        if (txn != null) {
          await txn.insert('schedule_entries', safeEntry);
        } else {
          final db = await database;
          await db.insert('schedule_entries', safeEntry);
        }
        print('Запись расписания успешно вставлена без конкретного ID');
      } catch (fallbackError) {
        print('Не удалось вставить запись расписания даже без ID: $fallbackError');
      }
    }
  }

  Future<void> insertPinboardNoteForBackup(Map<String, dynamic> note, [Transaction? txn]) async {
    // ⚠️ ВАЖНО: Фильтруем поля согласно локальной модели PinboardNote (БЕЗ created_at и updated_at)
    final filteredNote = <String, dynamic>{
      'id': note['id'],
      'title': note['title'],
      'content': note['content'],
      'position_x': note['position_x'],
      'position_y': note['position_y'],
      'width': note['width'],
      'height': note['height'],
      'background_color': note['background_color'],
      'icon': note['icon'],
      'database_id': note['database_id'],
    };
    
    final preparedNote = BackupData.prepareForSqlite(filteredNote);
    
    try {
      if (txn != null) {
        await txn.insert('pinboard_notes', preparedNote);
      } else {
        final db = await database;
        await db.insert('pinboard_notes', preparedNote);
      }
    } catch (e) {
      // Обрабатываем ошибки уникальных ограничений
      if (e.toString().contains('UNIQUE constraint failed') || 
          e.toString().contains('UNIQUE') ||
          e.toString().contains('PRIMARY KEY')) {
        print('Конфликт уникальности при вставке заметки на доске: ${preparedNote['title']}, пытаемся обновить');
        
        try {
          // Пытаемся обновить существующую запись
          if (preparedNote['id'] != null) {
            if (txn != null) {
              await txn.update(
                'pinboard_notes',
                preparedNote,
                where: 'id = ?',
                whereArgs: [preparedNote['id']],
              );
            } else {
              final db = await database;
              await db.update(
                'pinboard_notes',
                preparedNote,
                where: 'id = ?',
                whereArgs: [preparedNote['id']],
              );
            }
            print('Заметка на доске успешно обновлена: ${preparedNote['title']}');
          } else {
            print('Пропускаем заметку на доске без ID: ${preparedNote['title']}');
          }
        } catch (updateError) {
          print('Ошибка при обновлении заметки на доске: $updateError');
        }
      } else {
        print('Ошибка при вставке заметки на доске: $e');
        rethrow;
      }
    }
  }

  Future<void> insertConnectionForBackup(Map<String, dynamic> connection, [Transaction? txn]) async {
    // ⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Фильтруем поля согласно локальной модели Connection 
    // (БЕЗ created_at и updated_at которые отсутствуют в клиентской схеме)
    final filteredConnection = <String, dynamic>{
      'id': connection['id'],
      'from_note_id': connection['from_note_id'],
      'to_note_id': connection['to_note_id'],
      'name': connection['name'],
      'connection_color': connection['connection_color'],
      'database_id': connection['database_id'],
    };
    
    final preparedConnection = BackupData.prepareForSqlite(filteredConnection);
    
    try {
      if (txn != null) {
        await txn.insert('connections', preparedConnection);
      } else {
        final db = await database;
        await db.insert('connections', preparedConnection);
      }
    } catch (e) {
      // Обрабатываем ошибки уникальных ограничений
      if (e.toString().contains('UNIQUE constraint failed') || 
          e.toString().contains('UNIQUE') ||
          e.toString().contains('PRIMARY KEY')) {
        print('Конфликт уникальности при вставке соединения: ${preparedConnection['name']}, пытаемся обновить');
        
        try {
          // Пытаемся обновить существующую запись
          if (preparedConnection['id'] != null) {
            if (txn != null) {
              await txn.update(
                'connections',
                preparedConnection,
                where: 'id = ?',
                whereArgs: [preparedConnection['id']],
              );
            } else {
              final db = await database;
              await db.update(
                'connections',
                preparedConnection,
                where: 'id = ?',
                whereArgs: [preparedConnection['id']],
              );
            }
            print('Соединение успешно обновлено: ${preparedConnection['name']}');
          } else {
            print('Пропускаем соединение без ID: ${preparedConnection['name']}');
          }
        } catch (updateError) {
          print('Ошибка при обновлении соединения: $updateError');
        }
      } else {
        print('Ошибка при вставке соединения: $e');
        rethrow;
      }
    }
  }

  Future<void> insertImageForBackup(int noteId, String fileName, Uint8List imageData, [Transaction? txn, String? databaseId]) async {
    try {
      if (txn != null) {
        // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавляем database_id при вставке изображения
        await txn.rawInsert('''
          INSERT OR REPLACE INTO note_images (note_id, file_name, image_data, database_id)
          VALUES (?, ?, ?, ?)
        ''', [noteId, fileName, imageData, databaseId]);
      } else {
        final db = await database;
        await db.rawInsert('''
          INSERT OR REPLACE INTO note_images (note_id, file_name, image_data, database_id)
          VALUES (?, ?, ?, ?)
        ''', [noteId, fileName, imageData, databaseId]);
      }
      print('✅ ИЗОБРАЖЕНИЕ: Вставлено изображение $fileName для заметки $noteId в базу $databaseId');
    } catch (e) {
      print('❌ ИЗОБРАЖЕНИЕ: Ошибка при вставке изображения $fileName для заметки $noteId: $e');
      rethrow;
    }
  }

  Future<void> deleteFolder(int id) async {
    final db = await database;
    await db.delete(
      'folders',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceDatabase(BackupData backupData) async {
    final db = await database;
    await db.transaction((txn) async {
      // Очищаем все таблицы
      await clearAllTablesForBackup(txn);

      // Восстанавливаем папки
      for (var folder in backupData.folders) {
        await insertFolderForBackup(folder, txn);
      }

      // Восстанавливаем заметки
      for (var note in backupData.notes) {
        await insertNoteForBackup(note, txn);
      }

      // Восстанавливаем записи расписания
      for (var entry in backupData.scheduleEntries) {
        await insertScheduleEntryForBackup(entry, txn);
      }

      // Восстанавливаем заметки на доске
      for (var note in backupData.pinboardNotes) {
        await insertPinboardNoteForBackup(note, txn);
      }

      // Восстанавливаем соединения
      for (var connection in backupData.connections) {
        await insertConnectionForBackup(connection, txn);
      }

      // Восстанавливаем изображения
      for (var image in backupData.noteImages) {
        var imageData = image['image_data'];
        if (imageData is String) {
          // Если данные в формате base64
          imageData = base64Decode(imageData);
        } else if (imageData is List) {
          // Если данные в формате списка
          imageData = Uint8List.fromList(imageData.cast<int>());
        }
        
        await insertImageForBackup(
          image['note_id'],
          image['file_name'],
          imageData,
          txn,
          image['database_id']
        );
      }
    });

    // Уведомляем об изменении базы данных
    _notifyDatabaseChanged();
  }

  void _notifyDatabaseChanged() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      context.read<DatabaseProvider>().setNeedsUpdate(true);
    }
  }

  Future<BackupData> createBackup([String? databaseId]) async {
    print('Начало создания резервной копии');
    try {
      // Получаем все данные из базы
      final folders = await getFolders(databaseId);
      final notes = await getAllNotes(databaseId);
      final scheduleEntries = await getScheduleEntries(databaseId);
      final pinboardNotes = await getPinboardNotes(databaseId);  // Используем существующий метод
      final connections = await getConnectionsDB(databaseId);  // Используем существующий метод
      final noteImages = await getAllImages(databaseId);  // Используем существующий метод

      print('Создание резервной копии для базы ${databaseId ?? "локальной"}:');
      print('  Папок: ${folders.length}');
      print('  Заметок: ${notes.length}');
      print('  Записей расписания: ${scheduleEntries.length}');
      print('  Элементов доски: ${pinboardNotes.length}');  // ИСПРАВЛЕНО: добавляем вывод количества элементов доски
      print('  Соединений: ${connections.length}');
      print('  Изображений: ${noteImages.length}');

      // ИСПРАВЛЕНО: Создаем список изображений с данными из базы или пустой список
      List<Map<String, dynamic>> imagesWithData = [];
      if (noteImages.isNotEmpty) {
        print('Загрузка данных изображений из базы...');
        final db = await database;
        
        for (var img in noteImages) {
          try {
            // Получаем данные изображения из базы
            final imageDataRows = await db.query(
              'note_images',
              where: 'note_id = ? AND file_name = ?',
              whereArgs: [img.noteId, img.imagePath],
            );
            
            if (imageDataRows.isNotEmpty && imageDataRows.first['image_data'] != null) {
              imagesWithData.add({
                'id': img.id,
                'note_id': img.noteId,
                'file_name': img.imagePath,
                'image_data': imageDataRows.first['image_data'],  // Реальные данные из базы
                'database_id': databaseId,
              });
            }
          } catch (e) {
            print('Ошибка при загрузке данных изображения ${img.imagePath}: $e');
            // Пропускаем это изображение
          }
        }
        print('Загружено изображений с данными: ${imagesWithData.length} из ${noteImages.length}');
      }

      // Преобразуем данные в формат BackupData
      final backup = BackupData(
        folders: folders.map((f) => {
          'id': f.id,
          'name': f.name,
          'color': f.color,
          'is_expanded': f.isExpanded ? 1 : 0,
          'database_id': databaseId,
        }).toList(),
        notes: notes.map((n) => {
          'id': n.id,
          'title': n.title,
          'content': n.content,
          'folder_id': n.folderId,
          'created_at': n.createdAt.toIso8601String(),
          'updated_at': n.updatedAt.toIso8601String(),
          'database_id': databaseId,
        }).toList(),
        scheduleEntries: scheduleEntries.map((s) => {
          'id': s.id,
          'date': s.date,
          'time': s.time,
          'note': s.note,
          'dynamic_fields_json': s.dynamicFieldsJson,  // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: добавляю отсутствующие поля
          'recurrence_json': s.recurrence != null ? jsonEncode(s.recurrence!.toMap()) : null,
          'tags_json': s.tags.isNotEmpty ? jsonEncode(s.tags) : null, // ИСПРАВЛЕНИЕ: Добавляю поле tags_json
          'database_id': databaseId,
        }).toList(),
        pinboardNotes: pinboardNotes.map((p) => {  // ИСПРАВЛЕНО: используем правильные имена полей
          'id': p.id,
          'title': p.title,
          'content': p.content,
          'position_x': p.posX,  // ИСПРАВЛЕНО: правильное поле
          'position_y': p.posY,  // ИСПРАВЛЕНО: правильное поле
          'width': p.width,
          'height': p.height,
          'background_color': p.backgroundColor,  // ИСПРАВЛЕНО: правильное поле
          'icon': p.icon,
          'database_id': databaseId,
        }).toList(),
        connections: connections.map((c) => {
          'id': c.id,
          'from_note_id': c.fromId,  // ИСПРАВЛЕНО: правильное поле
          'to_note_id': c.toId,  // ИСПРАВЛЕНО: правильное поле
          'name': c.name,
          'connection_color': c.connectionColor,  // ИСПРАВЛЕНО: правильное поле
          'database_id': databaseId,
        }).toList(),
        noteImages: imagesWithData,  // ИСПРАВЛЕНО: используем загруженные данные изображений
      );

      print('Резервная копия успешно создана');
      return backup;
    } catch (e) {
      print('Ошибка при создании резервной копии: $e');
      rethrow;
    }
  }

  Future<void> restoreFromBackup(BackupData backup, [String? databaseId]) async {
    return await _safeDbOperation(() async {
      print('Начало восстановления из резервной копии для базы ${databaseId ?? "локальной"}');
      
      print('Данные для восстановления: папок - ${backup.folders.length}, ' +
            'заметок - ${backup.notes.length}, ' +
            'записей расписания - ${backup.scheduleEntries.length}, ' +
            'изображений - ${backup.noteImages.length}');
      
      final db = await database;
      
      try {
        await db.transaction((txn) async {
          // Начинаем очистку таблиц
          print('Начало очистки таблиц для базы $databaseId');
          
          if (databaseId != null) {
            // Очищаем существующие данные для указанной базы
            await txn.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
            await txn.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
            await txn.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
            await txn.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
            await txn.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
            
            // Удаляем изображения, связанные с заметками из этой базы
            await txn.delete('note_images', 
              where: 'note_id IN (SELECT id FROM notes WHERE database_id = ?)', 
              whereArgs: [databaseId]
            );
          } else {
            // Очищаем основную базу данных (для локальных данных)
            await txn.delete('folders', where: 'database_id IS NULL');
            await txn.delete('notes', where: 'database_id IS NULL');
            await txn.delete('schedule_entries', where: 'database_id IS NULL');
            await txn.delete('pinboard_notes', where: 'database_id IS NULL');
            await txn.delete('connections', where: 'database_id IS NULL');
            
            // Удаляем изображения, связанные с локальными заметками
            await txn.delete('note_images', 
              where: 'note_id IN (SELECT id FROM notes WHERE database_id IS NULL)'
            );
          }
          print('Очищены таблицы для базы $databaseId');
          
          // Счетчики для отслеживания успешно восстановленных элементов
          int restoredFolders = 0;
          int restoredNotes = 0;
          int restoredSchedule = 0;
          int restoredPinboard = 0;
          int restoredConnections = 0;
          int restoredImages = 0;
          
          // Восстанавливаем папки с обработкой ошибок
          print('Восстановление папок...');
          for (var folder in backup.folders) {
            try {
              if (databaseId != null) {
                folder['database_id'] = databaseId;
              } else {
                folder.remove('database_id');
              }
              await insertFolderForBackup(folder, txn);
              restoredFolders++;
            } catch (e) {
              print('Ошибка при восстановлении папки ${folder['name']}: $e');
            }
          }
          
          // Восстанавливаем заметки с обработкой ошибок
          print('Восстановление заметок...');
          for (var note in backup.notes) {
            try {
              if (databaseId != null) {
                note['database_id'] = databaseId;
              } else {
                note.remove('database_id');
              }
              await insertNoteForBackup(note, txn);
              restoredNotes++;
            } catch (e) {
              print('Ошибка при восстановлении заметки ${note['title']}: $e');
            }
          }
          
          // Восстанавливаем записи расписания с обработкой ошибок
          print('Восстановление записей расписания...');
          for (var entry in backup.scheduleEntries) {
            try {
              if (databaseId != null) {
                entry['database_id'] = databaseId;
              } else {
                entry.remove('database_id');
              }
              await insertScheduleEntryForBackup(entry, txn);
              restoredSchedule++;
            } catch (e) {
              print('Ошибка при восстановлении записи расписания: $e');
            }
          }
          
          // Восстанавливаем заметки на доске с обработкой ошибок
          print('Восстановление заметок на доске...');
          for (var note in backup.pinboardNotes) {
            try {
              if (databaseId != null) {
                note['database_id'] = databaseId;
              } else {
                note.remove('database_id');
              }
              await insertPinboardNoteForBackup(note, txn);
              restoredPinboard++;
            } catch (e) {
              print('Ошибка при восстановлении заметки на доске: $e');
            }
          }
          
          // Восстанавливаем соединения с обработкой ошибок
          print('Восстановление соединений...');
          for (var connection in backup.connections) {
            try {
              if (databaseId != null) {
                connection['database_id'] = databaseId;
              } else {
                connection.remove('database_id');
              }
              await insertConnectionForBackup(connection, txn);
              restoredConnections++;
            } catch (e) {
              print('Ошибка при восстановлении соединения: $e');
            }
          }
          
          // Восстановление изображений с обработкой ошибок
          if (backup.noteImages.isNotEmpty) {
            print('Восстановление изображений (всего: ${backup.noteImages.length})...');
            
            for (var image in backup.noteImages) {
              try {
                if (image['image_data'] == null || 
                   (image['image_data'] is Uint8List && (image['image_data'] as Uint8List).isEmpty)) {
                  continue;
                }
                
                Uint8List imageData;
                if (image['image_data'] is Uint8List) {
                  imageData = image['image_data'] as Uint8List;
                } else if (image['image_data'] is List) {
                  imageData = Uint8List.fromList(List<int>.from(image['image_data']));
                } else if (image['image_data'] is String) {
                  imageData = base64Decode(image['image_data']);
                } else {
                  print('  Неизвестный тип данных изображения: ${image['image_data'].runtimeType}');
                  continue;
                }
                
                if (imageData.isNotEmpty) {
                  await insertImageForBackup(
                    image['note_id'], 
                    image['file_name'], 
                    imageData, 
                    txn,
                    databaseId  // ✅ ИСПРАВЛЕНИЕ: передаем databaseId, а не image['database_id']
                  );
                  restoredImages++;
                }
              } catch (e) {
                print('  Ошибка при восстановлении изображения ${image['file_name']}: $e');
              }
            }
          }
          
          print('Итоги восстановления:');
          print('  Папок: $restoredFolders из ${backup.folders.length}');
          print('  Заметок: $restoredNotes из ${backup.notes.length}');
          print('  Записей расписания: $restoredSchedule из ${backup.scheduleEntries.length}');
          print('  Заметок на доске: $restoredPinboard из ${backup.pinboardNotes.length}');
          print('  Соединений: $restoredConnections из ${backup.connections.length}');
          print('  Изображений: $restoredImages из ${backup.noteImages.length}');
        });
        
        print('Восстановление из резервной копии успешно завершено');
        
        // ИСПРАВЛЕНИЕ: Синхронное уведомление об изменении базы данных для гарантированного обновления UI
        try {
          _notifyDatabaseChanged();
          print('Уведомление об изменении базы данных отправлено');
        } catch (e) {
          print('Ошибка при уведомлении об изменении базы данных: $e');
        }
        
      } catch (e) {
        print('Критическая ошибка при восстановлении из резервной копии: $e');
        throw e;
      }
    });
  }

  Future<void> addSharedDatabase(SharedDatabase database) async {
    final db = await this.database;
    await db.insert('shared_databases', database.toMap());
  }

  Future<List<SharedDatabase>> getSharedDatabases() async {
    final db = await this.database;
    final List<Map<String, dynamic>> maps = await db.query('shared_databases');
    return List.generate(maps.length, (i) => SharedDatabase.fromMap(maps[i]));
  }

  Future<void> updateSharedDatabase(SharedDatabase database) async {
    final db = await this.database;
    await db.update(
      'shared_databases',
      database.toMap(),
      where: 'server_id = ?',
      whereArgs: [database.serverId],
    );
  }

  Future<void> deleteSharedDatabase(String serverId) async {
    final db = await this.database;
    await db.delete(
      'shared_databases',
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
  }

  /// ИСПРАВЛЕНИЕ: Оптимизированный импорт данных БЕЗ сложной очистки таблиц
  /// Используется при переключении на совместную базу данных
  Future<void> importDatabaseOptimized(String databaseId, Map<String, dynamic> data) async {
    print('🔍 ДИАГНОСТИКА: Вход в importDatabaseOptimized для базы $databaseId');
    
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Добавляем таймаут для всей операции импорта
    return await Future.any([
      _performImportWithSafeOperation(databaseId, data),
      Future.delayed(Duration(seconds: 30), () => throw TimeoutException('Таймаут операции импорта данных'))
    ]);
  }
  
  /// Выполнение импорта с безопасными операциями
  Future<void> _performImportWithSafeOperation(String databaseId, Map<String, dynamic> data) async {
    return await _safeDbOperation(() async {
      print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Начало импорта данных для базы данных $databaseId');
      print('🔍 ДИАГНОСТИКА: Получение соединения с базой данных...');
      
      final db = await database;
      print('🔍 ДИАГНОСТИКА: Соединение с базой данных получено успешно');
      
      try {
        print('🔍 ДИАГНОСТИКА: Начало очистки таблиц...');
        
        // ИСПРАВЛЕНИЕ: Быстрая очистка без сложных транзакций и проверок
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Быстрая очистка таблиц для базы $databaseId...');
        
        // Простые DELETE запросы без транзакций для ускорения
        print('🔍 ДИАГНОСТИКА: Удаление соединений...');
        await db.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
        
        print('🔍 ДИАГНОСТИКА: Удаление заметок на доске...');
        await db.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
        
        print('🔍 ДИАГНОСТИКА: Удаление записей расписания...');
        await db.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
        
        print('🔍 ДИАГНОСТИКА: Удаление заметок...');
        await db.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
        
        print('🔍 ДИАГНОСТИКА: Удаление папок...');
        await db.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
        
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Таблицы быстро очищены');
        print('🔍 ДИАГНОСТИКА: Очистка таблиц завершена, начинаем импорт данных...');
        
        int foldersCount = 0;
        int notesCount = 0;
        int scheduleCount = 0;
        int pinboardCount = 0;
        int connectionsCount = 0;
        int imagesCount = 0;
        
        // ШАГ 1: Импортируем папки (быстрая операция)
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 1 - Импорт папок...');
        if (data['folders'] != null && data['folders'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка папок: ${data['folders'].length}');
          // ИСПРАВЛЕНИЕ: Импортируем без транзакций для ускорения
          for (var folder in (data['folders'] as List)) {
            try {
              folder['database_id'] = databaseId;
              await insertFolderForBackup(folder, null); // Без транзакции
              foldersCount++;
            } catch (e) {
              print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте папки: $e');
            }
          }
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано папок: $foldersCount');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Папок для импорта нет');
        }

        // ШАГ 1.5: КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ - Создаем базовую папку если папок нет вообще
        if (foldersCount == 0) {
          print('⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Папок нет, создаем базовую папку для базы $databaseId');
          try {
            final folderId = await db.insert('folders', {
              'name': 'Общие заметки',
              'color': 0xFF4CAF50,
              'is_expanded': 1,
              'database_id': databaseId,
            });
            foldersCount = 1;
            print('✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Создана базовая папка с ID $folderId');
          } catch (e) {
            print('❌ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Ошибка создания базовой папки: $e');
          }
        }

        // ШАГ 2: Импортируем заметки (может быть медленнее)
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 2 - Импорт заметок...');
        if (data['notes'] != null && data['notes'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка заметок: ${data['notes'].length}');
          // ИСПРАВЛЕНИЕ: Импортируем без транзакций для ускорения
          for (var note in (data['notes'] as List)) {
            try {
              note['database_id'] = databaseId;
              
              // ⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Проверяем и создаем недостающую папку
              if (note['folder_id'] != null) {
                final folderExists = await db.query(
                  'folders',
                  where: 'id = ? AND database_id = ?',
                  whereArgs: [note['folder_id'], databaseId],
                );
                
                if (folderExists.isEmpty) {
                  print('⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Папка ${note['folder_id']} не существует, создаем ее');
                  try {
                    await db.insert('folders', {
                      'id': note['folder_id'],
                      'name': 'Папка ${note['folder_id']}',
                      'color': 0xFF2196F3,
                      'is_expanded': 1,
                      'database_id': databaseId,
                    });
                    print('✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Создана недостающая папка ${note['folder_id']}');
                  } catch (folderError) {
                    print('❌ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Ошибка создания папки ${note['folder_id']}: $folderError');
                    // Обнуляем folder_id как запасной вариант
                    note['folder_id'] = null;
                  }
                }
              }
              
              await insertNoteForBackup(note, null); // Без транзакции
              notesCount++;
            } catch (e) {
              print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте заметки: $e');
            }
          }
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано заметок: $notesCount');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Заметок для импорта нет');
        }

        // ШАГ 3: Импортируем записи расписания (обе версии)
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 3 - Импорт записей расписания...');
        if (data['schedule_entries'] != null && data['schedule_entries'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка записей расписания: ${data['schedule_entries'].length}');
          await db.transaction((txn) async {
            for (var entry in (data['schedule_entries'] as List)) {
              try {
                entry['database_id'] = databaseId;
                await insertScheduleEntryForBackup(entry, txn);
                scheduleCount++;
              } catch (e) {
                print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте записи расписания: $e');
              }
            }
          });
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано записей расписания: $scheduleCount');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Записей расписания для импорта нет');
        }
        
        // ДОБАВЛЕНО: Поддержка camelCase от сервера
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 3b - Импорт записей расписания (camelCase)...');
        if (data['scheduleEntries'] != null && data['scheduleEntries'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка записей расписания (camelCase): ${data['scheduleEntries'].length}');
          await db.transaction((txn) async {
            for (var entry in (data['scheduleEntries'] as List)) {
              try {
                entry['database_id'] = databaseId;
                await insertScheduleEntryForBackup(entry, txn);
                scheduleCount++;
              } catch (e) {
                print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте записи расписания (camelCase): $e');
              }
            }
          });
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано записей расписания (camelCase): ${scheduleCount - (data['schedule_entries']?.length ?? 0)}');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Записей расписания (camelCase) для импорта нет');
        }

        // ШАГ 4: Импортируем заметки на доске (обе версии)
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 4 - Импорт заметок на доске...');
        if (data['pinboard_notes'] != null && data['pinboard_notes'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка заметок на доске: ${data['pinboard_notes'].length}');
          await db.transaction((txn) async {
            for (var note in (data['pinboard_notes'] as List)) {
              try {
                note['database_id'] = databaseId;
                await insertPinboardNoteForBackup(note, txn);
                pinboardCount++;
              } catch (e) {
                print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте заметки на доске: $e');
              }
            }
          });
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано заметок на доске: $pinboardCount');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Заметок на доске для импорта нет');
        }
        
        // ДОБАВЛЕНО: Поддержка camelCase от сервера
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 4b - Импорт заметок на доске (camelCase)...');
        if (data['pinboardNotes'] != null && data['pinboardNotes'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка заметок на доске (camelCase): ${data['pinboardNotes'].length}');
          await db.transaction((txn) async {
            for (var note in (data['pinboardNotes'] as List)) {
              try {
                note['database_id'] = databaseId;
                await insertPinboardNoteForBackup(note, txn);
                pinboardCount++;
              } catch (e) {
                print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте заметки на доске (camelCase): $e');
              }
            }
          });
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано заметок на доске (camelCase): ${pinboardCount - (data['pinboard_notes']?.length ?? 0)}');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Заметок на доске (camelCase) для импорта нет');
        }

        // ШАГ 5: Импортируем соединения
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 5 - Импорт соединений...');
        if (data['connections'] != null && data['connections'] is List) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка соединений: ${data['connections'].length}');
          await db.transaction((txn) async {
            for (var connection in (data['connections'] as List)) {
              try {
                connection['database_id'] = databaseId;
                await insertConnectionForBackup(connection, txn);
                connectionsCount++;
              } catch (e) {
                print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте соединения: $e');
              }
            }
          });
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано соединений: $connectionsCount');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Соединений для импорта нет');
        }
        
        // ШАГ 6: Импортируем изображения (может быть самое медленное)
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: ШАГ 6 - Импорт изображений...');
        
        // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Поддержка как 'note_images' так и 'images' от сервера
        List? imagesList;
        if (data['images'] != null && data['images'] is List) {
          imagesList = data['images'] as List;
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Найдены изображения в поле "images": ${imagesList.length}');
        } else if (data['note_images'] != null && data['note_images'] is List) {
          imagesList = data['note_images'] as List;
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Найдены изображения в поле "note_images": ${imagesList.length}');
        }
        
        if (imagesList != null && imagesList.isNotEmpty) {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка изображений: ${imagesList.length}');
          
          // Импортируем изображения небольшими пакетами
          for (int i = 0; i < imagesList.length; i += 3) { // По 3 изображения за раз для скорости
            final batch = imagesList.skip(i).take(3).toList();
            print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Обработка пакета изображений ${i + 1}-${i + batch.length} из ${imagesList.length}');
            
            await db.transaction((txn) async {
              for (var image in batch) {
                try {
                  // ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Правильная обработка base64 данных от сервера
                  String? imageDataBase64;
                  Uint8List? imageBytes;
                  
                  if (image['image_data'] != null && image['image_data'] is String) {
                    // Данные от сервера в base64
                    imageDataBase64 = image['image_data'] as String;
                    try {
                      imageBytes = base64Decode(imageDataBase64);
                      print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Декодированы base64 данные изображения ${image['file_name']}, размер: ${imageBytes.length} байт');
                    } catch (e) {
                      print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка декодирования base64 для ${image['file_name']}: $e');
                      continue;
                    }
                  } else if (image['image_data'] != null && image['image_data'] is Uint8List) {
                    // Данные уже в виде Uint8List
                    imageBytes = image['image_data'] as Uint8List;
                  } else if (image['image_data'] != null && image['image_data'] is List<int>) {
                    // Данные в виде List<int>
                    imageBytes = Uint8List.fromList(List<int>.from(image['image_data']));
                  } else {
                    print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Нет данных изображения для ${image['file_name']}');
                    continue;
                  }
                  
                  if (imageBytes != null) {
                    await insertImageForBackup(
                      image['note_id'],
                      image['file_name'],
                      imageBytes,
                      txn,
                      databaseId  // ✅ ИСПРАВЛЕНИЕ: передаем databaseId, а не image['database_id']
                    );
                    imagesCount++;
                    print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано изображение ${image['file_name']} для заметки ${image['note_id']}');
                  }
                } catch (e) {
                  print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Ошибка при импорте изображения ${image['file_name']}: $e');
                }
              }
            });
          }
          print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импортировано изображений: $imagesCount');
        } else {
          print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Изображений для импорта нет');
        }
        
        print('✅ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Общий итог импорта: папок - $foldersCount, заметок - $notesCount, ' +
              'записей расписания - $scheduleCount, заметок на доске - $pinboardCount, ' +
              'соединений - $connectionsCount, изображений - $imagesCount');
        
        print('📦 ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Импорт данных для базы $databaseId успешно завершен');
        
      } catch (e) {
        print('❌ ОПТИМИЗИРОВАННЫЙ ИМПОРТ: Критическая ошибка импорта для базы $databaseId: $e');
        throw e;
      }
    });
  }

  Future<void> importDatabase(String databaseId, Map<String, dynamic> data) async {
    return await _safeDbOperation(() async {
      print('📦 ИМПОРТ: Начало импорта данных для базы данных $databaseId');
      
      final db = await database;
      
      try {
        // ИСПРАВЛЕНИЕ: Разбиваем импорт на более мелкие транзакции чтобы избежать долгих блокировок
        
        // ШАГ 1: Очищаем существующие данные (быстрая операция)
        print('📦 ИМПОРТ: ШАГ 1 - Очистка существующих данных...');
        await db.transaction((txn) async {
          await clearDatabaseTables(databaseId, txn);
        });
        print('✅ ИМПОРТ: Таблицы очищены для базы $databaseId');
        
        int foldersCount = 0;
        int notesCount = 0;
        int scheduleCount = 0;
        int pinboardCount = 0;
        int connectionsCount = 0;
        int imagesCount = 0;
        
        // ШАГ 2: Импортируем папки (быстрая операция)
        print('📦 ИМПОРТ: ШАГ 2 - Импорт папок...');
        if (data['folders'] != null && data['folders'] is List) {
          print('📦 ИМПОРТ: Обработка папок: ${data['folders'].length}');
          await db.transaction((txn) async {
            for (var folder in (data['folders'] as List)) {
              try {
                folder['database_id'] = databaseId;
                await insertFolderForBackup(folder, txn);
                foldersCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте папки: $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано папок: $foldersCount');
        } else {
          print('📦 ИМПОРТ: Папок для импорта нет');
        }

        // ШАГ 2.5: КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ - Создаем базовую папку если папок нет
        if (foldersCount == 0) {
          print('⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Папок нет, создаем базовую папку для базы $databaseId');
          await db.transaction((txn) async {
            try {
              final folderId = await txn.insert('folders', {
                'name': 'Общие заметки',
                'color': 0xFF4CAF50,
                'is_expanded': 1,
                'database_id': databaseId,
              });
              foldersCount = 1;
              print('✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Создана базовая папка с ID $folderId');
            } catch (e) {
              print('❌ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Ошибка создания базовой папки: $e');
            }
          });
        }

        // ШАГ 3: Импортируем заметки (может быть медленнее)
        print('📦 ИМПОРТ: ШАГ 3 - Импорт заметок...');
        if (data['notes'] != null && data['notes'] is List) {
          print('📦 ИМПОРТ: Обработка заметок: ${data['notes'].length}');
          await db.transaction((txn) async {
            for (var note in (data['notes'] as List)) {
              try {
                note['database_id'] = databaseId;
                
                // ⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Проверяем и создаем недостающую папку
                if (note['folder_id'] != null) {
                  final folderExists = await txn.query(
                    'folders',
                    where: 'id = ? AND database_id = ?',
                    whereArgs: [note['folder_id'], databaseId],
                  );
                  
                  if (folderExists.isEmpty) {
                    print('⚠️ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Папка ${note['folder_id']} не существует, создаем ее');
                    try {
                      await txn.insert('folders', {
                        'id': note['folder_id'],
                        'name': 'Папка ${note['folder_id']}',
                        'color': 0xFF2196F3,
                        'is_expanded': 1,
                        'database_id': databaseId,
                      });
                      print('✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Создана недостающая папка ${note['folder_id']}');
                    } catch (folderError) {
                      print('❌ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Ошибка создания папки ${note['folder_id']}: $folderError');
                      // Обнуляем folder_id как запасной вариант
                      note['folder_id'] = null;
                    }
                  }
                }
                
                await insertNoteForBackup(note, txn);
                notesCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте заметки: $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано заметок: $notesCount');
        } else {
          print('📦 ИМПОРТ: Заметок для импорта нет');
        }

        // ШАГ 4: Импортируем записи расписания (обе версии)
        print('📦 ИМПОРТ: ШАГ 4 - Импорт записей расписания...');
        if (data['schedule_entries'] != null && data['schedule_entries'] is List) {
          print('📦 ИМПОРТ: Обработка записей расписания: ${data['schedule_entries'].length}');
          await db.transaction((txn) async {
            for (var entry in (data['schedule_entries'] as List)) {
              try {
                entry['database_id'] = databaseId;
                await insertScheduleEntryForBackup(entry, txn);
                scheduleCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте записи расписания: $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано записей расписания: $scheduleCount');
        } else {
          print('📦 ИМПОРТ: Записей расписания для импорта нет');
        }
        
        // ДОБАВЛЕНО: Поддержка camelCase от сервера
        print('📦 ИМПОРТ: ШАГ 4b - Импорт записей расписания (camelCase)...');
        if (data['scheduleEntries'] != null && data['scheduleEntries'] is List) {
          print('📦 ИМПОРТ: Обработка записей расписания (camelCase): ${data['scheduleEntries'].length}');
          await db.transaction((txn) async {
            for (var entry in (data['scheduleEntries'] as List)) {
              try {
                entry['database_id'] = databaseId;
                await insertScheduleEntryForBackup(entry, txn);
                scheduleCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте записи расписания (camelCase): $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано записей расписания (camelCase): ${scheduleCount - (data['schedule_entries']?.length ?? 0)}');
        } else {
          print('📦 ИМПОРТ: Записей расписания (camelCase) для импорта нет');
        }

        // ШАГ 5: Импортируем заметки на доске (обе версии)
        print('📦 ИМПОРТ: ШАГ 5 - Импорт заметок на доске...');
        if (data['pinboard_notes'] != null && data['pinboard_notes'] is List) {
          print('📦 ИМПОРТ: Обработка заметок на доске: ${data['pinboard_notes'].length}');
          await db.transaction((txn) async {
            for (var note in (data['pinboard_notes'] as List)) {
              try {
                note['database_id'] = databaseId;
                await insertPinboardNoteForBackup(note, txn);
                pinboardCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте заметки на доске: $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано заметок на доске: $pinboardCount');
        } else {
          print('📦 ИМПОРТ: Заметок на доске для импорта нет');
        }
        
        // ДОБАВЛЕНО: Поддержка camelCase от сервера
        print('📦 ИМПОРТ: ШАГ 5b - Импорт заметок на доске (camelCase)...');
        if (data['pinboardNotes'] != null && data['pinboardNotes'] is List) {
          print('📦 ИМПОРТ: Обработка заметок на доске (camelCase): ${data['pinboardNotes'].length}');
          await db.transaction((txn) async {
            for (var note in (data['pinboardNotes'] as List)) {
              try {
                note['database_id'] = databaseId;
                await insertPinboardNoteForBackup(note, txn);
                pinboardCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте заметки на доске (camelCase): $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано заметок на доске (camelCase): ${pinboardCount - (data['pinboard_notes']?.length ?? 0)}');
        } else {
          print('📦 ИМПОРТ: Заметок на доске (camelCase) для импорта нет');
        }

        // ШАГ 6: Импортируем соединения
        print('📦 ИМПОРТ: ШАГ 6 - Импорт соединений...');
        if (data['connections'] != null && data['connections'] is List) {
          print('📦 ИМПОРТ: Обработка соединений: ${data['connections'].length}');
          await db.transaction((txn) async {
            for (var connection in (data['connections'] as List)) {
              try {
                connection['database_id'] = databaseId;
                await insertConnectionForBackup(connection, txn);
                connectionsCount++;
              } catch (e) {
                print('❌ ИМПОРТ: Ошибка при импорте соединения: $e');
              }
            }
          });
          print('✅ ИМПОРТ: Импортировано соединений: $connectionsCount');
        } else {
          print('📦 ИМПОРТ: Соединений для импорта нет');
        }
        
        // ШАГ 7: Импортируем изображения (может быть самое медленное)
        print('📦 ИМПОРТ: ШАГ 7 - Импорт изображений...');
        if (data['note_images'] != null && data['note_images'] is List) {
          print('📦 ИМПОРТ: Обработка изображений: ${data['note_images'].length}');
          // Импортируем изображения небольшими пакетами
          final images = data['note_images'] as List;
          for (int i = 0; i < images.length; i += 5) { // По 5 изображений за раз
            final batch = images.skip(i).take(5).toList();
            print('📦 ИМПОРТ: Обработка пакета изображений ${i + 1}-${i + batch.length} из ${images.length}');
            await db.transaction((txn) async {
              for (var image in batch) {
                try {
                  await insertImageForBackup(
                    image['note_id'],
                    image['file_name'],
                    image['image_data'] is Uint8List 
                      ? image['image_data'] 
                      : Uint8List.fromList(List<int>.from(image['image_data'])),
                    txn,
                    image['database_id']
                  );
                  imagesCount++;
                } catch (e) {
                  print('❌ ИМПОРТ: Ошибка при импорте изображения: $e');
                }
              }
            });
          }
          print('✅ ИМПОРТ: Импортировано изображений: $imagesCount');
        } else {
          print('📦 ИМПОРТ: Изображений для импорта нет');
        }
        
        print('📦 ИМПОРТ: ШАГ 8 - Создание базовой структуры если нужно...');
        print('✅ ИМПОРТ: Общий итог импорта: папок - $foldersCount, заметок - $notesCount, ' +
              'записей расписания - $scheduleCount, заметок на доске - $pinboardCount, ' +
              'соединений - $connectionsCount, изображений - $imagesCount');
        
        // ШАГ 8: Создаем базовую структуру если данных нет
        if (foldersCount == 0 && notesCount == 0) {
          print('📦 ИМПОРТ: Создание базовой структуры для пустой базы $databaseId');
          await db.transaction((txn) async {
            try {
              // Вставляем общую папку
              final folderId = await txn.insert('folders', {
                'name': 'Общие заметки',
                'color': 0xFF4CAF50,
                'is_expanded': 1,
                'database_id': databaseId,
              });
              
              // Создаем демо-заметку
              await txn.insert('notes', {
                'title': 'Совместная работа',
                'content': 'Это заметка для совместной работы. Она будет синхронизироваться с другими участниками.',
                'folder_id': folderId,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'database_id': databaseId,
              });
              
              print('✅ ИМПОРТ: Базовая структура создана успешно');
            } catch (e) {
              print('❌ ИМПОРТ: Ошибка при создании базовой структуры: $e');
            }
          });
        } else {
          print('📦 ИМПОРТ: Базовая структура не нужна - данные уже есть');
        }
        
        print('🎉 ИМПОРТ: Импорт данных для базы $databaseId завершен успешно');
        
        // Уведомляем об изменении базы данных
        print('📦 ИМПОРТ: Отправка уведомления об изменении базы данных...');
        Future.microtask(() {
          try {
            _notifyDatabaseChanged();
            print('✅ ИМПОРТ: Уведомление об изменении базы данных отправлено');
          } catch (e) {
            print('❌ ИМПОРТ: Ошибка при уведомлении об изменении базы данных: $e');
          }
        });
        
      } catch (e) {
        print('❌ ИМПОРТ: Критическая ошибка при импорте данных: $e');
        throw e;
      }
    });
  }

  Future<void> initializeSharedTables(String databaseId, Transaction txn) async {
    // Создаем таблицу папок
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        is_expanded INTEGER NOT NULL DEFAULT 1,
        database_id TEXT
      )
    ''');

    // Создаем таблицу заметок
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT,
        folder_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        images TEXT,
        metadata TEXT,
        content_json TEXT,
        database_id TEXT,
        FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
      )
    ''');

    // Таблица расписания
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS schedule_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT,
        date TEXT,
        note TEXT,
        dynamic_fields_json TEXT,
        recurrence_json TEXT,
        database_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        tags_json TEXT
      )
    ''');

    // Таблица заметок на доске
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS pinboard_notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        position_x REAL,
        position_y REAL,
        width REAL,
        height REAL,
        background_color INTEGER,
        icon INTEGER,
        database_id TEXT
      )
    ''');

    // Таблица соединений заметок
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_note_id INTEGER,
        to_note_id INTEGER,
        type TEXT,
        name TEXT,
        connection_color INTEGER,
        database_id TEXT,
        FOREIGN KEY (from_note_id) REFERENCES pinboard_notes (id),
        FOREIGN KEY (to_note_id) REFERENCES pinboard_notes (id)
      )
    ''');

    // Таблица изображений
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS note_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        image_data BLOB NOT NULL,
        database_id TEXT,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE,
        UNIQUE(note_id, file_name)
      )
    ''');

    print('Таблицы для совместной базы $databaseId успешно созданы');
  }

  Future<void> switchToSharedDatabase(SharedDatabase sharedDb) async {
    final db = await database;
    await db.execute('ATTACH DATABASE ? AS shared', [sharedDb.databasePath]);
    await db.execute('CREATE TABLE IF NOT EXISTS notes AS SELECT * FROM shared.notes');
    await db.execute('DETACH DATABASE shared');
  }

  Future<List<Map<String, dynamic>>> getChangesSince(DateTime? lastSync) async {
    final db = await database;
    final List<Map<String, dynamic>> changes = [];
    
    if (lastSync != null) {
      final notes = await db.query(
        'notes',
        where: 'updated_at > ?',
        whereArgs: [lastSync.toIso8601String()],
      );
      changes.addAll(notes);
    }

    return changes;
  }

  Future<void> applyServerChanges(List<dynamic> changes) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var change in changes) {
        if (change['type'] == 'update') {
          await txn.update(
            'notes',
            change['data'],
            where: 'id = ?',
            whereArgs: [change['id']],
          );
        } else if (change['type'] == 'insert') {
          await txn.insert('notes', change['data']);
        } else if (change['type'] == 'delete') {
          await txn.delete(
            'notes',
            where: 'id = ?',
            whereArgs: [change['id']],
          );
        }
      }
    });
  }

  Future<void> initializeSharedDatabase(String databaseId) async {
    return await _safeDbOperation(() async {
      print('🔄 ИНИЦИАЛИЗАЦИЯ: Начало инициализации совместной базы данных: $databaseId');
      
      final db = await database;
      print('🔄 ИНИЦИАЛИЗАЦИЯ: Соединение с базой данных получено');
      
      // Проверяем существующие записи с обработкой ошибок
      try {
        print('🔄 ИНИЦИАЛИЗАЦИЯ: Проверка существующих записей для базы $databaseId');
        final existing = await db.query(
          'shared_databases',
          where: 'server_id = ?',
          whereArgs: [databaseId],
          limit: 1,
        );

        if (existing.isEmpty) {
          print('🔄 ИНИЦИАЛИЗАЦИЯ: База $databaseId не найдена, создаем новую запись');
          // Создаем запись с обработкой уникальных ограничений
          try {
            await db.insert('shared_databases', {
              'server_id': databaseId,
              'name': 'Shared Database $databaseId',
              'owner_id': '',
              'created_at': DateTime.now().toIso8601String(),
              'collaborators': '{}',
              'database_path': 'shared_$databaseId.db',
              'is_owner': 0,
              'last_sync': DateTime.now().toIso8601String(),
            });
            print('✅ ИНИЦИАЛИЗАЦИЯ: Создана запись в таблице shared_databases для базы $databaseId');
          } catch (insertError) {
            if (insertError.toString().contains('UNIQUE constraint failed')) {
              print('⚠️ ИНИЦИАЛИЗАЦИЯ: База $databaseId уже существует (конфликт уникальности)');
            } else {
              print('❌ ИНИЦИАЛИЗАЦИЯ: Ошибка создания записи для базы $databaseId: $insertError');
            }
          }
        } else {
          print('✅ ИНИЦИАЛИЗАЦИЯ: База $databaseId уже существует в таблице shared_databases');
        }
        
        // Проверяем наличие данных с ограничением количества запросов
        print('🔄 ИНИЦИАЛИЗАЦИЯ: Проверка наличия данных в базе $databaseId');
        final notesResult = await db.query(
          'notes',
          where: 'database_id = ?',
          whereArgs: [databaseId],
          limit: 1,
        );
        
        // Создаем базовую структуру только если база полностью пустая
        if (notesResult.isEmpty) {
          print('🔄 ИНИЦИАЛИЗАЦИЯ: Заметки не найдены, проверяем папки');
          final foldersResult = await db.query(
            'folders',
            where: 'database_id = ?',
            whereArgs: [databaseId],
            limit: 1,
          );
          
          if (foldersResult.isEmpty) {
            print('🔄 ИНИЦИАЛИЗАЦИЯ: Папки не найдены, создаем минимальную структуру для базы $databaseId');
            
            // Используем транзакцию для атомарности операций
            await db.transaction((txn) async {
              try {
                final folderId = await txn.insert('folders', {
                  'name': 'Общие заметки',
                  'color': 0xFF4CAF50,
                  'is_expanded': 1,
                  'database_id': databaseId,
                });
                
                await txn.insert('notes', {
                  'title': 'Совместная работа',
                  'content': 'Это заметка для совместной работы. Она будет синхронизироваться с другими участниками.',
                  'folder_id': folderId,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'database_id': databaseId,
                });
                
                print('✅ ИНИЦИАЛИЗАЦИЯ: Базовая структура создана для базы $databaseId');
              } catch (e) {
                print('❌ ИНИЦИАЛИЗАЦИЯ: Ошибка создания базовой структуры: $e');
                // Не критично, продолжаем
              }
            });
          } else {
            print('✅ ИНИЦИАЛИЗАЦИЯ: Папки уже существуют в базе $databaseId');
          }
        } else {
          print('✅ ИНИЦИАЛИЗАЦИЯ: База $databaseId уже содержит данные');
        }
        
        // Обновляем время синхронизации с обработкой ошибок
        print('🔄 ИНИЦИАЛИЗАЦИЯ: Обновление времени синхронизации для базы $databaseId');
        try {
          await db.update(
            'shared_databases',
            {'last_sync': DateTime.now().toIso8601String()},
            where: 'server_id = ?',
            whereArgs: [databaseId],
          );
          print('✅ ИНИЦИАЛИЗАЦИЯ: Время синхронизации обновлено для базы $databaseId');
        } catch (updateError) {
          print('❌ ИНИЦИАЛИЗАЦИЯ: Ошибка обновления времени синхронизации: $updateError');
        }
        
        print('🎉 ИНИЦИАЛИЗАЦИЯ: Инициализация базы $databaseId завершена успешно');
        
      } catch (e) {
        print('❌ ИНИЦИАЛИЗАЦИЯ: Ошибка при работе с базой данных во время инициализации: $e');
        throw e;
      }
      
      // Асинхронное уведомление без блокировки
      print('🔄 ИНИЦИАЛИЗАЦИЯ: Отправка уведомления об изменении базы данных');
      Future.microtask(() {
        try {
          _notifyDatabaseChanged();
          print('✅ ИНИЦИАЛИЗАЦИЯ: Уведомление об изменении базы данных отправлено');
        } catch (e) {
          print('❌ ИНИЦИАЛИЗАЦИЯ: Ошибка при уведомлении об изменении базы данных: $e');
        }
      });
    });
  }

  Future<void> saveExportData(String databaseId, Map<String, dynamic> exportData) async {
    try {
      final db = await database;
      final safeDatabaseId = databaseId.replaceAll('-', '_');
      
      print('Сохранение экспортированных данных для базы $databaseId:');
      print('  Заметок: ${exportData['notes']?.length ?? 0}');
      print('  Папок: ${exportData['folders']?.length ?? 0}');
      print('  Изображений: ${(exportData['images']?.length ?? 0) + (exportData['note_images']?.length ?? 0)}');
      
      // Сохраняем данные в соответствующие таблицы
      if (exportData.containsKey('notes')) {
        for (final note in exportData['notes']) {
          await db.insert('shared_notes_$safeDatabaseId', note);
        }
      }
      
      if (exportData.containsKey('folders')) {
        for (final folder in exportData['folders']) {
          await db.insert('shared_folders_$safeDatabaseId', folder);
        }
      }
      
      if (exportData.containsKey('schedule_entries')) {
        for (final entry in exportData['schedule_entries']) {
          await db.insert('shared_schedule_entries_$safeDatabaseId', entry);
        }
      }
      
      if (exportData.containsKey('pinboard_notes')) {
        for (final note in exportData['pinboard_notes']) {
          await db.insert('shared_pinboard_notes_$safeDatabaseId', note);
        }
      }
      
      if (exportData.containsKey('connections')) {
        for (final connection in exportData['connections']) {
          await db.insert('shared_connections_$safeDatabaseId', connection);
        }
      }
      
      // Обработка изображений с поддержкой разных ключей (для обратной совместимости)
      int importedImages = 0;
      
      // Проверяем ключ 'note_images' (старый формат)
      if (exportData.containsKey('note_images')) {
        for (final image in exportData['note_images']) {
          await db.insert('shared_note_images_$safeDatabaseId', image);
          importedImages++;
        }
      }
      
      // Проверяем ключ 'images' (новый формат)
      if (exportData.containsKey('images')) {
        for (final image in exportData['images']) {
          await db.insert('shared_note_images_$safeDatabaseId', image);
          importedImages++;
        }
      }
      
      print('Импортировано $importedImages изображений для базы $databaseId');
      
      // Обновляем время последней синхронизации
      await db.update(
        'shared_databases',
        {'last_sync': DateTime.now().toIso8601String()},
        where: 'server_id = ?',
        whereArgs: [databaseId],
      );
    } catch (e) {
      print('Ошибка при сохранении экспортированных данных: $e');
      rethrow;
    }
  }

  Future<void> deleteDatabase() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final appDir = Directory(p.dirname(exePath));
      final dbDir = Directory(p.join(appDir.path, 'database'));
      final path = p.join(dbDir.path, _dbName);
      
      // Создаем резервную копию перед удалением
      if (await File(path).exists()) {
        // Создаем директорию для резервных копий, если она не существует
        final backupDir = Directory(p.join(dbDir.path, 'backups'));
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        
        // Формируем имя файла резервной копии с текущей датой и временем
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
        final backupPath = p.join(backupDir.path, 'notes_backup_$timestamp.db');
        
        // Копируем файл базы данных в резервную копию
        await File(path).copy(backupPath);
        print('Резервная копия создана: $backupPath');
        
        // Теперь можно удалить базу данных
        await File(path).delete();
      }
      
      _database = null;
    } catch (e) {
      print('Ошибка при удалении базы данных: $e');
      rethrow;
    }
  }

  // Метод для закрытия текущего подключения к базе данных
  Future<void> closeDatabase() async {
    if (_database != null && !_isClosed) {
      try {
        _isChangingDatabase = true;
        await _database!.close();
        _database = null;
        _isClosed = true;
        print('База данных успешно закрыта');
      } catch (e) {
        print('Ошибка при закрытии базы данных: $e');
        rethrow;
      } finally {
        // Даже в случае ошибки изменяем флаг, чтобы другие операции знали, что база не доступна
        _isChangingDatabase = false;
      }
    }
  }
  
  // Метод для переинициализации базы данных после закрытия
  Future<void> reopenDatabase() async {
    if (_isClosed || _database == null) {
      try {
        _isChangingDatabase = true;
        _database = await _initDatabase();
        _isClosed = false;
        print('База данных успешно открыта заново');
      } catch (e) {
        print('Ошибка при повторном открытии базы данных: $e');
        rethrow;
      } finally {
        _isChangingDatabase = false;
      }
    }
  }
  
  // Метод для поиска изображений по имени файла во всех базах данных
  Future<Uint8List?> findImageInAllDatabases(String fileName) async {
    try {
      final db = await database;
      
      print('Поиск изображения $fileName во всех базах данных');
      
      // Сначала ищем в основной таблице note_images
      final List<Map<String, dynamic>> result = await db.query(
        'note_images',
        where: 'file_name = ?',
        whereArgs: [fileName],
      );
      
      if (result.isNotEmpty) {
        print('Изображение $fileName найдено в основной базе данных');
        return result.first['image_data'] as Uint8List?;
      }
      
      // Если не найдено, получаем все записи из таблицы shared_databases
      final sharedDatabases = await db.query('shared_databases');
      
      // Проходим по всем базам данных
      for (final sharedDb in sharedDatabases) {
        final dbId = sharedDb['server_id'] as String;
        final safeDatabaseId = dbId.replaceAll('-', '_');
        
        // Проверяем, существует ли таблица для этой базы
        final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='shared_note_images_$safeDatabaseId'"
        );
        
        if (tableCheck.isNotEmpty) {
          // Ищем изображение в этой базе
          try {
            final images = await db.query(
              'shared_note_images_$safeDatabaseId',
              where: 'file_name = ?',
              whereArgs: [fileName],
            );
            
            if (images.isNotEmpty) {
              print('Изображение $fileName найдено в базе $dbId');
              return images.first['image_data'] as Uint8List?;
            }
          } catch (e) {
            print('Ошибка при поиске в shared_note_images_$safeDatabaseId: $e');
          }
        }
      }
      
      // Если изображение не найдено нигде
      print('Изображение $fileName не найдено ни в одной базе данных');
      return null;
    } catch (e) {
      print('Ошибка при поиске изображения во всех базах: $e');
      return null;
    }
  }
  
  // Метод для очистки кешированных данных (не влияет на базу данных)
  Future<void> clearCache() async {
    try {
      print('Очистка кешированных данных DatabaseHelper');
      
      // ИСПРАВЛЕНИЕ: Реальная очистка кешированных данных
      // Закрываем текущее соединение с базой данных
      if (_database != null && !_isClosed) {
        await _database!.close();
        _database = null;
        _isClosed = true;
        print('Соединение с базой данных закрыто для очистки кеша');
      }
      
      // Сбрасываем флаги состояния
      _isChangingDatabase = false;
      _isClosed = false;
      
      print('Кеш успешно очищен');
    } catch (e) {
      print('Ошибка при очистке кеша: $e');
      // Не выбрасываем ошибку, так как это не критично
    }
  }
} 
