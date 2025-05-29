enum CollaborativeDatabaseRole {
  owner('owner', 'Владелец'),
  collaborator('collaborator', 'Соавтор');

  const CollaborativeDatabaseRole(this.value, this.displayName);

  final String value;
  final String displayName;

  static CollaborativeDatabaseRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'owner':
        return CollaborativeDatabaseRole.owner;
      case 'collaborator':
      case 'editor':
        return CollaborativeDatabaseRole.collaborator;
      default:
        return CollaborativeDatabaseRole.collaborator;
    }
  }

  bool get canEdit => this == owner || this == collaborator;
  bool get canDelete => this == owner;
  bool get canManageUsers => this == owner;
  bool get canInviteUsers => this == owner;
  bool get canLeave => this == collaborator; // Владелец не может покинуть базу, только удалить её
}

class CollaborativeDatabaseUser {
  final String userId;
  final String email;
  final String? displayName;
  final String? photoURL;
  final CollaborativeDatabaseRole role;
  final DateTime joinedAt;

  CollaborativeDatabaseUser({
    required this.userId,
    required this.email,
    this.displayName,
    this.photoURL,
    required this.role,
    required this.joinedAt,
  });

  factory CollaborativeDatabaseUser.fromJson(Map<String, dynamic> json) {
    return CollaborativeDatabaseUser(
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? json['displayName']?.toString(),
      photoURL: json['photo_url']?.toString() ?? json['photoURL']?.toString(),
      role: CollaborativeDatabaseRole.fromString(json['role']?.toString() ?? 'collaborator'),
      joinedAt: json['joined_at'] != null 
          ? DateTime.parse(json['joined_at']) 
          : json['joinedAt'] != null 
              ? DateTime.parse(json['joinedAt'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'display_name': displayName,
      'photo_url': photoURL,
      'role': role.value,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  CollaborativeDatabaseUser copyWith({
    String? userId,
    String? email,
    String? displayName,
    String? photoURL,
    CollaborativeDatabaseRole? role,
    DateTime? joinedAt,
  }) {
    return CollaborativeDatabaseUser(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollaborativeDatabaseUser &&
        other.userId == userId &&
        other.email == email &&
        other.displayName == displayName &&
        other.photoURL == photoURL &&
        other.role == role &&
        other.joinedAt == joinedAt;
  }

  @override
  int get hashCode {
    return userId.hashCode ^
        email.hashCode ^
        displayName.hashCode ^
        photoURL.hashCode ^
        role.hashCode ^
        joinedAt.hashCode;
  }
} 