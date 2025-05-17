import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/schedule_entry.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import '../db/database_helper.dart';
import '../providers/auth_provider.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/backup_data.dart';
import '../utils/config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class UserBackupService {
  final DatabaseHelper _dbHelper;
  final String _baseUrl;
  final String _token;

  UserBackupService(this._dbHelper, this._baseUrl, this._token);

  Future<void> createAndUploadBackup() async {
    try {
      print('Начало создания резервной копии...');
      final backupData = await _createBackup();
      print('Резервная копия создана успешно');

      print('Начало загрузки резервной копии на сервер...');
      await _uploadBackup(backupData);
      print('Резервная копия успешно загружена на сервер');
    } catch (e) {
      print('Ошибка при создании/загрузке резервной копии: $e');
      throw Exception('Ошибка при создании/загрузке резервной копии: $e');
    }
  }

  Future<BackupData> _createBackup() async {
    final folders = await _dbHelper.getFoldersForBackup();
    print('Получено папок: ${folders.length}');

    final notes = await _dbHelper.getNotesForBackup();
    print('Получено заметок: ${notes.length}');

    final scheduleEntries = await _dbHelper.getScheduleEntriesForBackup();
    print('Получено записей расписания: ${scheduleEntries.length}');

    final pinboardNotes = await _dbHelper.getPinboardNotesForBackup();
    print('Получено заметок на доске: ${pinboardNotes.length}');

    final connections = await _dbHelper.getConnectionsForBackup();
    print('Получено соединений: ${connections.length}');

    final images = await _dbHelper.getAllImagesForBackup();
    print('Получено изображений: ${images.length}');

    return BackupData(
      folders: folders,
      notes: notes,
      scheduleEntries: scheduleEntries,
      pinboardNotes: pinboardNotes,
      connections: connections,
      noteImages: images,
    );
  }

  Future<void> _uploadBackup(BackupData backupData) async {
    final url = Uri.parse('$_baseUrl/api/UserBackup/upload');
    
    // Используем UTF-8 кодировку для правильной обработки русских символов
    final jsonData = utf8.encode(jsonEncode(backupData.toJson()));
    
    final request = http.MultipartRequest('POST', url)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          jsonData,
          filename: 'backup.json',
          contentType: MediaType('application', 'json; charset=utf-8'),
        ),
      )
      ..headers['Authorization'] = 'Bearer $_token';

    final response = await request.send();
    
    if (response.statusCode != 200) {
      throw Exception('Ошибка при загрузке резервной копии: ${response.statusCode}');
    }
  }

  Future<void> restoreFromLatestBackup() async {
    try {
      print('Начало восстановления из резервной копии...');
      final backupData = await _downloadLatestBackup();
      await _restoreFromBackup(backupData);
      print('Восстановление из резервной копии завершено успешно');
    } catch (e) {
      print('Ошибка при восстановлении из резервной копии: $e');
      throw Exception('Ошибка при восстановлении из резервной копии: $e');
    }
  }

  Future<BackupData> _downloadLatestBackup() async {
    final url = Uri.parse('$_baseUrl/api/UserBackup/download/latest');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept-Charset': 'utf-8',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при загрузке резервной копии: ${response.statusCode}');
    }

    // Декодируем ответ в UTF-8
    return BackupData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<void> _restoreFromBackup(BackupData backupData) async {
    await _dbHelper.transaction((txn) async {
      // Очищаем существующие данные
      await _dbHelper.clearAllTables(txn);

      // Восстанавливаем данные
      await _restoreFolders(backupData.folders, txn);
      await _restoreNotes(backupData.notes, txn);
      await _restoreScheduleEntries(backupData.scheduleEntries, txn);
      await _restorePinboardNotes(backupData.pinboardNotes, txn);
      await _restoreConnections(backupData.connections, txn);
      await _restoreImages(backupData.noteImages, txn);
    });
  }

  Future<void> _restoreFolders(List<Map<String, dynamic>> folders, Transaction txn) async {
    for (var folder in folders) {
      await _dbHelper.insertFolderForBackup(folder, txn);
    }
  }

  Future<void> _restoreNotes(List<Map<String, dynamic>> notes, Transaction txn) async {
    for (var note in notes) {
      await _dbHelper.insertNoteForBackup(note, txn);
    }
  }

  Future<void> _restoreScheduleEntries(List<Map<String, dynamic>> entries, Transaction txn) async {
    for (var entry in entries) {
      await _dbHelper.insertScheduleEntryForBackup(entry, txn);
    }
  }

  Future<void> _restorePinboardNotes(List<Map<String, dynamic>> notes, Transaction txn) async {
    for (var note in notes) {
      await _dbHelper.insertPinboardNoteForBackup(note, txn);
    }
  }

  Future<void> _restoreConnections(List<Map<String, dynamic>> connections, Transaction txn) async {
    for (var connection in connections) {
      await _dbHelper.insertConnectionForBackup(connection, txn);
    }
  }

  Future<void> _restoreImages(List<Map<String, dynamic>> images, Transaction txn) async {
    for (var image in images) {
      try {
        final int noteId = image['note_id'];
        final String fileName = image['file_name'];
        Uint8List imageBytes;
        
        // Проверяем, в каком формате пришли данные изображения
        if (image['image_data'] is String) {
          // Если данные пришли в base64, декодируем их
          imageBytes = base64Decode(image['image_data'] as String);
        } else if (image['image_data'] is List) {
          // Если данные пришли как список байтов
          imageBytes = Uint8List.fromList(List<int>.from(image['image_data']));
        } else {
          // Если данные уже в формате Uint8List
          imageBytes = image['image_data'] as Uint8List;
        }
        
        await _dbHelper.insertImageForBackup(noteId, fileName, imageBytes, txn);
      } catch (e) {
        print('Ошибка при восстановлении изображения: $e');
        rethrow; // Пробрасываем ошибку дальше для обработки
      }
    }
  }
}

