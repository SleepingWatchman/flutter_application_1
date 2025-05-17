import 'package:flutter/material.dart';

/// Модель папки
class Folder {
  final int? id;
  final String name;
  bool isExpanded;
  final Color color;
  final String? database_id; // ID базы данных для совместной работы

  Folder({
    this.id,
    required this.name,
    this.isExpanded = false,
    this.color = Colors.blue,
    this.database_id,
  });
  
  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'name': name,
      'is_expanded': isExpanded ? 1 : 0,
      'color': color.value,
    };
    
    // Добавляем database_id только если он задан
    if (database_id != null) {
      map['database_id'] = database_id;
    }
    
    return map;
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'],
      name: map['name'],
      isExpanded: (map['is_expanded'] ?? 1) == 1,
      color: Color(map['color'] ?? Colors.blue.value),
      database_id: map['database_id'],
    );
  }
} 