import 'package:flutter/material.dart';

/// Модель заметки
class Note {
  int? id;
  String title;
  String? content;
  int? folderId;
  
  Note({
    this.id, 
    required this.title, 
    this.content, 
    this.folderId
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder_id': folderId,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      folderId: map['folder_id'],
    );
  }
} 