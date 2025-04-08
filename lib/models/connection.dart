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

class Connection {
  final int id;
  final int sourceNoteId;
  final int targetNoteId;
  final String type;
  final DateTime createdAt;

  Connection({
    required this.id,
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.type,
    required this.createdAt,
  });

  Connection copy({
    int? id,
    int? sourceNoteId,
    int? targetNoteId,
    String? type,
    DateTime? createdAt,
  }) {
    return Connection(
      id: id ?? this.id,
      sourceNoteId: sourceNoteId ?? this.sourceNoteId,
      targetNoteId: targetNoteId ?? this.targetNoteId,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source_note_id': sourceNoteId,
      'target_note_id': targetNoteId,
      'type': type,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Connection.fromMap(Map<String, dynamic> map) {
    return Connection(
      id: map['id'],
      sourceNoteId: map['source_note_id'],
      targetNoteId: map['target_note_id'],
      type: map['type'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
} 