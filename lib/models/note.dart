import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'dart:convert';

/// Модель заметки
class Note {
  final int? id;
  final String title;
  final String? content;
  final int? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  List<String>? images; // Список путей к изображениям
  Map<String, dynamic>? metadata; // Дополнительные метаданные
  final String? content_json; // JSON-представление контента
  final String? database_id; // ID базы данных для совместной работы
  
  Note({
    this.id,
    required this.title,
    this.content,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.images,
    this.metadata,
    this.content_json,
    this.database_id,
  });
  
  // Преобразование в HTML для отображения
  String toHtml() {
    return md.markdownToHtml(content ?? '');
  }

  // Преобразование в JSON для хранения
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder_id': folderId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'images': images != null ? jsonEncode(images) : null,
      'metadata': metadata,
      'content_json': content_json,
      'database_id': database_id,
    };
  }

  // Создание из JSON
  factory Note.fromMap(Map<String, dynamic> map) {
    List<String>? imagesList;
    if (map['images'] != null) {
      try {
        // Попытка декодировать, если это строка JSON
        if (map['images'] is String) {
          final decodedImages = jsonDecode(map['images'] as String);
          if (decodedImages is List) {
            imagesList = List<String>.from(decodedImages.map((item) => item.toString()));
          }
        } else if (map['images'] is List) {
          // Если это уже список (например, после jsonDecode ранее или из другого источника)
          imagesList = List<String>.from(map['images'].map((item) => item.toString()));
        }
      } catch (e) {
        print("Error decoding images from map: $e, images data: ${map['images']}");
        imagesList = null; // или [] в зависимости от логики
      }
    }

    Map<String, dynamic>? metadataMap;
    if (map['metadata'] != null) {
      if (map['metadata'] is String) {
        try {
          metadataMap = jsonDecode(map['metadata'] as String);
        } catch (e) {
          print("Error decoding metadata string from map: $e, metadata data: ${map['metadata']}");
          metadataMap = null;
        }
      } else if (map['metadata'] is Map) {
        // Если это уже Map, пробуем привести его к Map<String, dynamic>
        try {
          metadataMap = Map<String, dynamic>.from(map['metadata']);
        } catch (e) {
           print("Error casting metadata map: $e, metadata data: ${map['metadata']}");
           metadataMap = null;
        }
      }
    }
    
    return Note(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '', // Если title null, ставим пустую строку
      content: map['content'] as String?,
      folderId: map['folder_id'] as int?,
      // Добавляем проверку на null и используем DateTime.now() как запасной вариант
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
      images: imagesList,
      metadata: metadataMap,
      content_json: map['content_json'] as String?,
      database_id: map['database_id'] as String?,
    );
  }

  // Преобразование в JSON строку
  String toJson() {
    return jsonEncode(toMap());
  }

  // Создание из JSON строки
  factory Note.fromJson(String json) {
    return Note.fromMap(jsonDecode(json));
  }

  // Копирование заметки с новыми данными
  Note copyWith({
    int? id,
    String? title,
    String? content,
    int? folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? images,
    Map<String, dynamic>? metadata,
    String? content_json,
    String? database_id,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      images: images ?? this.images,
      metadata: metadata ?? this.metadata,
      content_json: content_json ?? this.content_json,
      database_id: database_id ?? this.database_id,
    );
  }

  Note copy({
    int? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? database_id,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      folderId: this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      images: this.images,
      metadata: this.metadata,
      content_json: this.content_json,
      database_id: database_id ?? this.database_id,
    );
  }
} 