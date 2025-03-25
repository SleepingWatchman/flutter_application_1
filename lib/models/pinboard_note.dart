import 'package:flutter/material.dart';

/// Модель заметки для доски (для работы с БД)
class PinboardNoteDB {
  int? id;
  String title;
  String content;
  double posX;
  double posY;
  int backgroundColor;
  String icon; // новое поле

  PinboardNoteDB({
    this.id,
    this.title = 'Без названия',
    this.content = '',
    required this.posX,
    required this.posY,
    required this.backgroundColor,
    this.icon = 'person', // дефолтное значение
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'posX': posX,
      'posY': posY,
      'backgroundColor': backgroundColor,
      'icon': icon, // сохраняем значок
    };
  }

  factory PinboardNoteDB.fromMap(Map<String, dynamic> map) {
    return PinboardNoteDB(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      posX: map['posX'],
      posY: map['posY'],
      backgroundColor: map['backgroundColor'],
      icon: map['icon'] ?? 'person',
    );
  }
} 