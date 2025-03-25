import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../models/note.dart';
import '../models/folder.dart';
import '../models/schedule_entry.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';

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
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Таблица заметок
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        folder TEXT
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
        posX REAL,
        posY REAL,
        backgroundColor INTEGER,
        icon TEXT
      )
    ''');

    // Таблица соединений заметок
    await db.execute('''
      CREATE TABLE connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fromId INTEGER,
        toId INTEGER,
        name TEXT,
        connectionColor INTEGER
      )
    ''');

    // Таблица папок
    await db.execute('''
      CREATE TABLE folders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        backgroundColor INTEGER
      )
    ''');
  }

  // Методы для работы с заметками
  Future<int> insertNote(Note note) async {
    final db = await database;
    return await db.insert('notes', note.toMap());
  }

  Future<List<Note>> getNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  Future<int> updateNote(Note note) async {
    final db = await database;
    return await db
        .update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
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
    return await db.insert('pinboard_notes', note.toMap());
  }

  Future<List<PinboardNoteDB>> getPinboardNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pinboard_notes');
    return List.generate(maps.length, (i) => PinboardNoteDB.fromMap(maps[i]));
  }

  Future<int> updatePinboardNote(PinboardNoteDB note) async {
    final db = await database;
    return await db.update('pinboard_notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> deletePinboardNote(int id) async {
    final db = await database;
    return await db.delete('pinboard_notes', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с соединениями заметок
  Future<int> insertConnection(ConnectionDB connection) async {
    final db = await database;
    return await db.insert('connections', connection.toMap());
  }

  Future<int> updateConnection(ConnectionDB connection) async {
    final db = await database;
    return await db.update(
      'connections',
      connection.toMap(),
      where: 'id = ?',
      whereArgs: [connection.id],
    );
  }

  Future<List<ConnectionDB>> getConnections() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('connections');
    return List.generate(maps.length, (i) => ConnectionDB.fromMap(maps[i]));
  }

  Future<int> deleteConnection(int id) async {
    final db = await database;
    return await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с папками
  Future<int> insertFolder(Folder folder) async {
    final db = await database;
    return await db.insert('folders', folder.toMap());
  }

  Future<List<Folder>> getFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('folders');
    return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
  }

  Future<int> updateFolder(Folder folder) async {
    final db = await database;
    return await db.update('folders', folder.toMap(),
        where: 'id = ?', whereArgs: [folder.id]);
  }

  Future<int> deleteFolder(int id) async {
    final db = await database;
    return await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }
} 