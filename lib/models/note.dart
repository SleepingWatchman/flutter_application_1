import 'package:flutter/material.dart';

/// Модель заметки
class Note {
  int? id;
  String title;
  String content;
  String? folder;
  
  Note({
    this.id, 
    this.title = 'Без названия', 
    this.content = '', 
    this.folder
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder': folder,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      folder: map['folder'],
    );
  }
} 