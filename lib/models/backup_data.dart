import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class BackupData {
  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> scheduleEntries;
  final List<Map<String, dynamic>> pinboardNotes;
  final List<Map<String, dynamic>> connections;
  final List<Map<String, dynamic>> noteImages;
  final String? databaseId;
  final String? userId;
  final DateTime lastModified;
  final DateTime createdAt;

  BackupData({
    required this.folders,
    required this.notes,
    required this.scheduleEntries,
    required this.pinboardNotes,
    required this.connections,
    required this.noteImages,
    this.databaseId,
    this.userId,
    DateTime? lastModified,
    DateTime? createdAt,
  }) : 
    this.lastModified = lastModified ?? DateTime.now(),
    this.createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    // Проверяем наличие и размеры изображений
    if (noteImages.isNotEmpty) {
      print('BackupData.toJson: конвертация ${noteImages.length} изображений');
      int validImages = 0;
      int invalidImages = 0;
      
      for (var image in noteImages) {
        if (image.containsKey('image_data') && image['image_data'] != null) {
          if (image['image_data'] is Uint8List && (image['image_data'] as Uint8List).isNotEmpty) {
            validImages++;
          } else {
            invalidImages++;
          }
        } else {
          invalidImages++;
        }
      }
      
      print('BackupData.toJson: обнаружено $validImages корректных и $invalidImages некорректных изображений');
    }
    
    return {
      'folders': _encodeList(folders),
      'notes': _encodeList(notes),
      'scheduleEntries': _encodeList(scheduleEntries),
      'pinboardNotes': _encodeList(pinboardNotes),
      'connections': _encodeList(connections),
      'images': _encodeImages(noteImages),
      'lastModified': lastModified.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'databaseId': databaseId,
      'userId': userId,
    };
  }

  List<Map<String, dynamic>> _encodeList(List<Map<String, dynamic>> list) {
    return list.map((item) {
      var encoded = Map<String, dynamic>.from(item);
      encoded.forEach((key, value) {
        if (value is DateTime) {
          encoded[key] = value.toIso8601String();
        } else if (value is Uint8List) {
          encoded[key] = base64Encode(value);
        } else if (value is Color) {
          encoded[key] = value.value;
        } else if (value != null && value.runtimeType.toString().contains('Color')) {
          try {
            encoded[key] = (value as dynamic).value as int;
          } catch (e) {
            print('Ошибка конвертации Color для $key: $e');
            encoded[key] = 0xFF000000;
          }
        } else if (value is int && key.toLowerCase().contains('color')) {
          encoded[key] = value;
        }
      });
      return encoded;
    }).toList();
  }

  List<Map<String, dynamic>> _encodeImages(List<Map<String, dynamic>> images) {
    List<Map<String, dynamic>> result = [];
    int errorCount = 0;
    
    for (var image in images) {
      try {
        var encoded = Map<String, dynamic>.from(image);
        if (!encoded.containsKey('image_data') || encoded['image_data'] == null) {
          print('Ошибка: изображение без данных, пропускаем');
          errorCount++;
          continue;
        }
        
        if (encoded['image_data'] is Uint8List) {
          Uint8List data = encoded['image_data'] as Uint8List;
          if (data.isEmpty) {
            print('Ошибка: изображение с пустыми данными, пропускаем');
            errorCount++;
            continue;
          }
          
          try {
            encoded['image_data'] = base64Encode(data);
          } catch (e) {
            print('Ошибка при кодировании изображения в base64: $e');
            errorCount++;
            continue;
          }
        } else {
          print('Ошибка: неизвестный формат данных изображения: ${encoded['image_data'].runtimeType}');
          errorCount++;
          continue;
        }
        
        result.add(encoded);
      } catch (e) {
        print('Ошибка при обработке изображения: $e');
        errorCount++;
      }
    }
    
    if (errorCount > 0) {
      print('При кодировании изображений обнаружено $errorCount ошибок');
    }
    
    return result;
  }

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      folders: _decodeList(json['folders'] ?? []),
      notes: _decodeList(json['notes'] ?? []),
      scheduleEntries: _decodeList(json['scheduleEntries'] ?? json['schedule'] ?? []),
      pinboardNotes: _decodeList(json['pinboardNotes'] ?? []),
      connections: _decodeList(json['connections'] ?? []),
      noteImages: _decodeImages(json['images'] ?? []),
      databaseId: json['databaseId'] as String?,
      userId: json['userId'] as String?,
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified'] as String)
        : null,
      createdAt: json['createdAt'] != null 
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    );
  }

  static List<Map<String, dynamic>> _decodeList(List<dynamic> list) {
    return list.map((item) {
      var decoded = Map<String, dynamic>.from(item);
      decoded.forEach((key, value) {
        if (value is String) {
          if (key.toLowerCase().contains('date') || 
              key.toLowerCase().contains('created_at') || 
              key.toLowerCase().contains('updated_at')) {
            try {
              // Оставляем значение как строку для SQLite
              decoded[key] = value;
            } catch (e) {
              print('Ошибка при обработке даты $value: $e');
            }
          }
        }
      });
      return decoded;
    }).toList();
  }

  static List<Map<String, dynamic>> _decodeImages(List<dynamic> images) {
    return images.map((image) {
      if (image == null) {
        return <String, dynamic>{
          'note_id': 0,
          'file_name': '',
          'image_data': Uint8List(0)
        };
      }
      
      var decoded = Map<String, dynamic>.from(image);
      
      // Проверка обязательного поля note_id
      if (!decoded.containsKey('note_id') || decoded['note_id'] == null) {
        decoded['note_id'] = 0;
        print('Предупреждение: отсутствует note_id для изображения');
      }
      
      // Проверка обязательного поля file_name
      if (!decoded.containsKey('file_name') || decoded['file_name'] == null) {
        decoded['file_name'] = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        print('Предупреждение: отсутствует file_name для изображения, создан временный');
      }
      
      // Обработка данных изображения
      if (!decoded.containsKey('image_data') || decoded['image_data'] == null) {
        print('Предупреждение: отсутствуют данные изображения');
        decoded['image_data'] = Uint8List(0);
      } else if (decoded['image_data'] is String) {
        try {
          // Декодируем base64 в бинарные данные
          final String base64Data = decoded['image_data'] as String;
          if (base64Data.isNotEmpty) {
            try {
              decoded['image_data'] = base64Decode(base64Data);
            } catch (e) {
              print('Ошибка при декодировании base64 для ${decoded['file_name']}: $e');
              decoded['image_data'] = Uint8List(0);
            }
          } else {
            print('Предупреждение: пустые данные изображения для ${decoded['file_name']}');
            decoded['image_data'] = Uint8List(0);
          }
        } catch (e) {
          print('Ошибка при декодировании изображения ${decoded['file_name']}: $e');
          decoded['image_data'] = Uint8List(0);
        }
      } else if (decoded['image_data'] is List) {
        // Если данные уже в виде списка байтов, преобразуем их в Uint8List
        try {
          decoded['image_data'] = Uint8List.fromList(List<int>.from(decoded['image_data']));
        } catch (e) {
          print('Ошибка при преобразовании списка байтов для ${decoded['file_name']}: $e');
          decoded['image_data'] = Uint8List(0);
        }
      }
      return decoded;
    }).toList();
  }

  // Метод для подготовки данных к сохранению в SQLite
  static Map<String, dynamic> prepareForSqlite(Map<String, dynamic> data) {
    var prepared = Map<String, dynamic>.from(data);
    prepared.forEach((key, value) {
      if (value is DateTime) {
        prepared[key] = value.toIso8601String();
      } else if (value is bool) {
        // SQLite не поддерживает bool, конвертируем в int
        prepared[key] = value ? 1 : 0;
      }
    });
    return prepared;
  }
} 