import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
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

  Future<String> createBackup() async {
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
          // Получаем изображения из базы данных
          final noteImages = await _dbHelper.getImagesForNote(note.id!);
          for (var image in noteImages) {
            final imageData = await _dbHelper.getImageData(image['id'] as int);
            if (imageData != null) {
              images.add({
                'note_id': image['note_id'],
                'file_name': image['file_name'],
                'image_data': base64Encode(imageData),
              });
            }
          }
          
          // Также проверяем изображения в content_json
          if (note.content_json != null) {
            try {
              final contentJson = jsonDecode(note.content_json!);
              if (contentJson['images'] != null) {
                for (var imagePath in contentJson['images']) {
                  final imageData = await _dbHelper.getImageDataByPath(imagePath);
                  if (imageData != null) {
                    images.add({
                      'note_id': note.id,
                      'file_name': imagePath.split('/').last,
                      'image_data': base64Encode(imageData),
                    });
                  }
                }
              }
            } catch (e) {
              print('Ошибка при обработке content_json: $e');
            }
          }
        }
      }
      print('Получено изображений: ${images.length}');

      final backupData = {
        'folders': folders.map((folder) => {
          'id': folder.id,
          'name': folder.name,
          'color': folder.color.value.toRadixString(16),
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
          'content_json': note.content_json,
        }).toList(),
        'schedule': scheduleEntries.map((entry) => {
          'id': entry.id,
          'time': entry.time,
          'date': entry.date,
          'note': entry.note,
          'dynamicFieldsJson': entry.dynamicFieldsJson,
        }).toList(),
        'pinboardNotes': pinboardNotes.map((note) {
          print('Сохранение заметки на доске: ${note.title}');
          print('Данные заметки: id=${note.id}, posX=${note.posX}, posY=${note.posY}, width=${note.width}, height=${note.height}, backgroundColor=${note.backgroundColor}');
          return {
            'id': note.id,
            'title': note.title,
            'content': note.content,
            'positionX': note.posX,
            'positionY': note.posY,
            'width': note.width,
            'height': note.height,
            'backgroundColor': note.backgroundColor.toDouble(),
            'icon': note.icon,
          };
        }).toList(),
        'connections': connections.map((conn) => {
          'id': conn.id,
          'fromId': conn.fromId,
          'toId': conn.toId,
          'name': conn.name,
          'connectionColor': conn.connectionColor.toRadixString(16),
        }).toList(),
        'images': images,
        'lastModified': DateTime.now().toIso8601String(),
      };

      print('Резервная копия создана успешно');
      return jsonEncode(backupData);
    } catch (e) {
      print('Ошибка при создании резервной копии: $e');
      rethrow;
    }
  }

  Future<void> restoreFromBackup(String backupJson) async {
    try {
      print('Начало восстановления из резервной копии...');
      
      // Очищаем текущую базу данных
      await _dbHelper.clearDatabase();
      print('База данных очищена');

      final backupData = jsonDecode(backupJson);

      // Восстанавливаем папки
      if (backupData['folders'] != null) {
        for (var folderData in backupData['folders']) {
          final folder = Folder(
            id: folderData['id'],
            name: folderData['name'],
            color: Color(int.parse(folderData['color'], radix: 16)),
            isExpanded: folderData['isExpanded'] ?? true,
          );
          await _dbHelper.insertFolder(folder);
        }
        print('Восстановлено папок: ${backupData['folders'].length}');
      }

      // Восстанавливаем заметки
      if (backupData['notes'] != null) {
        for (var noteData in backupData['notes']) {
          // Получаем изображения для заметки
          final noteImages = (backupData['images'] as List?)
              ?.where((img) => img['note_id'] == noteData['id'])
              .map((img) => img['file_name'] as String)
              .toList() ?? [];
          
          // Создаем JSON с информацией об изображениях
          final contentJson = {
            'content': noteData['content'],
            'images': noteImages,
          };
          
          final note = Note(
            id: noteData['id'] as int?,
            title: noteData['title'],
            content: noteData['content'],
            folderId: noteData['folderId'],
            createdAt: DateTime.parse(noteData['createdAt']),
            updatedAt: DateTime.parse(noteData['updatedAt']),
            images: noteImages,
            metadata: noteData['metadata'],
            content_json: jsonEncode(contentJson),
          );
          await _dbHelper.insertNote(note);
          
          // Сохраняем изображения для заметки
          if (note.id != null) {
            for (var imageData in (backupData['images'] as List?)
                ?.where((img) => img['note_id'] == note.id)
                .toList() ?? []) {
              final imageBytes = base64Decode(imageData['image_data'] as String);
              await _dbHelper.insertImage(
                note.id!,
                imageData['file_name'] as String,
                imageBytes,
              );
            }
          }
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
          print('Восстанавливаем заметку на доске: ${noteData['title']}');
          print('Данные заметки: $noteData');
          
          final note = PinboardNoteDB(
            id: noteData['id'],
            title: noteData['title'],
            content: noteData['content'],
            posX: noteData['positionX']?.toDouble() ?? 0.0,
            posY: noteData['positionY']?.toDouble() ?? 0.0,
            width: noteData['width']?.toDouble() ?? 200.0,
            height: noteData['height']?.toDouble() ?? 150.0,
            backgroundColor: (noteData['backgroundColor'] as num?)?.toInt() ?? 0xFF000000,
            icon: noteData['icon'],
          );
          await _dbHelper.insertPinboardNote(note);
          print('Заметка на доске восстановлена: ${note.title}');
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
            connectionColor: int.parse(connData['connectionColor'], radix: 16),
          );
          await _dbHelper.insertConnection(conn);
        }
        print('Восстановлено соединений: ${backupData['connections'].length}');
      }

      // Восстанавливаем изображения
      if (backupData['images'] != null) {
        for (var imageData in backupData['images']) {
          final imageBytes = base64Decode(imageData['image_data'] as String);
          await _dbHelper.insertImage(
            imageData['note_id'] as int,
            imageData['file_name'] as String,
            imageBytes,
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
      print('Данные для загрузки: $backupData');

      final response = await http.post(
        Uri.parse('$_baseUrl/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: backupData,
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

      await restoreFromBackup(response.body);
      
      print('Резервная копия успешно загружена с сервера и восстановлена');
    } catch (e) {
      print('Ошибка при загрузке резервной копии: $e');
      rethrow;
    }
  }
} 