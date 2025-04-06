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
  
  Note({
    this.id,
    required this.title,
    this.content,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.images,
    this.metadata,
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
      'images': images,
      'metadata': metadata,
    };
  }

  // Создание из JSON
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String?,
      folderId: map['folder_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      images: map['images'] != null ? List<String>.from(map['images']) : null,
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
    int? id,
    String? title,
    String? content,
    int? folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? images,
    Map<String, dynamic>? metadata,
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
    );
  }
} 