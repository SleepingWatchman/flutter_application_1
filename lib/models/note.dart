import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'dart:convert';

/// Модель заметки
class Note {
  int? id;
  String title;
  String? content;
  int? folderId;
  DateTime? createdAt;
  DateTime? updatedAt;
  List<String>? images; // Список путей к изображениям
  Map<String, dynamic>? metadata; // Дополнительные метаданные
  
  Note({
    this.id, 
    required this.title, 
    this.content, 
    this.folderId,
    this.createdAt,
    this.updatedAt,
    this.images,
    this.metadata,
  });
  
  // Преобразование в HTML для отображения
  String toHtml() {
    if (content == null) return '';
    return md.markdownToHtml(content!);
  }

  // Преобразование в JSON для хранения
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder_id': folderId,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'images': images,
      'metadata': metadata,
    };
  }

  // Создание из JSON
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'] ?? 'Без названия',
      content: map['content'],
      folderId: map['folder_id'],
      createdAt: map['created_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'])
          : null,
      updatedAt: map['updated_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
      images: List<String>.from(map['images'] ?? []),
      metadata: map['metadata'],
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
    String? title,
    String? content,
    int? folderId,
    List<String>? images,
    Map<String, dynamic>? metadata,
  }) {
    return Note(
      id: this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      folderId: folderId ?? this.folderId,
      createdAt: this.createdAt,
      updatedAt: DateTime.now(),
      images: images ?? this.images,
      metadata: metadata ?? this.metadata,
    );
  }
} 