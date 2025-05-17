import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'collaboration_service.dart';
import '../models/shared_database.dart';
import '../db/database_helper.dart';
import '../models/backup_data.dart';
import 'auth_service.dart';

class AutoSyncService {
  static const Duration _syncInterval = Duration(minutes: 15);
  static const String _lastSyncKey = 'last_sync_time';
  
  final CollaborationService _collaborationService;
  final DatabaseHelper _dbHelper;
  Timer? _syncTimer;
  bool _isSyncing = false;
  String? _currentDatabaseId;

  AutoSyncService(this._collaborationService, this._dbHelper);

  Future<void> initialize() async {
    // Запуск периодической синхронизации
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) => syncIfNeeded());
  }

  Future<void> syncIfNeeded() async {
    if (_isSyncing || _currentDatabaseId == null) return;

    try {
      _isSyncing = true;
      
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTime = prefs.getInt('${_lastSyncKey}_${_currentDatabaseId}') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Проверяем, прошло ли достаточно времени с последней синхронизации
      if (now - lastSyncTime >= _syncInterval.inMilliseconds) {
        await _performSync();
        await prefs.setInt('${_lastSyncKey}_${_currentDatabaseId}', now);
      }
    } catch (e) {
      print('Ошибка автоматической синхронизации: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _performSync() async {
    try {
      if (_currentDatabaseId == null || _currentDatabaseId!.isEmpty) {
        print('Пропуск синхронизации: не указан ID базы данных');
        return;
      }

      // Создаем резервную копию текущего состояния
      final backupData = await _createBackupData();
      
      // Отправляем изменения на сервер
      await _collaborationService.saveDatabaseBackup(_currentDatabaseId!, backupData);
      
      // Загружаем последние изменения с сервера
      final latestBackup = await _collaborationService.getDatabaseBackup(_currentDatabaseId!);
      
      // Применяем изменения
      await _applyBackupData(latestBackup);

      // Обновляем время последней синхронизации в базе данных
      final db = await _dbHelper.database;
      await db.update(
        'shared_databases',
        {'last_sync': DateTime.now().toIso8601String()},
        where: 'server_id = ?',
        whereArgs: [_currentDatabaseId],
      );
    } catch (e) {
      print('Ошибка при выполнении синхронизации: $e');
    }
  }

  Future<BackupData> _createBackupData() async {
    final db = await _dbHelper.database;
    final notes = await db.query(
      'notes',
      where: 'database_id = ?',
      whereArgs: [_currentDatabaseId],
    );
    final folders = await db.query(
      'folders',
      where: 'database_id = ?',
      whereArgs: [_currentDatabaseId],
    );
    final scheduleEntries = await db.query(
      'schedule_entries',
      where: 'database_id = ?',
      whereArgs: [_currentDatabaseId],
    );
    final pinboardNotes = await db.query(
      'pinboard_notes',
      where: 'database_id = ?',
      whereArgs: [_currentDatabaseId],
    );
    final connections = await db.query(
      'connections',
      where: 'database_id = ?',
      whereArgs: [_currentDatabaseId],
    );
    final noteImages = await db.query(
      'note_images',
      where: 'note_id IN (SELECT id FROM notes WHERE database_id = ?)',
      whereArgs: [_currentDatabaseId],
    );

    return BackupData(
      notes: notes,
      folders: folders,
      scheduleEntries: scheduleEntries,
      pinboardNotes: pinboardNotes,
      connections: connections,
      noteImages: noteImages,
    );
  }

  Future<void> _applyBackupData(BackupData backupData) async {
    final db = await _dbHelper.database;
    
    await db.transaction((txn) async {
      // Очищаем существующие данные для текущей базы
      await txn.delete(
        'notes',
        where: 'database_id = ?',
        whereArgs: [_currentDatabaseId],
      );
      await txn.delete(
        'folders',
        where: 'database_id = ?',
        whereArgs: [_currentDatabaseId],
      );
      await txn.delete(
        'schedule_entries',
        where: 'database_id = ?',
        whereArgs: [_currentDatabaseId],
      );
      await txn.delete(
        'pinboard_notes',
        where: 'database_id = ?',
        whereArgs: [_currentDatabaseId],
      );
      await txn.delete(
        'connections',
        where: 'database_id = ?',
        whereArgs: [_currentDatabaseId],
      );
      await txn.delete(
        'note_images',
        where: 'note_id IN (SELECT id FROM notes WHERE database_id = ?)',
        whereArgs: [_currentDatabaseId],
      );
      
      // Вставляем новые данные
      for (final note in backupData.notes) {
        note['database_id'] = _currentDatabaseId;
        await txn.insert('notes', note);
      }
      for (final folder in backupData.folders) {
        folder['database_id'] = _currentDatabaseId;
        await txn.insert('folders', folder);
      }
      for (final entry in backupData.scheduleEntries) {
        entry['database_id'] = _currentDatabaseId;
        await txn.insert('schedule_entries', entry);
      }
      for (final note in backupData.pinboardNotes) {
        note['database_id'] = _currentDatabaseId;
        await txn.insert('pinboard_notes', note);
      }
      for (final connection in backupData.connections) {
        connection['database_id'] = _currentDatabaseId;
        await txn.insert('connections', connection);
      }
      for (final image in backupData.noteImages) {
        await txn.insert('note_images', image);
      }
    });
  }

  void setCurrentDatabase(String? databaseId) {
    _currentDatabaseId = databaseId;
  }

  void dispose() {
    _syncTimer?.cancel();
  }
} 