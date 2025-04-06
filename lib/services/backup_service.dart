import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/note.dart';
import '../models/folder.dart';
import '../models/schedule_entry.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import '../db/database_helper.dart';
import '../providers/auth_provider.dart';

class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final String _baseUrl = 'http://127.0.0.1:5294/api/backup';
  final AuthProvider _authProvider;

  BackupService(this._authProvider);

  Future<Map<String, dynamic>> createBackup() async {
    try {
      print('Начало создания резервной копии...');
      
      // Получаем все данные из базы данных
      final folders = await _dbHelper.getFolders();
      print('Получено папок: ${folders.length}');
      
      final notes = await _dbHelper.getAllNotes();
      print('Получено заметок: ${notes.length}');
      
      // Получаем все записи расписания
      final scheduleEntries = await _dbHelper.getAllScheduleEntries();
      print('Получено записей расписания: ${scheduleEntries.length}');
      
      final pinboardNotes = await _dbHelper.getPinboardNotes();
      print('Получено заметок на доске: ${pinboardNotes.length}');
      
      final connections = await _dbHelper.getConnections();
      print('Получено соединений: ${connections.length}');
      
      final images = <Map<String, dynamic>>[];

      // Собираем информацию об изображениях для всех заметок
      for (var note in notes) {
        if (note.id != null) {
          final noteImages = await _dbHelper.getImagesForNote(note.id!);
          images.addAll(noteImages);
        }
      }
      print('Получено изображений: ${images.length}');

      final backupData = {
        'folders': folders.map((folder) => {
          'id': folder.id,
          'name': folder.name,
          'color': folder.color,
          'isExpanded': folder.isExpanded,
        }).toList(),
        'notes': notes.map((note) => {
          'id': note.id,
          'title': note.title,
          'content': note.content,
          'folderId': note.folderId,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
          'images': note.images,
          'metadata': note.metadata,
        }).toList(),
        'schedule': scheduleEntries.map((entry) => {
          'id': entry.id,
          'time': entry.time,
          'date': entry.date,
          'note': entry.note,
          'dynamicFieldsJson': entry.dynamicFieldsJson,
        }).toList(),
        'pinboardNotes': pinboardNotes.map((note) => {
          'id': note.id,
          'title': note.title,
          'content': note.content,
          'positionX': note.posX,
          'positionY': note.posY,
          'backgroundColor': note.backgroundColor,
          'icon': note.icon,
        }).toList(),
        'connections': connections.map((conn) => {
          'id': conn.id,
          'fromId': conn.fromId,
          'toId': conn.toId,
          'name': conn.name,
          'connectionColor': conn.connectionColor,
        }).toList(),
        'images': images,
        'lastModified': DateTime.now().toIso8601String(),
      };

      print('Резервная копия создана успешно');
      return backupData;
    } catch (e) {
      print('Ошибка при создании резервной копии: $e');
      rethrow;
    }
  }

  Future<void> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      print('Начало восстановления из резервной копии...');
      
      // Очищаем текущую базу данных
      await _dbHelper.clearDatabase();
      print('База данных очищена');

      // Восстанавливаем папки
      if (backupData['folders'] != null) {
        for (var folderData in backupData['folders']) {
          final folder = Folder(
            id: folderData['id'],
            name: folderData['name'],
            color: folderData['color'],
            isExpanded: folderData['isExpanded'] ?? true,
          );
          await _dbHelper.insertFolder(folder);
        }
        print('Восстановлено папок: ${backupData['folders'].length}');
      }

      // Восстанавливаем заметки
      if (backupData['notes'] != null) {
        for (var noteData in backupData['notes']) {
          final note = Note(
            id: noteData['id'] as int?,
            title: noteData['title'],
            content: noteData['content'],
            folderId: noteData['folderId'],
            createdAt: DateTime.parse(noteData['createdAt']),
            updatedAt: DateTime.parse(noteData['updatedAt']),
            images: noteData['images'] != null ? List<String>.from(noteData['images']) : null,
            metadata: noteData['metadata'],
          );
          await _dbHelper.insertNote(note);
        }
        print('Восстановлено заметок: ${backupData['notes'].length}');
      }

      // Восстанавливаем записи расписания
      if (backupData['schedule'] != null) {
        for (var entryData in backupData['schedule']) {
          final entry = ScheduleEntry(
            id: entryData['id'],
            time: entryData['time'],
            date: entryData['date'],
            note: entryData['note'],
            dynamicFieldsJson: entryData['dynamicFieldsJson'],
          );
          await _dbHelper.insertScheduleEntry(entry);
        }
        print('Восстановлено записей расписания: ${backupData['schedule'].length}');
      }

      // Восстанавливаем заметки на доске
      if (backupData['pinboardNotes'] != null) {
        for (var noteData in backupData['pinboardNotes']) {
          final note = PinboardNoteDB(
            id: noteData['id'],
            title: noteData['title'],
            content: noteData['content'],
            posX: noteData['positionX'],
            posY: noteData['positionY'],
            backgroundColor: noteData['backgroundColor'],
            icon: noteData['icon'],
          );
          await _dbHelper.insertPinboardNote(note);
        }
        print('Восстановлено заметок на доске: ${backupData['pinboardNotes'].length}');
      }

      // Восстанавливаем соединения
      if (backupData['connections'] != null) {
        for (var connData in backupData['connections']) {
          final conn = ConnectionDB(
            id: connData['id'],
            fromId: connData['fromId'],
            toId: connData['toId'],
            name: connData['name'],
            connectionColor: connData['connectionColor'],
          );
          await _dbHelper.insertConnection(conn);
        }
        print('Восстановлено соединений: ${backupData['connections'].length}');
      }

      // Восстанавливаем изображения
      if (backupData['images'] != null) {
        for (var imageData in backupData['images']) {
          await _dbHelper.insertImage(
            imageData['note_id'] as int,
            imageData['file_name'] as String,
            imageData['file_path'] as String,
          );
        }
        print('Восстановлено изображений: ${backupData['images'].length}');
      }

      print('Восстановление из резервной копии завершено успешно');
    } catch (e) {
      print('Ошибка при восстановлении из резервной копии: $e');
      rethrow;
    }
  }

  Future<void> uploadBackup() async {
    try {
      print('Начало загрузки резервной копии на сервер...');
      
      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      print('Токен авторизации: $token');
      print('Заголовки запроса:');
      print('Content-Type: application/json');
      print('Authorization: Bearer $token');

      final backupData = await createBackup();
      print('Данные для загрузки: ${jsonEncode(backupData)}');

      final response = await http.post(
        Uri.parse('$_baseUrl/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(backupData),
      );

      print('Ответ сервера: ${response.statusCode}');
      print('Тело ответа: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Ошибка при загрузке резервной копии: ${response.statusCode}');
      }
      
      print('Резервная копия успешно загружена на сервер');
    } catch (e) {
      print('Ошибка при загрузке резервной копии: $e');
      rethrow;
    }
  }

  Future<void> downloadBackup() async {
    try {
      print('Начало загрузки резервной копии с сервера...');
      
      final token = _authProvider.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/download'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      print('Ответ сервера: ${response.statusCode}');
      print('Тело ответа: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Ошибка при загрузке резервной копии: ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body);
      print('Данные для восстановления: ${jsonEncode(responseData)}');

      await restoreFromBackup(responseData);
      
      print('Резервная копия успешно загружена с сервера и восстановлена');
    } catch (e) {
      print('Ошибка при загрузке резервной копии: $e');
      rethrow;
    }
  }
} 