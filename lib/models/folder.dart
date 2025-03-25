import 'package:flutter/material.dart';

/// Модель папки
class Folder {
  int? id;
  String name;
  int backgroundColor; // хранится как int (ARGB)
  
  Folder({
    this.id, 
    required this.name, 
    required this.backgroundColor
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'backgroundColor': backgroundColor,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'],
      name: map['name'],
      backgroundColor: map['backgroundColor'],
    );
  }
} 