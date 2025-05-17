import 'dart:convert';
import 'package:flutter/foundation.dart';

enum CollaborativeDatabaseRole {
  owner,
  collaborator
}

class CollaborativeDatabase {
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final DateTime lastModified;
  final Map<String, CollaborativeDatabaseRole> collaborators;
  final String version;
  final bool isActive;
  final DateTime? lastSyncTime;
  final DateTime lastSync;

  CollaborativeDatabase({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.lastModified,
    required this.collaborators,
    required this.version,
    this.isActive = true,
    this.lastSyncTime,
    required this.lastSync,
  });

  factory CollaborativeDatabase.fromJson(Map<String, dynamic> json) {
    final collaboratorsRaw = json['collaborators'];
    final Map<String, CollaborativeDatabaseRole> collaboratorsMap = {};

    if (collaboratorsRaw is Map) {
      collaboratorsRaw.forEach((key, value) {
        collaboratorsMap[key.toString()] = CollaborativeDatabaseRole.values.firstWhere(
          (role) => role.toString() == value.toString(),
          orElse: () => CollaborativeDatabaseRole.collaborator,
        );
      });
    }

    return CollaborativeDatabase(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified']) : DateTime.now(),
      collaborators: collaboratorsMap,
      version: json['version']?.toString() ?? '1',
      isActive: json['isActive'] as bool? ?? true,
      lastSyncTime: json['lastSyncTime'] != null ? DateTime.parse(json['lastSyncTime']) : DateTime.now(),
      lastSync: json['lastSync'] != null ? DateTime.parse(json['lastSync']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'collaborators': collaborators.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      'version': version,
      'isActive': isActive,
      'lastSyncTime': lastSyncTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'lastSync': lastSync.toIso8601String(),
    };
  }

  CollaborativeDatabase copyWith({
    String? id,
    String? name,
    String? ownerId,
    DateTime? createdAt,
    DateTime? lastModified,
    Map<String, CollaborativeDatabaseRole>? collaborators,
    String? version,
    bool? isActive,
    DateTime? lastSyncTime,
    DateTime? lastSync,
  }) {
    return CollaborativeDatabase(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      collaborators: collaborators ?? this.collaborators,
      version: version ?? this.version,
      isActive: isActive ?? this.isActive,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSync: lastSync ?? this.lastSync,
    );
  }

  bool isOwner(String userId) => ownerId == userId;
  bool isCollaborator(String userId) => collaborators.containsKey(userId);
  bool canEdit(String userId) => isOwner(userId) || isCollaborator(userId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollaborativeDatabase &&
        other.id == id &&
        other.name == name &&
        other.ownerId == ownerId &&
        other.createdAt == createdAt &&
        other.lastModified == lastModified &&
        mapEquals(other.collaborators, collaborators) &&
        other.version == version &&
        other.isActive == isActive &&
        other.lastSyncTime == lastSyncTime &&
        other.lastSync == lastSync;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        ownerId.hashCode ^
        createdAt.hashCode ^
        lastModified.hashCode ^
        collaborators.hashCode ^
        version.hashCode ^
        isActive.hashCode ^
        lastSyncTime.hashCode ^
        lastSync.hashCode;
  }
} 