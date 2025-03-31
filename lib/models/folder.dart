import 'package:flutter/material.dart';

/// Модель папки
class Folder {
  final int? id;
  final String name;
  bool isExpanded;
  final Color color;

  Folder({
    this.id,
    required this.name,
    this.isExpanded = false,
    this.color = Colors.blue,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_expanded': isExpanded ? 1 : 0,
      'color': color.value,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'],
      name: map['name'],
      isExpanded: (map['is_expanded'] ?? 1) == 1,
      color: Color(map['color'] ?? Colors.blue.value),
    );
  }
} 