class CollaborationBackupService {
  final DatabaseHelper _dbHelper;
  final String _baseUrl;
  final String _token;

  CollaborationBackupService(this._dbHelper, this._baseUrl, this._token);

  Future<void> createAndUploadBackup(String databaseId) async {
    try {
      print('Начало создания резервной копии для совместной работы...');
      final backupData = await _createBackup(databaseId);
      print('Резервная копия создана успешно');

      print('Начало загрузки резервной копии на сервер...');
      await _uploadBackup(databaseId, backupData);
      print('Резервная копия успешно загружена на сервер');
    } catch (e) {
      print('Ошибка при создании/загрузке резервной копии: $e');
      throw Exception('Ошибка при создании/загрузке резервной копии: $e');
    }
  }

  Future<BackupData> _createBackup(String databaseId) async {
    final folders = await _dbHelper.getFoldersForDatabase(databaseId);
    print('Получено папок: ${folders.length}');
    
    final notes = await _dbHelper.getNotesForDatabase(databaseId);
    print('Получено заметок: ${notes.length}');

    final scheduleEntries = await _dbHelper.getScheduleEntriesForDatabase(databaseId);
    print('Получено записей расписания: ${scheduleEntries.length}');

    final pinboardNotes = await _dbHelper.getPinboardNotesForDatabase(databaseId);
    print('Получено заметок на доске: ${pinboardNotes.length}');

    final connections = await _dbHelper.getConnectionsForDatabase(databaseId);
    print('Получено соединений: ${connections.length}');

    // Получаем ID всех заметок для этой базы
    final noteIds = notes
        .where((note) => note['id'] != null)
        .map((note) => note['id'] as int)
        .toList();
    
    // Получаем изображения для этих заметок
    List<Map<String, dynamic>> images = [];
    if (noteIds.isNotEmpty) {
      final db = await _dbHelper.database;
      final placeholders = List.filled(noteIds.length, '?').join(',');
      images = await db.query(
        'note_images',
        where: 'note_id IN ($placeholders)',
        whereArgs: noteIds,
      );
      print('Получено изображений: ${images.length}');
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

  Future<void> _uploadBackup(String databaseId, BackupData backupData) async {
    final url = Uri.parse('$_baseUrl/api/CollaborationBackup/$databaseId/upload');
    final jsonData = jsonEncode(backupData.toJson());
    
    final request = http.MultipartRequest('POST', url)
      ..files.add(
        http.MultipartFile.fromString(
          'file',
          jsonData,
          filename: 'backup.json',
          contentType: MediaType('application', 'json; charset=utf-8'),
        ),
      )
      ..headers['Authorization'] = 'Bearer $_token';

    final response = await request.send();
    
    if (response.statusCode != 200) {
      throw Exception('Ошибка при загрузке резервной копии: ${response.statusCode}');
    }
  }

  Future<void> restoreFromLatestBackup(String databaseId) async {
    try {
      print('Начало восстановления из резервной копии...');
      final backupData = await _downloadLatestBackup(databaseId);
      await _restoreFromBackup(databaseId, backupData);
      print('Восстановление из резервной копии завершено успешно');
    } catch (e) {
      print('Ошибка при восстановлении из резервной копии: $e');
      throw Exception('Ошибка при восстановлении из резервной копии: $e');
    }
  }

  Future<BackupData> _downloadLatestBackup(String databaseId) async {
    final url = Uri.parse('$_baseUrl/api/CollaborationBackup/$databaseId/download/latest');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept-Charset': 'utf-8',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при загрузке резервной копии: ${response.statusCode}');
    }

    return BackupData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<void> _restoreFromBackup(String databaseId, BackupData backupData) async {
    await _dbHelper.transaction((txn) async {
      // Очищаем существующие данные только для указанной базы данных
      await _dbHelper.clearDatabaseTablesForBackup(databaseId, txn);

      // Восстанавливаем данные с указанным database_id
      await _restoreFolders(databaseId, backupData.folders, txn);
      await _restoreNotes(databaseId, backupData.notes, txn);
      await _restoreScheduleEntries(databaseId, backupData.scheduleEntries, txn);
      await _restorePinboardNotes(databaseId, backupData.pinboardNotes, txn);
      await _restoreConnections(databaseId, backupData.connections, txn);
      await _restoreImages(databaseId, backupData.noteImages, txn);
      
      print('Восстановлены данные для базы $databaseId: папок - ${backupData.folders.length}, заметок - ${backupData.notes.length}, записей расписания - ${backupData.scheduleEntries.length}, изображений - ${backupData.noteImages.length}');
    });
  }

  Future<void> _restoreFolders(String databaseId, List<Map<String, dynamic>> folders, Transaction txn) async {
    for (var folder in folders) {
      folder['database_id'] = databaseId;
      await _dbHelper.insertFolderForBackup(folder, txn);
    }
  }

  Future<void> _restoreNotes(String databaseId, List<Map<String, dynamic>> notes, Transaction txn) async {
    for (var note in notes) {
      note['database_id'] = databaseId;
      await _dbHelper.insertNoteForBackup(note, txn);
    }
  }

  Future<void> _restoreScheduleEntries(String databaseId, List<Map<String, dynamic>> entries, Transaction txn) async {
    for (var entry in entries) {
      entry['database_id'] = databaseId;
      await _dbHelper.insertScheduleEntryForBackup(entry, txn);
    }
  }

  Future<void> _restorePinboardNotes(String databaseId, List<Map<String, dynamic>> notes, Transaction txn) async {
    for (var note in notes) {
      note['database_id'] = databaseId;
      await _dbHelper.insertPinboardNoteForBackup(note, txn);
    }
  }

  Future<void> _restoreConnections(String databaseId, List<Map<String, dynamic>> connections, Transaction txn) async {
    for (var connection in connections) {
      connection['database_id'] = databaseId;
      await _dbHelper.insertConnectionForBackup(connection, txn);
    }
  }

  Future<void> _restoreImages(String databaseId, List<Map<String, dynamic>> images, Transaction txn) async {
    for (var image in images) {
      try {
        final int noteId = image['note_id'];
        final String fileName = image['file_name'];
        Uint8List imageBytes;
        
        // Проверяем, в каком формате пришли данные изображения
        if (image['image_data'] is String) {
          // Если данные пришли в base64, декодируем их
          imageBytes = base64Decode(image['image_data'] as String);
        } else if (image['image_data'] is List) {
          // Если данные пришли как список байтов
          imageBytes = Uint8List.fromList(List<int>.from(image['image_data']));
        } else {
          // Если данные уже в формате Uint8List
          imageBytes = image['image_data'] as Uint8List;
        }
        
        await _dbHelper.insertImageForBackup(noteId, fileName, imageBytes, txn);
      } catch (e) {
        print('Ошибка при восстановлении изображения: $e');
        // Пробрасываем ошибку дальше для обработки
      }
    }
  }
} 