import 'package:flutter/material.dart';

/// Модель соединения заметок (для работы с БД)
class ConnectionDB {
  int? id;
  int fromId;
  int toId;
  String name;
  int connectionColor; // цвет в формате ARGB

  ConnectionDB({
    this.id,
    required this.fromId,
    required this.toId,
    this.name = "",
    this.connectionColor = 0xFF00FFFF, // например, дефолтный – ярко-циановый
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'from_note_id': fromId,
      'to_note_id': toId,
      'name': name,
      'connection_color': connectionColor,
    };
  }

  factory ConnectionDB.fromMap(Map<String, dynamic> map) {
    return ConnectionDB(
      id: map['id'],
      fromId: map['from_note_id'] ?? 0,
      toId: map['to_note_id'] ?? 0,
      name: map['name'] ?? "",
      connectionColor: map['connection_color'] ?? 0xFF00FFFF,
    );
  }
} 