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
import 'package:sqflite/sqflite.dart';
import 'dart:typed_data';
import 'package:flutter_application_1/models/note_image.dart';
import 'package:flutter_application_1/models/backup_data.dart';

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
    try {
      // Получаем путь к исполняемому файлу приложения
      final exePath = Platform.resolvedExecutable;
      final appDir = Directory(p.dirname(exePath));
      final dbDir = Directory(p.join(appDir.path, 'database'));
      
      // Создаем директорию для базы данных, если она не существует
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      
      final path = p.join(dbDir.path, 'notes_app.db');
      
      // Открываем базу данных
      return await openDatabase(
        path,
        version: 3,
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
        is_expanded INTEGER NOT NULL DEFAULT 1
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
        FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
      )
    ''');

    // Таблица расписания
    await db.execute('''
      CREATE TABLE schedule_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT,
        date TEXT,
        note TEXT,
        dynamic_fields_json TEXT
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

    await _createImagesTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Создаем таблицу для изображений, если её нет
      await _createImagesTable(db);
    }
  }

  Future<void> _createImagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        image_data BLOB NOT NULL,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');
  }

  // Методы для работы с папками
  Future<List<Folder>> getFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('folders');
    return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
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
  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
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
      return note.copyWith(id: maps[i]['id']);
    });
  }

  Future<int> insertNote(Map<String, dynamic> note, [Transaction? txn]) async {
    if (txn != null) {
      return await txn.insert('notes', note);
    }
    final db = await database;
    return await db.insert('notes', note);
  }

  // Методы для работы с расписанием
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('schedule_entries');
    return List.generate(maps.length, (i) => ScheduleEntry.fromMap(maps[i]));
  }

  Future<int> insertScheduleEntry(Map<String, dynamic> entry, [Transaction? txn]) async {
    if (txn != null) {
      return await txn.insert('schedule_entries', entry);
    }
    final db = await database;
    return await db.insert('schedule_entries', entry);
  }

  // Методы для работы с заметками на доске
  Future<List<PinboardNoteDB>> getPinboardNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pinboard_notes');
    return List.generate(maps.length, (i) => PinboardNoteDB.fromMap(maps[i]));
  }

  Future<int> insertPinboardNote(Map<String, dynamic> note, [Transaction? txn]) async {
    if (txn != null) {
      return await txn.insert('pinboard_notes', note);
    }
    final db = await database;
    return await db.insert('pinboard_notes', note);
  }

  // Методы для работы с соединениями
  Future<List<ConnectionDB>> getConnectionsDB() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('connections');
    return List.generate(maps.length, (i) => ConnectionDB.fromMap(maps[i]));
  }

  Future<int> insertConnection(Map<String, dynamic> connection, [Transaction? txn]) async {
    if (txn != null) {
      return await txn.insert('connections', connection);
    }
    final db = await database;
    return await db.insert('connections', connection);
  }

  // Методы для работы с изображениями
  Future<List<NoteImage>> getAllImages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('note_images');
    return List.generate(maps.length, (i) => NoteImage.fromMap(maps[i]));
  }

  Future<void> insertImage(int noteId, String fileName, Uint8List imageData, [Transaction? txn]) async {
    final data = {
      'note_id': noteId,
      'file_name': fileName,
      'image_data': imageData,
    };
    
    if (txn != null) {
      await txn.insert('note_images', data);
    } else {
      final db = await database;
      await db.insert('note_images', data);
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

  Future<void> clearDatabaseTables(int databaseId, Transaction txn) async {
    await txn.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
  }

  Future<List<Map<String, dynamic>>> getNotesForDatabase() async {
    final db = await database;
    return await db.query('notes');
  }

  Future<List<Map<String, dynamic>>> getPinboardNotesForDatabase() async {
    final db = await database;
    return await db.query('pinboard_notes');
  }

  Future<List<Map<String, dynamic>>> getConnectionsForDatabase() async {
    final db = await database;
    return await db.query('connections');
  }

  Future<void> updateNote(Note note) async {
    if (note.id == null) return;
    
    final db = await database;
    await db.update(
      'notes',
      note.toMap(),
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
      final List<Map<String, dynamic>> result = await db.query(
        'note_images',
        where: 'file_name = ?',
        whereArgs: [imagePath.split('/').last],
      );
      
      if (result.isNotEmpty) {
        return result.first['image_data'] as Uint8List;
      }
      return null;
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

  Future<void> clearDatabaseTablesForBackup(int databaseId, Transaction txn) async {
    await txn.delete('notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('pinboard_notes', where: 'database_id = ?', whereArgs: [databaseId]);
    await txn.delete('connections', where: 'database_id = ?', whereArgs: [databaseId]);
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
    if (txn != null) {
      await txn.insert('folders', folder);
    } else {
      final db = await database;
      await db.insert('folders', folder);
    }
  }

  Future<void> insertNoteForBackup(Map<String, dynamic> note, [Transaction? txn]) async {
    final preparedNote = BackupData.prepareForSqlite(note);
    if (txn != null) {
      await txn.insert('notes', preparedNote);
    } else {
      final db = await database;
      await db.insert('notes', preparedNote);
    }
  }

  Future<void> insertScheduleEntryForBackup(Map<String, dynamic> entry, [Transaction? txn]) async {
    final preparedEntry = BackupData.prepareForSqlite(entry);
    if (txn != null) {
      await txn.insert('schedule_entries', preparedEntry);
    } else {
      final db = await database;
      await db.insert('schedule_entries', preparedEntry);
    }
  }

  Future<void> insertPinboardNoteForBackup(Map<String, dynamic> note, [Transaction? txn]) async {
    final preparedNote = BackupData.prepareForSqlite(note);
    if (txn != null) {
      await txn.insert('pinboard_notes', preparedNote);
    } else {
      final db = await database;
      await db.insert('pinboard_notes', preparedNote);
    }
  }

  Future<void> insertConnectionForBackup(Map<String, dynamic> connection, [Transaction? txn]) async {
    final preparedConnection = BackupData.prepareForSqlite(connection);
    if (txn != null) {
      await txn.insert('connections', preparedConnection);
    } else {
      final db = await database;
      await db.insert('connections', preparedConnection);
    }
  }

  Future<void> insertImageForBackup(int noteId, String fileName, Uint8List imageData, [Transaction? txn]) async {
    final data = {
      'note_id': noteId,
      'file_name': fileName,
      'image_data': imageData,
    };
    
    if (txn != null) {
      await txn.insert('note_images', data);
    } else {
      final db = await database;
      await db.insert('note_images', data);
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

  Future<void> updateScheduleEntry(ScheduleEntry entry) async {
    if (entry.id == null) return;
    
    final db = await database;
    await db.update(
      'schedule_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteScheduleEntry(int id) async {
    final db = await database;
    await db.delete(
      'schedule_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePinboardNote(PinboardNoteDB note) async {
    if (note.id == null) return;
    
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

  Future<void> deleteConnection(int id) async {
    final db = await database;
    await db.delete(
      'connections',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateConnection(Map<String, dynamic> connection) async {
    final db = await database;
    await db.update(
      'connections',
      connection,
      where: 'id = ?',
      whereArgs: [connection['id']],
    );
  }
} 