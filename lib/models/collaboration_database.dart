class CollaborationDatabase {
  final String id;
  final String userId;
  final DateTime createdAt;
  final String databaseName;
  final String connectionString;

  CollaborationDatabase({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.databaseName,
    required this.connectionString,
  });

  factory CollaborationDatabase.fromJson(Map<String, dynamic> json) {
    return CollaborationDatabase(
      id: json['id'],
      userId: json['userId'],
      createdAt: DateTime.parse(json['createdAt']),
      databaseName: json['databaseName'],
      connectionString: json['connectionString'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
      'databaseName': databaseName,
      'connectionString': connectionString,
    };
  }
} 