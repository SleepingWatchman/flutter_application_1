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
      'fromId': fromId,
      'toId': toId,
      'name': name,
      'connectionColor': connectionColor,
    };
  }

  factory ConnectionDB.fromMap(Map<String, dynamic> map) {
    return ConnectionDB(
      id: map['id'],
      fromId: map['fromId'],
      toId: map['toId'],
      name: map['name'] ?? "",
      connectionColor: map['connectionColor'] ?? 0xFF00FFFF,
    );
  }
} 