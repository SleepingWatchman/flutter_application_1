class SharedDatabaseAccess {
  final String userId;
  final String databaseId;
  final bool isOwner;
  final DateTime joinedAt;

  SharedDatabaseAccess({
    required this.userId,
    required this.databaseId,
    required this.isOwner,
    required this.joinedAt,
  });

  factory SharedDatabaseAccess.fromJson(Map<String, dynamic> json) {
    return SharedDatabaseAccess(
      userId: json['userId'],
      databaseId: json['databaseId'],
      isOwner: json['isOwner'],
      joinedAt: DateTime.parse(json['joinedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'databaseId': databaseId,
      'isOwner': isOwner,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }
} 