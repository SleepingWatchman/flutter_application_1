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
  String? database_id;

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
    this.database_id,
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
      'database_id': database_id,
    };
  }

  factory PinboardNoteDB.fromMap(Map<String, dynamic> map) {
    // Вспомогательная функция для безопасного парсинга double
    double _parseDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Вспомогательная функция для безопасного парсинга int
    int _parseInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return PinboardNoteDB(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      posX: _parseDouble(map['position_x'], 0.0),
      posY: _parseDouble(map['position_y'], 0.0),
      width: _parseDouble(map['width'], 200.0),
      height: _parseDouble(map['height'], 150.0),
      backgroundColor: _parseInt(map['background_color'], 0xFF424242),
      icon: _getIconKey(_parseInt(map['icon'], Icons.person.codePoint)),
      database_id: map['database_id'] as String?,
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