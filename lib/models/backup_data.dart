import 'dart:convert';
import 'dart:typed_data';

class BackupData {
  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> scheduleEntries;
  final List<Map<String, dynamic>> pinboardNotes;
  final List<Map<String, dynamic>> connections;
  final List<Map<String, dynamic>> noteImages;

  BackupData({
    required this.folders,
    required this.notes,
    required this.scheduleEntries,
    required this.pinboardNotes,
    required this.connections,
    required this.noteImages,
  });

  Map<String, dynamic> toJson() {
    return {
      'folders': _encodeList(folders),
      'notes': _encodeList(notes),
      'schedule': _encodeList(scheduleEntries),
      'pinboardNotes': _encodeList(pinboardNotes),
      'connections': _encodeList(connections),
      'images': _encodeImages(noteImages),
      'lastModified': DateTime.now().toIso8601String(),
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
        }
      });
      return encoded;
    }).toList();
  }

  List<Map<String, dynamic>> _encodeImages(List<Map<String, dynamic>> images) {
    return images.map((image) {
      var encoded = Map<String, dynamic>.from(image);
      if (encoded['image_data'] is Uint8List) {
        encoded['image_data'] = base64Encode(encoded['image_data'] as Uint8List);
      }
      return encoded;
    }).toList();
  }

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      folders: _decodeList(json['folders'] ?? []),
      notes: _decodeList(json['notes'] ?? []),
      scheduleEntries: _decodeList(json['schedule'] ?? []),
      pinboardNotes: _decodeList(json['pinboardNotes'] ?? []),
      connections: _decodeList(json['connections'] ?? []),
      noteImages: _decodeImages(json['images'] ?? []),
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
      var decoded = Map<String, dynamic>.from(image);
      if (decoded['image_data'] is String) {
        try {
          decoded['image_data'] = base64Decode(decoded['image_data'] as String);
        } catch (e) {
          print('Ошибка при декодировании изображения: $e');
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
      }
    });
    return prepared;
  }
} 