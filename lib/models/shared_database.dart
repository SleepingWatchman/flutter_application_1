import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SharedDatabase {
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final List<String> collaborators;
  final String serverId;
  final String databasePath;
  final bool isOwner;
  final DateTime? lastSync;

  SharedDatabase({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.collaborators,
    required this.serverId,
    required this.databasePath,
    required this.isOwner,
    this.lastSync,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'name': name,
      'owner_id': ownerId,
      'created_at': createdAt.toIso8601String(),
      'collaborators': jsonEncode(collaborators),
      'database_path': databasePath,
      'is_owner': isOwner ? 1 : 0,
      'last_sync': lastSync?.toIso8601String(),
    };
  }

  factory SharedDatabase.fromMap(Map<String, dynamic> map) {
    List<String> parseCollaborators(dynamic collaboratorsJson) {
      if (collaboratorsJson == null) return [];
      try {
        if (collaboratorsJson is String) {
          final List<dynamic> list = jsonDecode(collaboratorsJson);
          return list.map((e) => e.toString()).toList();
        }
        return [];
      } catch (e) {
        print('Ошибка при парсинге collaborators: $e');
        return [];
      }
    }

    return SharedDatabase(
      id: map['id'] as String,
      serverId: map['server_id'] as String,
      name: map['name'] as String,
      ownerId: map['owner_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      collaborators: parseCollaborators(map['collaborators']),
      databasePath: map['database_path'] as String,
      isOwner: map['is_owner'] == 1,
      lastSync: map['last_sync'] != null ? DateTime.parse(map['last_sync'] as String) : null,
    );
  }

  factory SharedDatabase.fromJson(Map<String, dynamic> json) {
    return SharedDatabase(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
      collaborators: json['collaborators'] != null 
          ? List<String>.from(json['collaborators'])
          : [],
      serverId: json['id']?.toString() ?? '',
      databasePath: 'shared_${json['id']}.db',
      isOwner: json['isOwner'] ?? false,
      lastSync: json['lastSync'] != null 
          ? DateTime.parse(json['lastSync'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'createdAt': createdAt.toIso8601String(),
      'collaborators': collaborators,
      'serverId': serverId,
      'databasePath': databasePath,
      'isOwner': isOwner,
      'lastSync': lastSync?.toIso8601String(),
    };
  }

  SharedDatabase copyWith({
    String? id,
    String? name,
    String? ownerId,
    DateTime? createdAt,
    List<String>? collaborators,
    String? serverId,
    String? databasePath,
    bool? isOwner,
    DateTime? lastSync,
  }) {
    return SharedDatabase(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      collaborators: collaborators ?? this.collaborators,
      serverId: serverId ?? this.serverId,
      databasePath: databasePath ?? this.databasePath,
      isOwner: isOwner ?? this.isOwner,
      lastSync: lastSync ?? this.lastSync,
    );
  }
} 