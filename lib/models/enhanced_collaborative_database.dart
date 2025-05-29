import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'collaborative_database_role.dart';

class EnhancedCollaborativeDatabase {
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final DateTime lastModified;
  final List<CollaborativeDatabaseUser> users;
  final String version;
  final bool isActive;
  final DateTime? lastSyncTime;
  final DateTime lastSync;
  final bool isOnline;
  final int pendingChanges;
  final Map<String, dynamic> metadata;

  EnhancedCollaborativeDatabase({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.lastModified,
    required this.users,
    required this.version,
    this.isActive = true,
    this.lastSyncTime,
    required this.lastSync,
    this.isOnline = false,
    this.pendingChanges = 0,
    this.metadata = const {},
  });

  factory EnhancedCollaborativeDatabase.fromJson(Map<String, dynamic> json) {
    final usersRaw = json['users'] ?? json['collaborators'] ?? [];
    final List<CollaborativeDatabaseUser> usersList = [];

    if (usersRaw is List) {
      for (final userJson in usersRaw) {
        if (userJson is Map<String, dynamic>) {
          usersList.add(CollaborativeDatabaseUser.fromJson(userJson));
        }
      }
    } else if (usersRaw is Map) {
      // Поддержка старого формата collaborators
      usersRaw.forEach((userId, roleString) {
        usersList.add(CollaborativeDatabaseUser(
          userId: userId.toString(),
          email: '', // Будет заполнено позже
          role: CollaborativeDatabaseRole.fromString(roleString.toString()),
          joinedAt: DateTime.now(),
        ));
      });
    }

    return EnhancedCollaborativeDatabase(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? json['owner_user_id']?.toString() ?? '',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : json['created_at'] != null 
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      lastModified: json['lastModified'] != null 
          ? DateTime.parse(json['lastModified']) 
          : json['updated_at'] != null 
              ? DateTime.parse(json['updated_at'])
              : DateTime.now(),
      users: usersList,
      version: json['version']?.toString() ?? '1',
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
      lastSyncTime: json['lastSyncTime'] != null 
          ? DateTime.parse(json['lastSyncTime']) 
          : json['last_sync_time'] != null 
              ? DateTime.parse(json['last_sync_time'])
              : null,
      lastSync: json['lastSync'] != null 
          ? DateTime.parse(json['lastSync']) 
          : json['last_sync'] != null 
              ? DateTime.parse(json['last_sync'])
              : DateTime.now(),
      isOnline: json['isOnline'] as bool? ?? json['is_online'] as bool? ?? false,
      pendingChanges: json['pendingChanges'] as int? ?? json['pending_changes'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'users': users.map((user) => user.toJson()).toList(),
      'version': version,
      'isActive': isActive,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'lastSync': lastSync.toIso8601String(),
      'isOnline': isOnline,
      'pendingChanges': pendingChanges,
      'metadata': metadata,
    };
  }

  EnhancedCollaborativeDatabase copyWith({
    String? id,
    String? name,
    String? ownerId,
    DateTime? createdAt,
    DateTime? lastModified,
    List<CollaborativeDatabaseUser>? users,
    String? version,
    bool? isActive,
    DateTime? lastSyncTime,
    DateTime? lastSync,
    bool? isOnline,
    int? pendingChanges,
    Map<String, dynamic>? metadata,
  }) {
    return EnhancedCollaborativeDatabase(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      users: users ?? this.users,
      version: version ?? this.version,
      isActive: isActive ?? this.isActive,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSync: lastSync ?? this.lastSync,
      isOnline: isOnline ?? this.isOnline,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      metadata: metadata ?? this.metadata,
    );
  }

  // Методы для работы с ролями
  bool isOwner(String userId) => ownerId == userId;
  
  CollaborativeDatabaseUser? getUser(String userId) {
    try {
      return users.firstWhere((user) => user.userId == userId);
    } catch (e) {
      return null;
    }
  }

  CollaborativeDatabaseRole? getUserRole(String userId) {
    final user = getUser(userId);
    return user?.role;
  }

  bool canEdit(String userId) {
    if (isOwner(userId)) return true;
    final role = getUserRole(userId);
    return role?.canEdit ?? false;
  }

  bool canDelete(String userId) {
    return isOwner(userId);
  }

  bool canManageUsers(String userId) {
    return isOwner(userId);
  }

  bool canInviteUsers(String userId) {
    return isOwner(userId);
  }

  bool canLeave(String userId) {
    if (isOwner(userId)) return false; // Владелец не может покинуть базу
    return getUser(userId) != null;
  }

  // Методы для работы с синхронизацией
  bool get needsSync => pendingChanges > 0 || 
      (lastSyncTime != null && DateTime.now().difference(lastSyncTime!).inMinutes > 15);

  bool get isOutdated => lastSyncTime != null && 
      DateTime.now().difference(lastSyncTime!).inHours > 24;

  String get syncStatus {
    if (!isOnline) return 'Офлайн';
    if (pendingChanges > 0) return 'Есть несинхронизированные изменения';
    if (needsSync) return 'Требуется синхронизация';
    return 'Синхронизировано';
  }

  // Получение списка соавторов (без владельца)
  List<CollaborativeDatabaseUser> get collaborators {
    return users.where((user) => user.userId != ownerId).toList();
  }

  // Получение владельца
  CollaborativeDatabaseUser? get owner {
    return getUser(ownerId);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnhancedCollaborativeDatabase &&
        other.id == id &&
        other.name == name &&
        other.ownerId == ownerId &&
        other.createdAt == createdAt &&
        other.lastModified == lastModified &&
        listEquals(other.users, users) &&
        other.version == version &&
        other.isActive == isActive &&
        other.lastSyncTime == lastSyncTime &&
        other.lastSync == lastSync &&
        other.isOnline == isOnline &&
        other.pendingChanges == pendingChanges &&
        mapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        ownerId.hashCode ^
        createdAt.hashCode ^
        lastModified.hashCode ^
        users.hashCode ^
        version.hashCode ^
        isActive.hashCode ^
        lastSyncTime.hashCode ^
        lastSync.hashCode ^
        isOnline.hashCode ^
        pendingChanges.hashCode ^
        metadata.hashCode;
  }
} 