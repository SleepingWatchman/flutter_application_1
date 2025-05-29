import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/schedule_entry.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'dart:typed_data';
import 'package:flutter_application_1/models/note_image.dart';
import 'package:flutter_application_1/models/backup_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/database_provider.dart';
import '../models/shared_database.dart';
import 'dart:async';

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
  static const int _dbVersion = 5;
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
        
        // Если после ожидания база все еще в процессе переключения, отменяем операцию
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
        return await operation();
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
          
          // Повторяем операцию
          return await operation();
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
        database_id TEXT
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

    // Таблица расписания с колонками created_at и updated_at
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
        updated_at TEXT
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
      // Создаем таблицу для изображений, если её нет
      await _createImagesTable(db);
      
      // Создаем таблицу для совместных баз данных
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shared_databases (
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
    
    if (oldVersion < 3) {
      // Добавляем колонку recurrence_json в таблицу schedule_entries
      try {
        await db.execute('ALTER TABLE schedule_entries ADD COLUMN recurrence_json TEXT');
        print('Успешно добавлена колонка recurrence_json в таблицу schedule_entries');
      } catch (e) {
        print('Ошибка при добавлении колонки recurrence_json: $e');
      }
    }
    
    // Добавляем отсутствующие колонки для версии 4
    if (oldVersion < 4) {
      // Добавляем created_at и updated_at в schedule_entries
      try {
        await db.execute('ALTER TABLE schedule_entries ADD COLUMN created_at TEXT');
        print('Успешно добавлена колонка created_at в таблицу schedule_entries');
      } catch (e) {
        print('Колонка created_at уже существует или ошибка: $e');
      }
      
      try {
        await db.execute('ALTER TABLE schedule_entries ADD COLUMN updated_at TEXT');
        print('Успешно добавлена колонка updated_at в таблицу schedule_entries');
      } catch (e) {
        print('Колонка updated_at уже существует или ошибка: $e');
      }
      
      // Добавляем database_id в note_images
      try {
        await db.execute('ALTER TABLE note_images ADD COLUMN database_id TEXT');
        print('Успешно добавлена колонка database_id в таблицу note_images');
      } catch (e) {
        print('Колонка database_id уже существует или ошибка: $e');
      }
    }
    
    // Новая миграция для версии 5 - добавление уникального ограничения
    if (oldVersion < 5) {
      // Миграция для добавления уникального ограничения к таблице note_images
      print('Применение миграции базы данных: очистка дублирующихся изображений');
      
      // Сначала очищаем дублирующиеся изображения
      await _cleanupDuplicateImages(db);
      
      // Создаем новую таблицу с уникальным ограничением
      await db.execute('''
        CREATE TABLE note_images_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          note_id INTEGER NOT NULL,
          file_name TEXT NOT NULL,
          image_data BLOB NOT NULL,
          database_id TEXT,
          FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE,
          UNIQUE(note_id, file_name)
        )
      ''');
      
      // Копируем уникальные данные в новую таблицу
      await db.execute('''
        INSERT INTO note_images_new (note_id, file_name, image_data, database_id)
        SELECT note_id, file_name, image_data, database_id
        FROM note_images
        GROUP BY note_id, file_name
        HAVING MIN(id)
      ''');
      
      // Удаляем старую таблицу и переименовываем новую
      await db.execute('DROP TABLE note_images');
      await db.execute('ALTER TABLE note_images_new RENAME TO note_images');
      
      print('Миграция завершена: добавлено уникальное ограничение для изображений');
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
    // Удаляем database_id из карты, если это локальная заметка
    if (note['database_id'] == null) {
      note.remove('database_id');
    }
    final id = await db.insert('notes', note);
    _notifyDatabaseChanged();
    return id;
  }

  // Методы для работы с расписанием
  Future<List<ScheduleEntry>> getScheduleEntries([String? databaseId]) async {
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
  }

  Future<int> insertScheduleEntry(Map<String, dynamic> entry, [Transaction? txn]) async {
    // Удаляем database_id из карты, если это локальная запись
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
      // Удаляем database_id из карты, если это локальная запись
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
  }

  Future<int> insertPinboardNote(Map<String, dynamic> note, [Transaction? txn]) async {
    // Удаляем database_id из карты, если это локальная заметка
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
        final db = await database;
        
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
        
        // Если передана транзакция, используем её, иначе создаем новую
        if (transaction != null) {
          await _performTableClear(transaction, databaseId);
        } else {
          await db.transaction((txn) async {
            await _performTableClear(txn, databaseId);
          });
        }
        
        print('Очищены таблицы для базы $databaseId');
      } catch (e) {
        print('Ошибка при очистке таблиц для базы $databaseId: $e');
        // Не выбрасываем исключение, чтобы не прерывать работу приложения
      }
    });
  }
  
  /// Вспомогательный метод для выполнения очистки таблиц в транзакции
  Future<void> _performTableClear(Transaction txn, String databaseId) async {
    // Сначала удаляем изображения к заметкам этой базы данных
    final notesWithImages = await txn.query(
      'notes', 
      columns: ['id'],
      where: 'database_id = ?',
      whereArgs: [databaseId],
    );
    
    final noteIds = notesWithImages.map((note) => note['id'] as int).toList();
    if (noteIds.isNotEmpty) {
      await txn.delete(
        'note_images',
        where: 'note_id IN (${List.filled(noteIds.length, '?').join(',')})',
        whereArgs: noteIds,
      );
    }
    
    // Удаляем данные из таблиц в определенном порядке, 
    // чтобы избежать проблем с внешними ключами
    await txn.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('schedule_entries', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('folders', where: 'database_id = ?', whereArgs: [databaseId]);
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
    // Удаляем database_id из карты, если это локальная заметка
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
  Future<List<Map<String, dynamic>>> getImagesForNote(int id) async {
    final db = await database;
    return await db.query(
      'note_images',
      where: 'note_id = ?',
      whereArgs: [id],
    );
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
    try {
      if (txn != null) {
        await txn.insert('folders', folder);
      } else {
        final db = await database;
        await db.insert('folders', folder);
      }
    } catch (e) {
      // Обрабатываем ошибки уникальных ограничений
      if (e.toString().contains('UNIQUE constraint failed') || 
          e.toString().contains('UNIQUE') ||
          e.toString().contains('PRIMARY KEY')) {
        print('Конфликт уникальности при вставке папки: ${folder['name']}, пытаемся обновить');
        
        try {
          // Пытаемся обновить существующую запись
          if (folder['id'] != null) {
            if (txn != null) {
              await txn.update(
                'folders',
                folder,
                where: 'id = ?',
                whereArgs: [folder['id']],
              );
            } else {
              final db = await database;
              await db.update(
                'folders',
                folder,
                where: 'id = ?',
                whereArgs: [folder['id']],
              );
            }
            print('Папка успешно обновлена: ${folder['name']}');
          } else {
            print('Пропускаем папку без ID: ${folder['name']}');
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
    final preparedNote = BackupData.prepareForSqlite(note);
    
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
      } else {
        print('Ошибка при вставке заметки: $e');
        rethrow;
      }
    }
  }

  Future<void> insertScheduleEntryForBackup(Map<String, dynamic> entry, [Transaction? txn]) async {
    final preparedEntry = BackupData.prepareForSqlite(entry);
    
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
          (id, time, date, note, dynamic_fields_json, recurrence_json, database_id, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          preparedEntry['id'],
          preparedEntry['time'],
          preparedEntry['date'],
          preparedEntry['note'],
          preparedEntry['dynamic_fields_json'],
          preparedEntry['recurrence_json'],
          preparedEntry['database_id'],
          preparedEntry['created_at'],
          preparedEntry['updated_at'],
        ]);
      } else {
        final db = await database;
        await db.rawInsert('''
          INSERT OR REPLACE INTO schedule_entries 
          (id, time, date, note, dynamic_fields_json, recurrence_json, database_id, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          preparedEntry['id'],
          preparedEntry['time'],
          preparedEntry['date'],
          preparedEntry['note'],
          preparedEntry['dynamic_fields_json'],
          preparedEntry['recurrence_json'],
          preparedEntry['database_id'],
          preparedEntry['created_at'],
          preparedEntry['updated_at'],
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
    final preparedNote = BackupData.prepareForSqlite(note);
    
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
    final preparedConnection = BackupData.prepareForSqlite(connection);
    
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

  Future<void> insertImageForBackup(int noteId, String fileName, Uint8List imageData, [Transaction? txn]) async {
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
      print('Ошибка при вставке изображения $fileName для заметки $noteId при восстановлении: $e');
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
          txn
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
    final folders = await getFoldersForDatabase(databaseId);
    final notes = await getNotesForDatabase(databaseId);
    final scheduleEntries = await getScheduleEntriesForDatabase(databaseId);
    final pinboardNotes = await getPinboardNotesForDatabase(databaseId);
    final connections = await getConnectionsForDatabase(databaseId);
    
    print('Создание резервной копии для базы ${databaseId ?? "локальной"}:');
    print('  Папок: ${folders.length}');
    print('  Заметок: ${notes.length}');
    
    // Изображения нужно фильтровать по ID заметок из текущей базы
    List<Map<String, dynamic>> images = [];
    if (notes.isNotEmpty) {
      // Получаем ID всех заметок
      final noteIds = notes
          .where((note) => note['id'] != null)
          .map((note) => note['id'].toString())
          .toList();
      
      if (noteIds.isNotEmpty) {
        final db = await database;
        // Создаем строку с плейсхолдерами для запроса IN (?, ?, ...)
        final placeholders = List.filled(noteIds.length, '?').join(',');
        images = await db.query(
          'note_images',
          where: 'note_id IN ($placeholders)',
          whereArgs: noteIds,
        );
        
        print('  Заметок с изображениями: ${images.map((img) => img['note_id']).toSet().length}');
        print('  Всего изображений: ${images.length}');
        
        // Проверяем структуру нескольких изображений для диагностики
        if (images.isNotEmpty) {
          print('  Примеры изображений:');
          for (int i = 0; i < math.min(3, images.length); i++) {
            final image = images[i];
            final imageData = image['image_data'] as Uint8List?;
            print('    Изображение $i: note_id=${image['note_id']}, ' +
                  'file_name=${image['file_name']}, ' +
                  'размер=${imageData?.length ?? 0} байт');
          }
        }
      }
    }

    return BackupData(
      folders: folders,
      notes: notes,
      scheduleEntries: scheduleEntries,
      pinboardNotes: pinboardNotes,
      connections: connections,
      noteImages: images,
      databaseId: databaseId,
    );
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
                    txn
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

  Future<void> importDatabase(String databaseId, Map<String, dynamic> data) async {
    return await _safeDbOperation(() async {
      print('Импорт данных для базы данных $databaseId');
      
      final db = await database;
      
      try {
        await db.transaction((txn) async {
          // Очищаем существующие данные для этой базы
          await clearDatabaseTables(databaseId, txn);
    
          int foldersCount = 0;
          int notesCount = 0;
          int scheduleCount = 0;
          int pinboardCount = 0;
          int connectionsCount = 0;
          int imagesCount = 0;
          
          // Импортируем папки с обработкой ошибок
          if (data['folders'] != null && data['folders'] is List) {
            print('Импорт папок: ${data['folders'].length}');
            for (var folder in (data['folders'] as List)) {
              try {
                folder['database_id'] = databaseId;
                await insertFolderForBackup(folder, txn);
                foldersCount++;
              } catch (e) {
                print('Ошибка при импорте папки: $e');
              }
            }
          }
    
          // Импортируем заметки с обработкой ошибок
          if (data['notes'] != null && data['notes'] is List) {
            print('Импорт заметок: ${data['notes'].length}');
            for (var note in (data['notes'] as List)) {
              try {
                note['database_id'] = databaseId;
                await insertNoteForBackup(note, txn);
                notesCount++;
              } catch (e) {
                print('Ошибка при импорте заметки: $e');
              }
            }
          }
    
          // Импортируем записи расписания с обработкой ошибок
          if (data['schedule_entries'] != null && data['schedule_entries'] is List) {
            print('Импорт записей расписания: ${data['schedule_entries'].length}');
            for (var entry in (data['schedule_entries'] as List)) {
              try {
                entry['database_id'] = databaseId;
                await insertScheduleEntryForBackup(entry, txn);
                scheduleCount++;
              } catch (e) {
                print('Ошибка при импорте записи расписания: $e');
              }
            }
          }
    
          // Импортируем заметки на доске с обработкой ошибок
          if (data['pinboard_notes'] != null && data['pinboard_notes'] is List) {
            print('Импорт заметок на доске: ${data['pinboard_notes'].length}');
            for (var note in (data['pinboard_notes'] as List)) {
              try {
                note['database_id'] = databaseId;
                await insertPinboardNoteForBackup(note, txn);
                pinboardCount++;
              } catch (e) {
                print('Ошибка при импорте заметки на доске: $e');
              }
            }
          }
    
          // Импортируем соединения с обработкой ошибок
          if (data['connections'] != null && data['connections'] is List) {
            print('Импорт соединений: ${data['connections'].length}');
            for (var connection in (data['connections'] as List)) {
              try {
                connection['database_id'] = databaseId;
                await insertConnectionForBackup(connection, txn);
                connectionsCount++;
              } catch (e) {
                print('Ошибка при импорте соединения: $e');
              }
            }
          }
          
          // Импортируем изображения с обработкой ошибок
          if (data['note_images'] != null && data['note_images'] is List) {
            print('Импорт изображений: ${data['note_images'].length}');
            for (var image in (data['note_images'] as List)) {
              try {
                await insertImageForBackup(
                  image['note_id'],
                  image['file_name'],
                  image['image_data'] is Uint8List 
                    ? image['image_data'] 
                    : Uint8List.fromList(List<int>.from(image['image_data'])),
                  txn
                );
                imagesCount++;
              } catch (e) {
                print('Ошибка при импорте изображения: $e');
              }
            }
          }
          
          print('Импортировано: папок - $foldersCount, заметок - $notesCount, ' +
                'записей расписания - $scheduleCount, заметок на доске - $pinboardCount, ' +
                'соединений - $connectionsCount, изображений - $imagesCount');
          
          // Если данных нет, создаем базовую структуру
          if (foldersCount == 0 && notesCount == 0) {
            print('Создание базовой структуры для пустой базы $databaseId');
            
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
              
              print('Базовая структура создана успешно');
            } catch (e) {
              print('Ошибка при создании базовой структуры: $e');
            }
          }
        });
        
        print('Импорт данных для базы $databaseId завершен успешно');
        
        // Уведомляем об изменении базы данных
        Future.microtask(() {
          try {
            _notifyDatabaseChanged();
          } catch (e) {
            print('Ошибка при уведомлении об изменении базы данных: $e');
          }
        });
        
      } catch (e) {
        print('Критическая ошибка при импорте данных: $e');
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
        updated_at TEXT
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
      print('Инициализация совместной базы данных: $databaseId');
      
      final db = await database;
      
      // Проверяем существующие записи с обработкой ошибок
      try {
        final existing = await db.query(
          'shared_databases',
          where: 'server_id = ?',
          whereArgs: [databaseId],
          limit: 1,
        );

        if (existing.isEmpty) {
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
            print('Создана запись в таблице shared_databases для базы $databaseId');
          } catch (insertError) {
            if (insertError.toString().contains('UNIQUE constraint failed')) {
              print('База $databaseId уже существует (конфликт уникальности)');
            } else {
              print('Ошибка создания записи для базы $databaseId: $insertError');
            }
          }
        } else {
          print('База $databaseId уже существует в таблице shared_databases');
        }

        // Проверяем наличие данных с ограничением количества запросов
        final notesResult = await db.query(
          'notes',
          where: 'database_id = ?',
          whereArgs: [databaseId],
          limit: 1,
        );
        
        // Создаем базовую структуру только если база полностью пустая
        if (notesResult.isEmpty) {
          final foldersResult = await db.query(
            'folders',
            where: 'database_id = ?',
            whereArgs: [databaseId],
            limit: 1,
          );
          
          if (foldersResult.isEmpty) {
            print('Создание минимальной структуры для пустой базы $databaseId');
            
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
                
                print('Базовая структура создана для базы $databaseId');
              } catch (e) {
                print('Ошибка создания базовой структуры: $e');
                // Не критично, продолжаем
              }
            });
          }
        } else {
          print('База $databaseId уже содержит данные');
        }
        
        // Обновляем время синхронизации с обработкой ошибок
        try {
          await db.update(
            'shared_databases',
            {'last_sync': DateTime.now().toIso8601String()},
            where: 'server_id = ?',
            whereArgs: [databaseId],
          );
        } catch (updateError) {
          print('Ошибка обновления времени синхронизации: $updateError');
        }
        
        print('Инициализация базы $databaseId завершена успешно');
        
      } catch (e) {
        print('Ошибка при работе с базой данных во время инициализации: $e');
        throw e;
      }
      
      // Асинхронное уведомление без блокировки
      Future.microtask(() {
        try {
          _notifyDatabaseChanged();
        } catch (e) {
          print('Ошибка при уведомлении об изменении базы данных: $e');
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
      // В текущей реализации кеширование данных минимально
      // Этот метод может быть расширен, если добавится кеширование
      print('Кеш успешно очищен');
    } catch (e) {
      print('Ошибка при очистке кеша: $e');
      // Не выбрасываем ошибку, так как это не критично
    }
  }
} 