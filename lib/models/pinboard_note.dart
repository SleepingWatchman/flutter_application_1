import 'package:flutter/material.dart';

/// Модель заметки для доски (для работы с БД)
class PinboardNoteDB {
  int? id;
  String title;
  String content;
  double posX;
  double posY;
  double width;
  double height;
  int backgroundColor;
  String icon;

  PinboardNoteDB({
    this.id,
    this.title = '',
    this.content = '',
    required this.posX,
    required this.posY,
    this.width = 200.0,
    this.height = 150.0,
    this.backgroundColor = 0xFF424242, // Темно-серый по умолчанию
    this.icon = 'person',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'position_x': posX,
      'position_y': posY,
      'width': width,
      'height': height,
      'background_color': backgroundColor,
      'icon': _getIconCodePoint(icon), // Сохраняем codePoint иконки
    };
  }

  factory PinboardNoteDB.fromMap(Map<String, dynamic> map) {
    return PinboardNoteDB(
      id: map['id'],
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      posX: map['position_x'] ?? 0.0,
      posY: map['position_y'] ?? 0.0,
      width: map['width'] ?? 200.0,
      height: map['height'] ?? 150.0,
      backgroundColor: map['background_color'] ?? 0xFF424242,
      icon: _getIconKey(map['icon'] ?? Icons.person.codePoint), // Преобразуем codePoint в ключ
    );
  }

  // Преобразование строкового ключа в codePoint иконки
  int _getIconCodePoint(String iconKey) {
    switch (iconKey) {
      case 'person':
        return Icons.person.codePoint;
      case 'check':
        return Icons.check_circle.codePoint;
      case 'tree':
        return Icons.forest.codePoint;
      case 'home':
        return Icons.home.codePoint;
      case 'car':
        return Icons.directions_car.codePoint;
      case 'close':
        return Icons.close.codePoint;
      default:
        return Icons.person.codePoint;
    }
  }

  // Преобразование codePoint в строковый ключ
  static String _getIconKey(int codePoint) {
    if (codePoint == Icons.person.codePoint) return 'person';
    if (codePoint == Icons.check_circle.codePoint) return 'check';
    if (codePoint == Icons.forest.codePoint) return 'tree';
    if (codePoint == Icons.home.codePoint) return 'home';
    if (codePoint == Icons.directions_car.codePoint) return 'car';
    if (codePoint == Icons.close.codePoint) return 'close';
    return 'person';
  }
} 