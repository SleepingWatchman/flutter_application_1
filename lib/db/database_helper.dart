import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/schedule_entry.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import 'dart:convert';

/// Класс для работы с базой данных, реализующий CRUD-операции для всех сущностей.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, 'notes_app.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Создаем таблицу папок
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        is_expanded INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Создаем таблицу заметок
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT,
        folder_id INTEGER,
        created_at INTEGER,
        updated_at INTEGER,
        images TEXT,
        metadata TEXT,
        content_json TEXT,
        FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
      )
    ''');

    // Таблица расписания
    await db.execute('''
      CREATE TABLE schedule(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT,
        date TEXT,
        note TEXT,
        dynamicFields TEXT
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
        icon INTEGER
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
        FOREIGN KEY (from_note_id) REFERENCES pinboard_notes (id),
        FOREIGN KEY (to_note_id) REFERENCES pinboard_notes (id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Добавляем новые колонки для версии 2
      await db.execute('ALTER TABLE notes ADD COLUMN images TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN metadata TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN content_json TEXT');
    }
  }

  // Методы для работы с заметками
  Future<int> insertNote(Note note) async {
    final db = await database;
    try {
      final Map<String, dynamic> data = {
        'title': note.title,
        'content': note.content,
        'folder_id': note.folderId,
        'created_at': note.createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
        'updated_at': note.updatedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
      };
      return await db.insert('notes', data);
    } catch (e) {
      print('Ошибка при создании заметки: $e');
      rethrow;
    }
  }

  Future<List<Note>> getAllNotes() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query('notes');
      return List.generate(maps.length, (i) {
        // Создаем заметку из основных полей
        return Note(
          id: maps[i]['id'],
          title: maps[i]['title'] ?? 'Без названия',
          content: maps[i]['content'],
          folderId: maps[i]['folder_id'],
          createdAt: maps[i]['created_at'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(maps[i]['created_at'])
              : null,
          updatedAt: maps[i]['updated_at'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(maps[i]['updated_at'])
              : null,
        );
      });
    } catch (e) {
      print('Ошибка при получении заметок: $e');
      return [];
    }
  }

  Future<void> updateNote(Note note) async {
    final db = await database;
    try {
      await db.update(
        'notes',
        {
          'title': note.title,
          'content': note.content,
          'folder_id': note.folderId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [note.id],
      );
    } catch (e) {
      print('Ошибка при обновлении заметки: $e');
      rethrow;
    }
  }

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Методы для работы с папками
  Future<List<Folder>> getFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('folders');
    return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
  }

  Future<int> insertFolder(Folder folder) async {
    final db = await database;
    return await db.insert('folders', folder.toMap());
  }

  Future<void> updateFolder(Folder folder) async {
    final db = await database;
    await db.update(
      'folders',
      folder.toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  Future<void> deleteFolder(int id) async {
    final db = await database;
    await db.delete(
      'folders',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Note>> getNotesByFolder(int folderId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
    return List.generate(maps.length, (i) {
      final noteJson = maps[i]['content_json'];
      final note = Note.fromJson(noteJson);
      note.id = maps[i]['id']; // Восстанавливаем ID из основной таблицы
      return note;
    });
  }

  // Методы для работы с расписанием
  Future<int> insertScheduleEntry(ScheduleEntry entry) async {
    final db = await database;
    return await db.insert('schedule', entry.toMap());
  }

  Future<List<ScheduleEntry>> getScheduleEntries(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('schedule', where: 'date = ?', whereArgs: [date]);
    return List.generate(maps.length, (i) => ScheduleEntry.fromMap(maps[i]));
  }

  Future<int> updateScheduleEntry(ScheduleEntry entry) async {
    final db = await database;
    return await db.update('schedule', entry.toMap(),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<int> deleteScheduleEntry(int id) async {
    final db = await database;
    return await db.delete('schedule', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с заметками на доске
  Future<int> insertPinboardNote(PinboardNoteDB note) async {
    final db = await database;
    try {
      final id = await db.insert('pinboard_notes', note.toMap());
      return id;
    } catch (e) {
      print('Ошибка при вставке заметки в базу данных: $e');
      rethrow;
    }
  }

  Future<List<PinboardNoteDB>> getPinboardNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pinboard_notes');
    return List.generate(maps.length, (i) => PinboardNoteDB.fromMap(maps[i]));
  }

  Future<void> updatePinboardNote(PinboardNoteDB note) async {
    final db = await database;
    await db.update(
      'pinboard_notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deletePinboardNote(int id) async {
    final db = await database;
    await db.delete(
      'pinboard_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Методы для работы с соединениями
  Future<int> insertConnection(ConnectionDB connection) async {
    final db = await database;
    return await db.insert('connections', connection.toMap());
  }

  Future<List<ConnectionDB>> getConnections() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('connections');
    return List.generate(maps.length, (i) => ConnectionDB.fromMap(maps[i]));
  }

  Future<void> updateConnection(ConnectionDB connection) async {
    final db = await database;
    await db.update(
      'connections',
      connection.toMap(),
      where: 'id = ?',
      whereArgs: [connection.id],
    );
  }

  Future<void> deleteConnection(int id) async {
    final db = await database;
    await db.delete(
      'connections',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Folder>> getAllFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('folders');
    return List.generate(maps.length, (i) {
      return Folder.fromMap(maps[i]);
    });
  }

  static Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'notes_app.db');
    await databaseFactoryFfi.deleteDatabase(path);
  }
} 